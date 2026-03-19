from __future__ import annotations
from typing import List, Dict, Any, Union, Optional, cast

import os
import copy
import argparse
import pprint
import subprocess
import pyone  # type: ignore
from .ssh_manager import SshManager
from ..models.enums import DiskType, ImageType
from .base_manager import BaseManager

# OpenNebula authentication
ONE_TOKEN = "oneadmin:oneadmin"
ONE_AUTH_FILE = "/var/lib/one/.one/one_auth"
ONE_API_URL = "http://localhost:2633/RPC2"

QOSCLASS_ORDER: Dict[DiskType, List[str]] = {
    # Order is from highest to lowest priority.
    DiskType.PERSISTENT: [
        "disk_qosclass",
        "img_qosclass",
        "vm_qosclass",
        "sys_ds_qosclass",
        "img_ds_qosclass",
    ],
    DiskType.VOLATILE: [
        "disk_qosclass",
        "vm_qosclass",
        "sys_ds_qosclass",
        "img_ds_qosclass",
    ],
    DiskType.CDROM: [
        "disk_qosclass",
        "vm_qosclass",
        "sys_ds_qosclass",
        "img_ds_qosclass",
    ],
    DiskType.NONPERSISTENT: [
        "disk_qosclass",
        "vm_qosclass",
        "sys_ds_qosclass",
        "img_ds_qosclass",
    ],
    DiskType.CONTEXT: [
        "disk_qosclass",
        "vm_qosclass",
        "sys_ds_qosclass",
        "img_ds_qosclass",
    ],
    DiskType.NVRAM: [
        "vm_qosclass",
        "sys_ds_qosclass",
    ],
    DiskType.CHECKPOINT: [
        "vm_qosclass",
        "sys_ds_qosclass",
    ],
}


class oneManager(BaseManager):
    """Manages OpenNebula connection and operations"""

    ds_images: Dict[str, Any] = {}
    vm_disks: Dict[str, Any] = {}
    one_hosts: Dict[str, Any] = {}
    one_datastores: Dict[int, Any] = {}
    vm_ids: List[int] = []

    def get_one_token(self) -> str:
        """Get OpenNebula token"""
        one_token: str = ONE_TOKEN
        if hasattr(self.args, "one_token") and self.args.one_token:
            one_token = self.args.one_token
        else:
            one_auth_file: str = os.getenv("ONE_AUTH", ONE_AUTH_FILE)  # type: ignore[attr-defined] # noqa: E501
            if os.path.exists(one_auth_file):  # type: ignore[attr-defined]
                with open(one_auth_file, "r", encoding="utf-8") as f:
                    one_token = f.read().strip()
        return one_token

    def __init__(self, args: argparse.Namespace, ssh_mngr: SshManager):
        super().__init__(args)
        self.ssh = ssh_mngr
        # Use ONE_TOKEN
        one_token: str = self.get_one_token()
        one_api_url: str = os.getenv("ONE_API_URL", ONE_API_URL)  # type: ignore[attr-defined] # noqa: E501
        try:
            self.api = pyone.OneServer(one_api_url, session=one_token)
        except Exception as err:
            print(f"Error initializing OpenNebula API! {err}")
            raise err
        self._init_datastores()
        self._init_hosts()
        self._init_vmids()
        self._init_ds_images()
        self._get_vm_disks()

    def _init_vmids(self) -> None:
        """List of VM IDs"""
        # onevm = one_api.vmpool.info(-1, -1, -1, -1)
        self.vm_ids: List[int] = []
        cmd = ["onevm", "list", "--list", "ID", "--csv", "--no-pager"]
        try:
            res = subprocess.run(cmd, capture_output=True, check=True)
            if res.returncode == 0:
                out = res.stdout.decode("utf-8")
                for line in out.splitlines():
                    if line.isnumeric():
                        self.vm_ids.append(int(line))
        except subprocess.CalledProcessError as error:
            self.err(f"{error=}")
            raise error
        self.dbg(5, f"self.vm_ids = {self.vm_ids}")

    def _init_hosts(self) -> None:
        """Get OpenNebula hosts"""
        self.dbg(6, "get_hosts")
        onehosts = self.api.hostpool.info(-1, -1, -1, -1)
        for host_e in onehosts.get_HOST():
            host_r: Dict[str, Any] = {}
            hostname: str = host_e.NAME
            host_r["name"] = hostname
            host_r["id"] = int(host_e.ID)
            host_r["state"] = int(host_e.STATE)
            host_r["vm_mad"] = str(host_e.VM_MAD)
            if host_r["state"] < 3:
                try:
                    host_r["links"] = self.ssh.get_symlinks(hostname)
                except self.ssh.SshManagerError as error:  # type: ignore[attr-defined] # noqa: E501
                    print(f"Error: {error=}; {hostname=}")
                except Exception as error:
                    print(f"Error: {error=}; {hostname=}")
                    # raise error
            self.one_hosts[hostname] = host_r
        self.dbg(2, f"self.one_hosts = \n{pprint.pformat(self.one_hosts)}")

    def _init_datastores(self) -> None:
        """Get OpenNebula datastores"""
        self.dbg(6, "get_datastores")
        one_datastores = self.api.datastorepool.info(-1, -1, -1, -1)
        for datastore_e in one_datastores.get_DATASTORE():
            datastore_r: Dict[str, Any] = {}
            datastore_r["name"] = datastore_e.NAME
            datastore_r["id"] = int(datastore_e.ID)
            datastore_r["state"] = int(datastore_e.STATE)
            datastore_r["type"] = int(datastore_e.TYPE)
            datastore_r["disk_type"] = datastore_e.DISK_TYPE
            datastore_r["ZDBG"] = "_init_datastores"
            datastore_r["qosclass"] = datastore_e.TEMPLATE.get("SP_QOSCLASS", self.args.default_qosclass)  # noqa: E501
            self.one_datastores[datastore_e.ID] = datastore_r
        self.dbg(2, f"self.one_datastores = \n{pprint.pformat(self.one_datastores)}")  # noqa: E501

    def _host_symlinks(self, vm_e: Any) -> Dict[str, Any]:
        """get symlinks from hosts data, if any"""
        links: Dict[str, Any] = {}
        vm_id: int = int(vm_e.ID)
        ds_id: int = int(vm_e.HISTORY_RECORDS.HISTORY[-1].DS_ID)
        host: str = vm_e.HISTORY_RECORDS.HISTORY[-1].HOSTNAME
        if vm_e.STATE in [3, 8] and vm_e.LCM_STATE in [0, 3]:
            # VM is Running or PowerOff
            if host in self.one_hosts:
                host_e: Dict[str, Any] = self.one_hosts[host]
                if "links" in host_e:
                    if ds_id in host_e["links"]:
                        if vm_id in host_e["links"][ds_id]:
                            links = host_e["links"][ds_id][vm_id]
        self.dbg(5, f"links = \n{pprint.pformat(links)}")
        return links

    def _qosclass_selector(
        self,
        disktype: DiskType,
        disk_id: Optional[int],
        img_qosclass: Optional[str],
        vm_qosclass: str,
        img_ds_id: Optional[int],
        sys_ds_id: Optional[int],
    ) -> str:
        """Calculate disk QoS class"""
        qosclass_data: Dict[str, Any] = {}
        return_qosclass: str = self.args.default_qosclass
        # build options
        if sys_ds_id is not None and sys_ds_id in self.one_datastores:
            qosclass_data["sys_ds_qosclass"] = self.one_datastores[
                sys_ds_id
            ].get("qosclass")
        if img_ds_id is not None and img_ds_id in self.one_datastores:
            qosclass_data["img_ds_qosclass"] = self.one_datastores[
                img_ds_id
            ].get("qosclass")
        if img_qosclass:
            qosclass_data["img_qosclass"] = img_qosclass
        if vm_qosclass:
            qosclass_data["vm_qosclass"] = vm_qosclass.split(';')[0]
            perdisk: List[str] = vm_qosclass.split(';')
            if len(perdisk) > 1:
                for _entry in perdisk:
                    perdisk_entry: List[str] = _entry.split(':')
                    if len(perdisk_entry) == 2:
                        if (
                            disk_id is not None
                            and int(perdisk_entry[0]) == disk_id
                        ):
                            qosclass_data["disk_qosclass"] = perdisk_entry[1]

        # select qosclass
        matched_qosclass: str = "n/a"
        for qosclass_name in QOSCLASS_ORDER[disktype]:
            if qosclass_name in qosclass_data:
                if qosclass_data[qosclass_name] is not None:
                    return_qosclass = qosclass_data[qosclass_name]
                    matched_qosclass = qosclass_name
                    break
        else:
            return_qosclass = self.args.default_qosclass
            matched_qosclass = "default"
        self.dbg(
            5,
            f"{disktype.name} {disk_id=} {return_qosclass=} "
            f"{matched_qosclass=} {qosclass_data=}",
        )
        return return_qosclass

    def _prepare_vm_disk(self, vdata: Dict[str, Any]) -> Dict[str, Any]:
        """Volume dict building helper"""
        self.dbg(6, f"{vdata=}")
        img_ds_id: int = vdata["img_ds_id"]
        v_info: Dict[str, Union[str, int, bool, DiskType]] = {
            "vm_id": int(vdata["vm_id"]),
            "disk_id": int(vdata["disk_id"]),
            "snapshot": False,
            "sys_ds_id": int(vdata["sys_ds_id"]),
            "img_ds_id": img_ds_id,
            "link": "/var/lib/one/datastores"
            f"/{vdata['sys_ds_id']}/{vdata['vm_id']}"
            f"/disk.{vdata['disk_id']}",
            "ZDBG": "_prepare_vm_disk",
        }
        v_name: str = vdata["one_px"]
        img_qosclass: Optional[str] = None
        if (
            "image_id" in vdata
            and vdata["image_id"] is not None
            and img_ds_id > 0
        ):
            v_name = f"{v_name}-img-{vdata['image_id']}"
            if "type" in vdata and vdata["type"] == "CDROM":
                v_name = f"{v_name}-{vdata['vm_id']}-{vdata['disk_id']}"
                v_info["disktype"] = DiskType.CDROM
            elif "clone" in vdata and vdata["clone"] == "YES":
                v_name = f"{v_name}-{vdata['vm_id']}-{vdata['disk_id']}"
                v_info["disktype"] = DiskType.NONPERSISTENT
            else:
                v_info["disktype"] = DiskType.PERSISTENT
            v_info["legacy"] = v_name
            if v_name in self.ds_images:
                img_qosclass = self.ds_images[v_name].get("qosclass")
        else:
            v_name = f"{v_name}-sys-{vdata['vm_id']}-{vdata['disk_id']}"
            v_info["disktype"] = DiskType.VOLATILE
            v_info["volatile"] = vdata["type"]
            legacy_suffix: str = "raw"
            if v_info["volatile"] == "swap":
                legacy_suffix = "swap"
            v_info["legacy"] = f"{v_name}-{legacy_suffix}"
            if "fs" in vdata and vdata["fs"]:
                v_info["fs"] = vdata["fs"]
        v_info["spname"] = v_name
        v_info["img"] = v_name
        v_info["qosclass"] = self._qosclass_selector(
            cast(DiskType, v_info["disktype"]),
            cast(Optional[int], v_info["disk_id"]),
            img_qosclass,
            vdata["qosclass"],
            vdata["img_ds_id"],
            vdata["sys_ds_id"],
        )
        v_info["vc-policy"] = vdata["vc-policy"]
        return v_info

    def _get_vm_snapshots(self, vm_e: Any) -> List[str]:
        """Get list of VM snapshots"""
        vm_snaps_list: List[str] = []
        if "SNAPSHOT" in vm_e.TEMPLATE.keys():
            snapshot_e: Union[dict[str, Any], list[Any]] = vm_e.TEMPLATE.get("SNAPSHOT")  # noqa: E501
            snapshots: List[Any] = [snapshot_e]
            if isinstance(snapshot_e, list):
                snapshots = snapshot_e
            for snapshot in snapshots:
                vm_snaps_list.append(snapshot.get("HYPERVISOR_ID"))
        self.dbg(4, f"VM {vm_e.ID} vm_snaps_list = {vm_snaps_list}")
        return vm_snaps_list

    def _get_disk_snapshots(self, vm_e: Any) -> Dict[int, List[int]]:
        """Get VM disk snapshots"""
        disk_snaps: Dict[int, List[int]] = {}
        if isinstance(vm_e.SNAPSHOTS, list):
            for snapshots_e in vm_e.SNAPSHOTS:
                disk_id: int = int(snapshots_e.DISK_ID)
                disk_snaps[disk_id] = []
                if isinstance(snapshots_e.SNAPSHOT, list):
                    for snapshot in snapshots_e.SNAPSHOT:
                        disk_snaps[disk_id].append(int(snapshot.ID))
        self.dbg(4, f"VM {vm_e.ID} disk_snaps = {disk_snaps}")
        return disk_snaps

    def _init_ds_images(self) -> None:
        """Get registeredOpenNebula Images"""
        oneimg: Any = self.api.imagepool.info(-1, -1, -1, -1)
        for img_e in oneimg.get_IMAGE():
            spname: str = f"{self.args.one_px}-img-{img_e.ID}"
            img_dict: Dict[str, Any] = {
                "image_id": int(img_e.ID),
                "legacy": spname,
                "spname": spname,
                "img": spname,
                "imagetype": ImageType(int(img_e.TYPE)),
                "disktype": DiskType(int(img_e.PERSISTENT)),
                "vmlist": img_e.VMS.get_ID(),
                "state": int(img_e.STATE),
                "name": img_e.NAME,
                "snapshot": True,
                "virt": "one",
                "nloc": self.args.one_px,
                "qosclass": img_e.TEMPLATE.get("SP_QOSCLASS"),
                "datastore_id": int(img_e.DATASTORE_ID),
                "ZDBG": "_get_ds_images",
            }
            img_dict["vms"] = len(img_dict["vmlist"])
            if img_dict["disktype"] == DiskType.PERSISTENT:
                if img_dict["vms"] > 0:
                    img_dict["snapshot"] = False
                    img_dict["vm_id"] = img_dict["vmlist"][0]
            img_dict["snapshots"] = {}
            for snapshot in img_e.SNAPSHOTS.SNAPSHOT:
                snap_id: int = int(snapshot.ID)  # type: ignore[annotation-unchecked] # noqa: E501
                snap: str = f"snap{snap_id}"
                snap_entry = {
                    "id": snap_id,
                    "legacy": f"{spname}-{snap}",
                    "spname": f"{spname}-{snap}",
                    "img": spname,
                    "snap": snap,
                    "size": int(snapshot.SIZE),
                    "snapshot": True,
                    "virt": "one",
                    "nloc": self.args.one_px,
                    "ZDBG": "_get_ds_images",
                }
                # fmt: off
                if (
                    img_dict["disktype"] == DiskType.PERSISTENT
                    and img_dict["vms"] > 0
                ):
                    # fmt: on
                    snap_entry["vms"] = img_dict["vms"]
                else:
                    snap_entry["vms"] = 0
                img_dict["snapshots"][f"{spname}-{snap}"] = snap_entry
            img_dict["snaplen"] = len(img_dict["snapshots"])
            self.ds_images[spname] = img_dict
        self.dbg(2, f"self.ds_images = \n{pprint.pformat(self.ds_images)}")

    def _get_disk_symlink(
        self,
        disk_id: int,
        links: Dict[str, str],
    ) -> Optional[str]:
        """Generate disk target"""
        if f"disk.{disk_id}" in links:
            return links[f"disk.{disk_id}"]
        return None

    def _get_vm_disks_list(self, vm_element: Any) -> List[Dict[str, Any]]:
        """Get list of the VM disks"""
        disk_element: Union[dict[str, Any], list[Any]] = vm_element.TEMPLATE.get("DISK")  # noqa: E501
        return (
            disk_element if isinstance(disk_element, list) else [disk_element]
        )

    def _process_vm_system_disks(
        self,
        vm_e: Any,
        sys_ds_id: int,
        vm_snaps_list: List[str],
        links: Dict[str, str],
    ) -> Dict[str, Any]:
        """Get VM system disks/volumes"""
        vc_policy: str = vm_e.USER_TEMPLATE.get("VC_POLICY")
        vm_qosclass: str = vm_e.USER_TEMPLATE.get("SP_QOSCLASS")
        self.dbg(
            6,
            f"** VM {vm_e.ID} {sys_ds_id=} {vm_qosclass=} {vc_policy=}",
        )
        vm_disks: Dict[str, Any] = {}
        vm_id: int = int(vm_e.ID)
        host: str = vm_e.HISTORY_RECORDS.HISTORY[-1].HOSTNAME
        state: int = int(vm_e.STATE)
        lcm_state: int = int(vm_e.LCM_STATE)
        # CONTEXTUALIZATION disk
        entry: Union[dict[str, Any], None] = vm_e.TEMPLATE.get("CONTEXT")
        v_name: str = ""
        v_info: Dict[str, Any] = {}
        snap_dict: Dict[str, Any] = {}
        if entry is not None:
            disk_id: int = int(entry.get("DISK_ID"))  # type: ignore[arg-type]
            v_name = f"{self.args.one_px}-sys-{vm_id}-{disk_id}"
            v_info = {
                "spname": v_name,
                "img": v_name,
                "legacy": f"{v_name}-iso",
                "disktype": DiskType.CONTEXT,
                "disk_id": disk_id,
                "vm_id": vm_id,
                "nloc": self.args.one_px,
                "virt": "one",
                "snapshot": False,
                "sys_ds_id": sys_ds_id,
                "vc-policy": vc_policy,
                "state": state,
                "lcm_state": lcm_state,
                # fmt: off
                "link": (f"/var/lib/one/datastores/{sys_ds_id}/{vm_id}"
                         f"/disk.{disk_id}"),
                # fmt: on
            }
            v_info["qosclass"] = self._qosclass_selector(
                cast(DiskType, v_info["disktype"]),
                cast(Optional[int], v_info["disk_id"]),
                None,
                vm_qosclass,
                None,
                sys_ds_id,
            )
            v_info["ZDBG"] = "_process_vm_system_disks"
            if host:
                v_info["host"] = host
            disk_str: str = f"disk.{v_info['disk_id']}"
            if disk_str in links:
                v_info["target"] = links[disk_str]
            vm_disks[v_name] = copy.deepcopy(v_info)
            for snap in vm_snaps_list:
                snapname = f"{v_name}-{snap}"
                snap_dict = copy.deepcopy(v_info)
                snap_dict["spname"] = snapname
                snap_dict["legacy"] = f"{v_info['legacy']}-{snap}"
                snap_dict["snap"] = snap
                snap_dict["snapshot"] = True
                # snapshots has no vc-policy or qc tags
                if "vc-policy" in snap_dict:
                    del snap_dict["vc-policy"]
                if "qosclass" in snap_dict:
                    del snap_dict["qosclass"]
                vm_disks[snapname] = snap_dict
        # UEFI NVRAM volume
        entry = vm_e.USER_TEMPLATE.get("T_OS_LOADER")  # noqa: E501
        if entry is not None:
            v_name = f"{self.args.one_px}-sys-{vm_id}-NVRAM"
            v_info = {
                "legacy": v_name,
                "spname": v_name,
                "img": v_name,
                "disktype": DiskType.NVRAM,
                "vm_id": vm_id,
                "nloc": self.args.one_px,
                "virt": "one",
                "snapshot": False,
                "sys_ds_id": sys_ds_id,
                "vc-policy": vc_policy,
                "state": state,
                "lcm_state": lcm_state,
            }
            v_info["qosclass"] = self._qosclass_selector(
                cast(DiskType, v_info["disktype"]),
                None,
                None,
                vm_qosclass,
                None,
                sys_ds_id,
            )
            v_info["ZDBG"] = "process_vm_system_disks"
            vm_disks[v_name] = v_info
            for snap in vm_snaps_list:
                snap_dict = copy.deepcopy(v_info)
                snap_dict["legacy"] = f"{v_info['legacy']}-{snap}"
                snap_dict["spname"] = f"{v_name}-{snap}"
                snap_dict["snap"] = snap
                snap_dict["snapshot"] = True
                if "vc-policy" in snap_dict:
                    del snap_dict["vc-policy"]
                if "qosclass" in snap_dict:
                    del snap_dict["qosclass"]
                vm_disks[snap] = snap_dict
        # VM checkpoint volume
        if int(vm_e.STATE) in [4, 5]:  # 4 - STOPPED, 5 - SUSPENDED
            v_name = f"{self.args.one_px}-sys-{vm_id}-rawcheckpoint"
            v_info = {
                "spname": v_name,
                "img": v_name,
                "legacy": v_name,
                "disktype": DiskType.CHECKPOINT,
                "vm_id": vm_id,
                "snapshot": False,
                "nloc": self.args.one_px,
                "virt": "one",
                "vc-policy": vc_policy,
                "state": state,
                "lcm_state": lcm_state,
            }
            v_info["qosclass"] = self._qosclass_selector(
                cast(DiskType, v_info["disktype"]),
                None,
                None,
                vm_qosclass,
                None,
                sys_ds_id,
            )
            v_info["ZDBG"] = "get_vm_system_disks"
            v_info["vm_id"] = f"{vm_id}"
            vm_disks[v_name] = v_info
        self.dbg(6, f"VM {vm_e.ID} RETURNING vm_disks = \n{pprint.pformat(vm_disks)}")  # noqa: E501
        return vm_disks

    def _process_vm_disks(
        self,
        vm_element: Any,
        vm_snaps_list: List[str],
        disk_snaps: Dict[int, List[int]],
        links: Dict[str, str],
    ) -> Dict[str, Any]:
        """Get VM disks"""
        vm_qosclass: str = vm_element.USER_TEMPLATE.get("SP_QOSCLASS", self.args.default_qosclass)  # noqa: E501
        vc_policy: str = vm_element.USER_TEMPLATE.get("VC_POLICY")
        self.dbg(
            6,
            f"** VM {vm_element.ID} {vm_snaps_list=}"
            + f" {disk_snaps=} {links=}"
            + f" {vm_qosclass=} {vc_policy=}",
        )
        vm_disks: Dict[str, Any] = {}
        vm_details: Dict[str, Any] = {
            "id": int(vm_element.ID),
            "ds_id": int(vm_element.HISTORY_RECORDS.HISTORY[-1].DS_ID),
            "host": vm_element.HISTORY_RECORDS.HISTORY[-1].HOSTNAME,
            "state": int(vm_element.STATE),
            "lcm_state": int(vm_element.LCM_STATE),
            "disks": [],
        }
        if vm_qosclass:
            vm_details["qosclass"] = vm_qosclass.split(';')[0]
        else:
            vm_details["qosclass"] = self.args.default_qosclass
        vm_details["disks"] = self._get_vm_disks_list(vm_element)
        for disk in vm_details["disks"]:
            disk_id: int = int(disk.get("DISK_ID"))
            img_ds_id: int = int(disk.get("DATASTORE_ID", -1))
            v_info: Dict[str, Any] = self._prepare_vm_disk(
                {
                    "one_px": self.args.one_px,
                    "vm_id": vm_details["id"],
                    "disk_id": disk_id,
                    "image_id": int(disk.get("IMAGE_ID", 0)),
                    "clone": disk.get("CLONE"),
                    "type": disk.get("TYPE"),
                    "fs": disk.get("FS", ""),
                    "sys_ds_id": vm_details["ds_id"],
                    "img_ds_id": img_ds_id,
                    "qosclass": vm_qosclass,
                    "vc-policy": vc_policy,
                }
            )
            v_info["state"] = vm_details["state"]
            v_info["lcm_state"] = vm_details["lcm_state"]
            v_info["ZDBG"] = "process_vm_disks"
            v_info["nloc"] = self.args.one_px
            v_info["virt"] = "one"
            if vm_details["host"]:
                v_info["host"] = vm_details["host"]
            v_info["target"] = self._get_disk_symlink(disk_id, links)
            diskvolume: str = v_info["spname"]
            vm_disks[diskvolume] = copy.deepcopy(v_info)
            # there are no 'link' and 'target' in snapshots...
            if "link" in v_info:
                del v_info["link"]
            if "target" in v_info:
                del v_info["target"]
            legacy: str = v_info["legacy"]
            for snap in vm_snaps_list:
                v_info["spname"] = f"{diskvolume}-{snap}"
                v_info["img"] = diskvolume
                v_info["legacy"] = f"{legacy}-{snap}"
                v_info["snap"] = snap
                v_info["snapshot"] = True
                v_info["ZDBG"] = "process_vm_disks"
                snapname = f"{diskvolume}-{v_info['snap']}"
                vm_disks[snapname] = copy.deepcopy(v_info)
                if "vc-policy" in vm_disks[snapname]:
                    del vm_disks[snapname]["vc-policy"]
                if "qosclass" in vm_disks[snapname]:
                    del vm_disks[snapname]["qosclass"]
            if disk_id in disk_snaps:
                for snapidx in disk_snaps[disk_id]:
                    snapname = f"{diskvolume}-snap{snapidx}"
                    v_info["spname"] = snapname
                    v_info["img"] = diskvolume
                    v_info["legacy"] = f"{legacy}-snap{snapidx}"
                    v_info["snap"] = f"snap{snapidx}"
                    v_info["snapshot"] = True
                    v_info["ZDBG"] = "process_vm_disks"
                    vm_disks[snapname] = copy.deepcopy(
                        v_info
                    )  # noqa
                    # snapshots has no vc-policy or qc tags
                    if "vc-policy" in vm_disks[snapname]:
                        del vm_disks[snapname]["vc-policy"]
                    if "qosclass" in vm_disks[snapname]:
                        del vm_disks[snapname]["qosclass"]

        self.dbg(
            2,
            f"VM {vm_details['id']}"
            + f" DISKS (len={len(vm_details['disks'])}):"
            + f"\n{pprint.pformat(vm_details['disks'])}",
        )
        if len(vm_details["disks"]) == 0:
            self.dbg(0, f"VM {vm_details['id']} has no DISKs!")
        self.dbg(6, f"VM {vm_element.ID} RETURNING vm_disks = \n{pprint.pformat(vm_disks)}")  # noqa: E501
        return vm_disks

    def _get_vm_disks(self) -> None:
        """Dict of VM disk volumes"""
        if self.one_hosts is None:
            self.one_hosts = self.get_hosts()
        for vm_id in self.vm_ids:
            vm_e: Any = self.api.vm.info(vm_id)
            try:
                sys_ds_id = int(vm_e.HISTORY_RECORDS.HISTORY[-1].DS_ID)
            except Exception as error:
                self.err(
                    f"VM {vm_id} '{vm_e.NAME}' {vm_e.STATE}:{vm_e.LCM_STATE}"
                    + f" Error:{error} //HISTORY_RECORDS"
                )
                raise error
            links = self._host_symlinks(vm_e)
            self.dbg(
                3,
                f">>> VM {vm_e.ID} '{vm_e.NAME}'"
                f" {vm_e.STATE}:{vm_e.LCM_STATE} {links=}",
            )
            vm_snaps_list: List[str] = self._get_vm_snapshots(vm_e)
            disk_snaps: Dict[int, List[int]] = self._get_disk_snapshots(vm_e)
            self.vm_disks.update(
                self._process_vm_disks(
                    vm_e, vm_snaps_list, disk_snaps, links
                )
            )
            self.vm_disks.update(
                self._process_vm_system_disks(
                    vm_e, sys_ds_id, vm_snaps_list, links
                )
            )

        self.dbg(2, f"END vm_disks = \n{pprint.pformat(self.vm_disks)}")

    def get_by_legacy(
        self, one_dict: Dict[str, Dict[str, Any]], entry_name: str
    ) -> Any:
        """wrapper looking for the legacy names too"""
        self.dbg(6, f"lookup {entry_name}")
        if entry_name in one_dict:
            self.dbg(5, f"FOUND {entry_name} in the dictionary")
            return one_dict[entry_name]
        for vdata in one_dict.values():
            if "legacy" in vdata and entry_name == vdata["legacy"]:
                self.dbg(5, f"FOUND {entry_name} in the dictionary (legacy)")
                return vdata
            if "snapshots" in vdata and entry_name in vdata["snapshots"]:
                self.dbg(5, f"FOUND {entry_name} in the dictionary (legacy/snapshot)")  # noqa: E501
                return vdata["snapshots"][entry_name]
        self.dbg(6, f"NO {entry_name} in the dictionary")
        return None
