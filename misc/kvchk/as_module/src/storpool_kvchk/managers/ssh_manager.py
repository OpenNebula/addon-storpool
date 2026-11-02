from __future__ import annotations
from typing import Dict, Any, List, Optional, Set, Tuple

import subprocess

from .base_manager import BaseManager
from ..models.exceptions import SshManagerError

# oned's built-in DATASTORE_LOCATION; the effective value is read from
# oned by oneManager and passed to get_symlinks()/get_local_symlinks()
DEFAULT_DS_LOCATION = "/var/lib/one/datastores"


class SshManager(BaseManager):
    """SSH operations manager"""

    def __init__(self, args: Any):
        super().__init__(args)
        # the datastore locations scanned for symlinks so far;
        # remove_symlink() only touches links under one of them
        self.ds_locations: Set[str] = set()

    @staticmethod
    def _find_cmd(ds_location: str) -> Tuple[str, ...]:
        """find(1) arguments listing the symlinks under ds_location.
        A datastore (or VM) directory could itself be a symlink, e.g.
        to another filesystem: -L descends into those, -xtype l still
        selects the symlinks themselves and ls -ld prints each link
        with its target (find's %l is empty under -L)"""
        return (
            "find", "-L", ds_location, "-xtype", "l",
            "-exec", "ls", "-ld", "{}", "+",
        )

    def _parse_symlinks(
        self, out: str, ds_location: str = DEFAULT_DS_LOCATION
    ) -> Dict[int, Dict[int, Dict[str, str]]]:
        """Parse 'ls -l' output lines into the per-datastore/VM
        symlink map"""
        symlinks: Dict[int, Dict[int, Dict[str, str]]] = {}
        root: str = ds_location.rstrip("/") + "/"
        for line in out.splitlines():
            if " -> " not in line:
                continue
            left, target = line.rsplit(" -> ", 1)
            words: List[str] = left.split()
            if not words:
                continue
            link: str = words[-1]
            # only <ds_location>/<ds_id>/<vm_id>/... links are tracked;
            # a datastore or VM directory symlink is skipped
            dpath: List[str] = link[len(root):].split("/")
            if (
                not link.startswith(root)
                or len(dpath) < 3
                or not dpath[0].isdigit()
                or not dpath[1].isdigit()
            ):
                self.dbg(1, f"skipping non-VM symlink {link}")
                continue
            ds_id: int = int(dpath[0])
            vm_id: int = int(dpath[1])
            if ds_id not in symlinks:
                symlinks[ds_id] = {}
            if vm_id not in symlinks[ds_id]:
                symlinks[ds_id][vm_id] = {}
            symlinks[ds_id][vm_id][dpath[-1]] = target.strip()
        return symlinks

    def _run_find(
        self, cmd: Tuple[str, ...], where: str, ds_location: str
    ) -> Dict[int, Dict[int, Dict[str, str]]]:
        """Run the find command and parse its output"""
        self.ds_locations.add(ds_location)
        symlinks: Dict[int, Dict[int, Dict[str, str]]] = {}
        if self.args.dummy_etcd > 1:
            self.dbg(0, f"[dummy] {cmd}")
            return symlinks
        try:
            res: subprocess.CompletedProcess[bytes] = subprocess.run(
                cmd, capture_output=True, check=True
            )
            if res.returncode == 0:
                symlinks = self._parse_symlinks(
                    res.stdout.decode("utf-8"), ds_location
                )
        except subprocess.CalledProcessError as error:
            stderr: Any = error.stderr
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            raise SshManagerError(
                f"subprocess.CalledProcessError {error=}"
                f" {str(stderr or '').strip()}",
                where,
                str(cmd),
            )
        except Exception as error:
            raise SshManagerError(
                f"Unknown error {error=}",
                where,
                str(cmd),
            )
        return symlinks

    def get_symlinks(
        self, host: str, ds_location: str = DEFAULT_DS_LOCATION
    ) -> Dict[int, Dict[int, Dict[str, str]]]:
        """ssh to a host end get the symlinks in the datastores path"""
        ssh_cmd: Tuple[str, ...] = ("ssh", host) + self._find_cmd(ds_location)
        symlinks: Dict[int, Dict[int, Dict[str, str]]] = self._run_find(
            ssh_cmd, host, ds_location
        )
        self.dbg(2, f"ssh_getsymlinks {ssh_cmd}: {symlinks}")
        return symlinks

    def get_local_symlinks(
        self, ds_location: str = DEFAULT_DS_LOCATION
    ) -> Dict[int, Dict[int, Dict[str, str]]]:
        """Get the symlinks in the datastores path on the frontend,
        where the files of the STOPPED/UNDEPLOYED VMs are expected"""
        find_cmd: Tuple[str, ...] = self._find_cmd(ds_location)
        symlinks: Dict[int, Dict[int, Dict[str, str]]] = self._run_find(
            find_cmd, "localhost", ds_location
        )
        self.dbg(2, f"get_local_symlinks {find_cmd}: {symlinks}")
        return symlinks

    def _get_vm_pid(self, host: str, vm_id: int) -> int:
        """Get the pid of the vm"""
        match: str = f"guest=one-{vm_id},"
        ssh_cmd = (
            "ssh",
            host,
            "pgrep",
            "-f",
            match,
        )
        try:
            response: subprocess.CompletedProcess[bytes] = subprocess.run(
                ssh_cmd, capture_output=True, check=True
            )
        except Exception as error:
            raise SshManagerError(
                f"Unknown error {error=}",
                self.args.host,
                str(ssh_cmd),
            )
        pid: int = int(response.stdout.decode("utf-8"))
        self.dbg(5, f"{ssh_cmd=}: {pid=}")
        return pid

    def create_symlink(
        self,
        action_data: Dict[str, Any]
    ) -> None:
        """Create symlink on the given host"""
        if "host" not in action_data["symlink"]:
            raise ValueError(
                f"Host is required for creating a symlink {action_data=}"
            )
        target: str = action_data["symlink"]["target"].replace(
            "_SP_UID_", action_data["uid"]
        )
        link: str = action_data["symlink"]["link"]
        link_dir: str = link.rsplit("/", 1)[0]
        mkdir_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "mkdir",
            "-p",
            link_dir,
        )
        ssh_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "ln",
            "-v",
            "-sfn",
            target,
            link,
        )
        try:
            if self.args.execute:
                if self.args.dry_run:
                    self.dbg(0, f"[dry-run] {mkdir_cmd=}")
                    self.dbg(0, f"[dry-run] {ssh_cmd=}")
                else:
                    if link_dir:
                        subprocess.run(
                            mkdir_cmd,
                            capture_output=True,
                            check=True,
                        )
                    response = subprocess.run(
                        ssh_cmd,
                        capture_output=True,
                        check=True,
                    )
                    if self.args.verbose > 0:
                        self.dbg(0, f"create_symlink {ssh_cmd}: {response}")
        except Exception as error:
            self.err(f"create_symlink Error! {mkdir_cmd=} {ssh_cmd=} {error=}")
            raise error

    def remove_symlink(self, action_data: Dict[str, Any]) -> None:
        """Remove a dangling symlink on the frontend/host (an undeployed
        VM leftover). Only symlinks under the datastores path are
        touched and the removal happens with --execute."""
        if "unlink" not in action_data:
            raise ValueError(
                f"unlink data is required to remove a symlink {action_data=}"
            )
        link: str = action_data["unlink"]["link"]
        host: Optional[str] = action_data["unlink"].get("host")
        roots: Set[str] = self.ds_locations or {DEFAULT_DS_LOCATION}
        if not any(link.startswith(root.rstrip("/") + "/") for root in roots):
            raise ValueError(
                "refusing to remove a symlink outside the datastores"
                f" path: {link}"
            )
        rm_cmd: Tuple[str, ...] = ("rm", "-v", link)
        if host:
            rm_cmd = ("ssh", host, "rm", "-v", link)
        try:
            if self.args.execute:
                if self.args.dry_run:
                    self.dbg(0, f"[dry-run] {rm_cmd=}")
                else:
                    response = subprocess.run(
                        rm_cmd, capture_output=True, check=True
                    )
                    if self.args.verbose > 0:
                        self.dbg(0, f"remove_symlink {rm_cmd}: {response}")
        except Exception as error:
            self.err(f"remove_symlink Error! {rm_cmd=} {error=}")
            raise error

    def _get_spdev(self, action_data: Dict[str, Any]) -> None:
        """Get the spdev for the given symlink"""
        if self.args.verbose:
            self.dbg(2, f"{action_data=}")
        if "link" not in action_data["symlink"]:
            raise ValueError(
                f"Link is required for getting the spdev {action_data=}"
            )
        link: str = action_data["symlink"]["link"]
        ssh_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "readlink",
            "-f",
            link,
        )
        try:
            response = subprocess.run(
                ssh_cmd, capture_output=True, check=True
            )
        except Exception as error:
            raise SshManagerError(
                f"Unknown error {error=}",
                action_data["symlink"]["host"],
                str(ssh_cmd),
            )
        spdev: str = response.stdout.decode("utf-8")
        self.dbg(5, f"{ssh_cmd=}: {spdev=}")
        if spdev.startswith("/dev/sp-"):
            action_data["symlink"]["spdev"] = spdev.strip("\n")
        else:
            raise ValueError(
                f"Invalid spdev {spdev=} {action_data=}"
            )

    def _mkdir_in_namespace(self, action_data: Dict[str, Any]) -> None:
        """Create a directory in the namespace"""
        if self.args.verbose:
            self.dbg(2, f"{action_data=}")
        if "spdev" not in action_data["symlink"]:
            raise ValueError(
                "Spdev is required for creating a directory"
                f" in the namespace {action_data=}"
            )
        ssh_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "nsenter",
            "-t",
            str(action_data["symlink"]["pid"]),
            "-m",
            "mkdir",
            "-p",
            "/dev/storpool-byid",
        )
        try:
            response = subprocess.run(
                ssh_cmd, capture_output=True, check=True
            )
        except Exception as error:
            raise SshManagerError(
                f"Unknown error {error=}",
                action_data["symlink"]["host"],
                str(ssh_cmd),
            )
        self.dbg(5, f"{ssh_cmd=}: {response=}")

    def symlink_in_namespace(self, action_data: Dict[str, Any]) -> None:
        """Check if the spdev is in the namespace"""
        pid: int = self._get_vm_pid(
            action_data["symlink"]["host"],
            action_data["symlink"]["vm_id"],
        )
        action_data["symlink"]["pid"] = pid
        self._mkdir_in_namespace(action_data)
        self._get_spdev(action_data)
        if "spdev" not in action_data["symlink"]:
            raise ValueError(
                f"Spdev is required for checking the namespace {action_data=}"
            )
        spdev: str = action_data["symlink"]["spdev"]
        target: str = action_data["symlink"]["target"].replace(
            "_SP_UID_", action_data["uid"]
        )
        ssh_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "nsenter",
            "-t",
            str(action_data["symlink"]["pid"]),
            "-m",
            "ln",
            "-v",
            "-sf",
            spdev,
            target,
        )
        try:
            response = subprocess.run(
                ssh_cmd, capture_output=True, check=True
            )
        except Exception as error:
            raise SshManagerError(
                f"Unknown error {error=}",
                action_data["symlink"]["host"],
                str(ssh_cmd),
            )
        if response.returncode == 0:
            action_data["symlink"]["in_namespace"] = True
        else:
            action_data["symlink"]["in_namespace"] = False
        self.dbg(5, f"{ssh_cmd=}: {action_data['symlink']['in_namespace']=}")

    def action(self, action_data: Dict[str, Any], action: str) -> None:
        """Action on the given data"""
        self.dbg(3, f"{action=} {action_data=}")
        if action == "unlink":
            self.remove_symlink(action_data)
        else:
            self.create_symlink(action_data)
        # self._get_spdev(action_data)
        # self.symlink_in_namespace(action_data)
