from __future__ import annotations
from typing import Dict, Any, List

import subprocess

from .base_manager import BaseManager
from ..models.exceptions import SshManagerError


class SshManager(BaseManager):
    """SSH operations manager"""

    def __init__(self, args: Any):
        super().__init__(args)

    def get_symlinks(self, host: str) -> Dict[int, Dict[int, Dict[str, str]]]:
        """ssh to a host end get the symlinks in the path"""
        symlinks: Dict[int, Dict[int, Dict[str, str]]] = {}
        ssh_cmd = (
            "ssh",
            host,
            "find",
            "/var/lib/one/datastores",
            "-type",
            "l",
            "-exec",
            "ls",
            "-l",
            "{}",
            r"\;",
        )
        if self.args.dummy_etcd > 1:  # pylint: disable=R1702
            self.dbg(0, f"[dummy] {ssh_cmd}")
        else:
            try:
                res: subprocess.CompletedProcess[bytes] = subprocess.run(
                    ssh_cmd, capture_output=True, check=True
                )
                if res.returncode == 0:
                    out: str = res.stdout.decode("utf-8")
                    for line in out.splitlines():
                        words: List[str] = line.split()
                        if "->" in words:
                            dpath: List[str] = words[-3].split("/")
                            ds_id: int = int(dpath[5])
                            vm_id: int = int(dpath[6])
                            if ds_id not in symlinks:
                                symlinks[ds_id] = {}
                            if vm_id not in symlinks[ds_id]:
                                symlinks[ds_id][vm_id] = {}
                            symlinks[ds_id][vm_id][dpath[-1]] = words[-1]
            except subprocess.CalledProcessError as error:
                raise SshManagerError(
                    f"subprocess.CalledProcessError {error=}",
                    host,
                    str(ssh_cmd),
                )
            except Exception as error:
                raise SshManagerError(
                    f"Unknown error {error=}",
                    host,
                    str(ssh_cmd),
                )
        self.dbg(2, f"ssh_getsymlinks {ssh_cmd}: {symlinks}")
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
        ssh_cmd = (
            "ssh",
            action_data["symlink"]["host"],
            "ln",
            "-v",
            "-sf",
            target,
            action_data["symlink"]["link"],
        )
        try:
            if self.args.execute:
                if self.args.dry_run:
                    self.dbg(0, f"[dry-run] {ssh_cmd=}")
                else:
                    response = subprocess.run(
                        ssh_cmd,
                        capture_output=True,
                        check=True,
                    )
                    if self.args.verbose > 0:
                        self.dbg(0, f"create_symlink {ssh_cmd}: {response}")
        except Exception as error:
            self.err(f"create_symlink Error! {ssh_cmd=} {error=}")
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
        self.create_symlink(action_data)
        # self._get_spdev(action_data)
        # self.symlink_in_namespace(action_data)
