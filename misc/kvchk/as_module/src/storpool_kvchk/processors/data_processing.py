from __future__ import annotations
from typing import List, Dict, Any, Optional, Tuple, Callable

import argparse
from ..managers.base_manager import BaseManager
from ..managers.ssh_manager import SshManager
from ..managers.one_manager import oneManager
from ..managers.storpool_manager import spManager
from ..managers.etcd_manager import etcdManager
from ..models.exceptions import UnhandledCase, KvByNameError, KvByUidError
from ..models.enums import DiskType, ImageType


class DataProcessing(BaseManager):
    """Analyzes data and relationships between
    OpenNebula and Etcd, and StorPool."""

    def __init__(
        self,
        args: argparse.Namespace,
        etcd_manager: etcdManager,
        sp_manager: spManager,
        one_manager: oneManager,
        ssh_manager: SshManager,
    ):
        super().__init__(args)
        self.etcd: etcdManager = etcd_manager
        self.sp: spManager = sp_manager
        self.one: oneManager = one_manager
        self.ssh: SshManager = ssh_manager
        self.update_data: Dict[str, Dict[str, Any]] = {}
        self.update_entry: Dict[str, Any] = {}

    def _get_by_legacy(self, entry_name: str) -> Optional[Dict[str, Any]]:
        """Look up entry by legacy name in OpenNebula vm_disks and ds_images"""
        # Check name in vm_disks
        if entry_name in self.one.vm_disks:
            self.dbg(5, f"{entry_name} is in one.vm_disks")
            return self.one.vm_disks[entry_name]
        # Check legacy names in vm_disks
        for vdata in self.one.vm_disks.values():
            if "legacy" in vdata:
                if entry_name == vdata["legacy"]:
                    self.dbg(5, f"{entry_name} is in one.vm_disks (legacy)")
                    return vdata
                if "snapshots" in vdata and entry_name in vdata["snapshots"]:
                    self.dbg(5, f"{entry_name} is in one.vm_disks.snapshots (legacy/snapshot)")  # noqa: E501
                    return vdata["snapshots"][entry_name]
        # Check legacy names in ds_images
        for vdata in self.one.ds_images.values():
            if "legacy" in vdata:
                if entry_name == vdata["legacy"]:
                    self.dbg(5, f"{entry_name} is in one.ds_images (legacy)")
                    return vdata
                if "snapshots" in vdata and entry_name in vdata["snapshots"]:
                    self.dbg(5, f"{entry_name} is in one.ds_images.snapshots (legacy/snapshot)")  # noqa: E501
                    return vdata["snapshots"][entry_name]
        self.dbg(6, f"{entry_name} not found in one.vm_disks or one.ds_images (or snapshots)")  # noqa: E501
        return None

    def analyze_kv_by_name(self) -> None:
        """Analyze KV byName entries"""
        self.dbg(3, "processing byName entries ...")
        for name, uid in self.etcd.data["byName"].items():
            byUid_name = None
            if uid in self.etcd.data["byUid"]:
                byUid_name = self.etcd.data["byUid"][uid]
                self._kv_check_name_uid_match(name, uid)
            else:
                self._kv_handle_missing_uid(name, uid)
            # Check for duplicate byName entries
            for name2, uid2 in self.etcd.data["byName"].items():
                if name2 != name and uid2 == uid and name2 != byUid_name:
                    self.dbg(
                        2,
                        f"[kv] byName[{name}] = {uid}"
                        f" != byName[{name2}] = {uid2}",
                    )
                    self.dbg(0, f"etcdctl del /byName/{name2}")

    def _kv_check_name_uid_match(self, name: str, uid: str) -> None:
        """Check if name matches uid entry"""
        if name != self.etcd.data["byUid"][uid]:
            self.dbg(
                2,
                f"[kv] byName[{name}] != byUid[{uid}]"
                f"={self.etcd.data['byUid'][uid]}",
            )
            # Check if uid is in StorPool
            if uid in self.sp.data:
                if self.sp.data[uid]["snapshot"]:
                    self.dbg(2, f"[kv] UID snapshot:{self.sp.data[uid]}")
                else:
                    self.dbg(2, f"[kv] UID volume:{self.sp.data[uid]}")
            # Check if name is in StorPool
            elif name in self.sp.data:
                if self.sp.data[name]["snapshot"]:
                    self.dbg(2, f"[kv] NAME snapshot:{self.sp.data[name]}")
                else:
                    self.dbg(2, f"[kv] NAME volume:{self.sp.data[name]}")
            else:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid} not in StorPool// Delete?",
                )
        else:
            # byUid/uid -> name matches byName/name
            if uid not in self.sp.data:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    " UID not in StorPool //Delete?",
                )
            elif name in self.sp.data:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    " NAME in StorPool //Migrate?",
                )

    def _kv_handle_missing_uid(self, name: str, uid: str) -> None:
        """Handle case when uid is missing from byUid"""
        if name in self.sp.data:
            if self.sp.data[name]["snapshot"]:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    + f" not in byUid but {name} snapshot exists in StorPool",
                )
            else:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    + f" not in byUid but {name} volume exists in StorPool",
                )
        elif uid in self.sp.data:
            if self.sp.data[uid]["snapshot"]:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    f" not in byUid but UID {uid} snapshot exists in StorPool",
                )
                self._update_kv_data(name, uid)
            else:
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    f" not in byUid but UID {uid} volume exists in StorPool",
                )
                self._update_kv_data(name, uid)
        else:
            self.dbg(
                2,
                f"[kv] byName[{name}] = {uid} not in byUid and StorPool",
            )

    def _update_kv_data(self, name: str, uid: str) -> None:
        """Update KV data for name/uid pair"""
        if name not in self.update_data:
            self.update_data[name] = {"data": {}, "action": []}
        if "name" not in self.update_data[name]["data"]:
            self.update_data[name]["data"]["name"] = name
        if "uid" not in self.update_data[name]["data"]:
            self.update_data[name]["data"]["uid"] = uid
        self.update_data[name]["data"]["byName"] = name
        self.update_data[name]["data"]["byUid"] = f"~{uid}"
        self.update_data[name]["action"].append("kv")

    def analyze_kv_by_uid(self) -> None:
        """Analyze KV byUid entries"""
        self.dbg(1, "processing byUid entries ...")
        for uid, name in self.etcd.data["byUid"].items():
            if name in self.etcd.data["byName"]:
                uid_by_name: str = self.etcd.data["byName"][name]
                if uid != uid_by_name:
                    if uid_by_name in self.etcd.data["byUid"]:
                        self._fix_uid_mismatch(uid, name)
                    else:
                        self.dbg(
                            2,
                            f" byUid[{uid}]={name} !="
                            f" byName[{name}]={uid_by_name}"
                            f" {uid_by_name=} not in byUid",
                        )
            else:
                one_data: Optional[Dict[str, Any]] = self._get_by_legacy(name)
                if one_data:
                    self._fix_one_data(uid, name)
                else:
                    self.dbg(2, f" byUid[{uid}] = {name} not in ONE")
                    self.dbg(0, f"etcdctl del /byUid/{uid}")

    def _fix_uid_mismatch(self, uid: str, name: str) -> None:
        """Fix uid mismatch cases"""
        if uid in self.sp.data:
            if self.sp.data[uid]["snapshot"]:
                self.dbg(
                    2,
                    f" byUid[{uid}]={name}"
                    f" has SP snapshot {self.sp.data[uid]['tags']},"
                    f" byName[{name}]={self.etcd.data['byName'][name]}",
                )
                self.dbg(0, f"etcdctl del /byUid/{uid}")
                self.dbg(0, f"storpool -M -B snapshot {uid} delete {uid}")
            else:
                self.dbg(
                    2,
                    f" byUid[{uid}]={name}"
                    f" has SP volume {self.sp.data[uid]['tags']},"
                    f" byName[{name}]={self.etcd.data['byName'][name]}",
                )
                self.dbg(0, f"etcdctl del /byUid/{uid}")
                self.dbg(0, f"storpool -M -B volume {uid} delete {uid}")
        else:
            self.dbg(0, f"etcdctl del /byUid/{uid}")

    def _fix_one_data(self, uid: str, name: str) -> None:
        """Fix OpenNebula data cases"""
        if uid in self.sp.data:
            self.dbg(
                2,
                f" byUid[{uid}] = {name} in ONE and StorPool, KV update",
            )
            if name not in self.update_data:
                self.update_data[name] = {"data": {}, "action": []}
            self.update_data[name]["data"] = {"name": name, "uid": uid}
            self.dbg(6, f"ZDBG {self.update_data=}")
            self.update_data[name]["action"].append("kvupdate")
        else:
            self.dbg(2, f" byUid[{uid}] = {name} in ONE but not in StorPool")
            raise UnhandledCase(f" byUid[{uid}] = {name} not in StorPool")

    def analyze_vm_disks(self) -> None:
        """Analyze VM disk elements"""
        self.dbg(1, "processing VM Disk elements...")
        for name, data in self.one.vm_disks.items():
            err: bool = False
            msg: str = f"VM {data['vm_id']} {name}"
            msg += f" {data['disktype'].name} disk"
            if 'snapshot' in data and data['snapshot']:
                msg += " (snapshot)"
            if name in self.etcd.data["byName"]:
                by_name_uid: str = self.etcd.data["byName"][name]
                msg += f" UID {by_name_uid} (in KV)."
                if by_name_uid in self.etcd.data["byUid"]:
                    if self.etcd.data["byUid"][by_name_uid] != name:
                        err = True
                        msg += f" {name}/{by_name_uid}"
                        msg += "in KV but byUid point to other"
                        msg += f" name:{self.etcd.data['byUid'][by_name_uid]}."
                else:
                    err = True
                    msg += f" {name}/{by_name_uid} not in byUid!"
            else:
                err = True
                if name in self.sp.data:
                    msg += " <<TO_MIGRATE>>"
                    if self.args.verbose > 1:
                        msg += "\n\tSP:" + repr(self.sp.data[name])
                        msg += "\n\tON:" + repr(data)
                else:
                    if "legacy" in data:
                        legacy_name: str = data["legacy"]
                        if legacy_name in self.sp.data:
                            msg += f" <<TO_MIGRATE>> legacy:{legacy_name}"
                            if self.args.verbose > 1:
                                msg += (
                                    "\n\tSP:"
                                    f"{repr(self.sp.data[legacy_name])}"
                                    f"\n\tON:{repr(data)}"
                                )
                        else:
                            msg += (
                                " Should upgrade legacy volume"
                                f" '{legacy_name}'"
                                " but not found in StorPool!"
                            )
                            msg += "\n\tON:" + repr(data)
                    else:
                        msg = f" !{name} not found in KV/StorPool data!"
            if self.args.verbose > 1 or err:
                if err:
                    self.err(msg, "Issue")
                else:
                    self.dbg(1, msg)

    def analyze_one_images(self) -> None:
        """Analyze OpenNebula images"""
        self.dbg(1, "processing OpenNebula Images...")
        err: bool = False
        for name, data in self.one.ds_images.items():
            err = False
            msg: str = f"IMG {data['image_id']} ({data['name']}) {name}"
            msg += f" {data['imagetype'].name}|{data['disktype'].name}"
            if name in self.etcd.data["byName"]:
                by_name_uid: str = self.etcd.data["byName"][name]
                msg += f" UID {by_name_uid} (in KV)"
                if by_name_uid in self.sp.data:
                    msg += (
                        " SPsnapshot:"
                        f"{self.sp.data[by_name_uid]['snapshot']}"
                    )
                    if data["disktype"] == DiskType.PERSISTENT:
                        if data["vms"] > 0:
                            msg += " _but_ VM list " + repr(data["vmlist"])
                        elif self.sp.data[by_name_uid]["snapshot"] is not True:
                            msg += " no VMs but volume! [CONVERT TO SNAPSHOT?]"
                    elif data["imagetype"] == ImageType.CDROM:
                        if data["vms"] > 0:
                            msg += " VM list " + repr(data["vmlist"])
                        if self.sp.data[by_name_uid]["snapshot"] is not True:
                            msg += " is SPvolume! [CONVERT TO SNAPSHOT?]"
                else:
                    msg += " UID not in StorPool"
            else:
                err = True
                is_snapshot: bool = True
                if data["disktype"] == DiskType.PERSISTENT:
                    if "id" not in data and data["vms"] > 0:
                        is_snapshot = False
                if name in self.sp.data:
                    msg += " <TO_MIGRATE>"
                    if self.sp.data[name]["snapshot"] != is_snapshot:
                        msg += " <CONVERT_TO_SNAPSHOT>"
                    if self.args.verbose > 1:
                        msg += "\n\tSP:" + repr(self.sp.data[name])
                        msg += "\n\tON:" + repr(data)
                else:
                    for sp_name, sp_data in self.sp.data.items():
                        if "img" in sp_data["tags"]:
                            img: str = sp_data["tags"]["img"]
                            if img == name:
                                msg += (
                                    f" snapshot to KV name:{sp_name}"
                                    f" tags.img={img}"
                                )
                                if self.args.verbose > 1:
                                    msg += "\n\tSP:" + repr(sp_data)
                                    msg += "\n\tON:" + repr(data)
                                break

                    if "legacy" in data:
                        if data["legacy"] in self.sp.data:
                            sp_data_legacy = self.sp.data[data["legacy"]]
                            msg += f" <TO_MIGRATE> legacy:{data['legacy']}"
                            if sp_data_legacy["snapshot"] != is_snapshot:
                                msg += " <CONVERT_TO_SNAPSHOT>"
                            if self.args.verbose > 1:
                                msg += (
                                    "\n\tSP:"
                                    f"{repr(sp_data_legacy)}"
                                    "\n\tON:"
                                    f"{repr(data)}"
                                )
                        else:
                            msg += " Should migrate but not found in StorPool"
                            msg += "\n\tON:" + repr(data)
            if self.args.verbose > 1 or err:
                if err:
                    self.err(msg, "Issue")
                else:
                    self.dbg(1, msg)
            self._analyze_one_image_snapshots(data)

    def _analyze_one_image_snapshots(self, data: Dict[str, Any]) -> None:
        """Analyze snapshots for a given image"""
        for snapname, snapdata in data["snapshots"].items():
            msg: str = f"IMG {data['image_id']} {snapname=}"
            if snapname in self.etcd.data["byName"]:
                by_name_uid: str = self.etcd.data["byName"][snapname]
                msg += f" UID {by_name_uid} (in KV)"
                if by_name_uid in self.sp.data:
                    msg += (
                        " snapshot="
                        f"{self.sp.data[by_name_uid]['snapshot']}"
                        " in StorPool"
                    )
                else:
                    msg += " StorPool snapshot not found!"
            else:
                msg += " not in KV!"
                if snapname in self.sp.data:
                    msg += "<TO_MIGRATE> "
                    if self.args.verbose > 1:
                        msg += "\n\tSP:" + repr(self.sp.data[snapname])
                        msg += "\n\tON:" + repr(snapdata)
                else:
                    if "legacy" in snapdata:
                        legacy_name: str = snapdata["legacy"]
                        msg += f" <TO_MIGRATE> legacy:{legacy_name}"
                        if self.args.verbose > 1:
                            if legacy_name in self.sp.data:
                                msg += (
                                    "\n\tSP:"
                                    f"{repr(self.sp.data[legacy_name])}"
                                )
                            else:
                                print(f"ZDBG not in storpool {snapdata=}")
                            msg += "\n\tON:" + repr(snapdata)
                    else:
                        msg += " Should migrate but not found in StorPool"
                        msg += "\n\tON:" + repr(snapdata)
            self.dbg(1, msg)

    def analyze_storpool(self) -> None:
        """Analyze StorPool data"""
        self.dbg(1, "processing StorPool data...")
        for sp_name, sp_entry in self.sp.data.items():
            notes: List[str] = []
            self.dbg(2, f"_SP_> {sp_name} {repr(sp_entry)}")
            if sp_name[0] == "~":
                self._analyze_storpool_globalid(sp_name, sp_entry, notes)
            else:
                self._analyze_storpool_legacy(sp_name, sp_entry, notes)
            if notes:
                self.err(f"{sp_name} {notes=}", "NOTE")

    def _analyze_storpool_globalid(
        self,
        sp_name: str,
        sp_entry: Dict[str, Any],
        notes: List[str],
    ) -> None:
        """Analyze StorPool entry with globalId"""
        if sp_name in self.etcd.data["byUid"]:
            # ~name found in byUid
            kv_name: str = self.etcd.data["byUid"][sp_name]
            if kv_name in self.etcd.data["byName"]:
                # reverse match: kv_name found in byName
                if sp_name == self.etcd.data["byName"][kv_name]:
                    # ~name matches byName/kv_name value
                    sp_update: Dict[str, Any] = {}
                    if kv_name in self.one.vm_disks:
                        sp_update = self._build_sp_update(
                            sp_entry, self.one.vm_disks[kv_name]
                        )
                    elif kv_name in self.one.ds_images:
                        sp_update = self._build_sp_update(
                            sp_entry, self.one.ds_images[kv_name]
                        )
                    else:
                        one_data: Optional[Dict[str, Any]] = (
                            self._get_by_legacy(kv_name)
                        )
                        if one_data:
                            sp_update = self._build_sp_update(
                                sp_entry, one_data
                            )
                        else:
                            if self.args.verbose > 2:
                                notes.append(f"{kv_name} not in vmData/dsData")
                    if sp_update:
                        self.dbg(3, f"ZDBG {sp_update=}")
                        self.update_data[
                            sp_update["data"]["spname"]
                        ] = sp_update
                else:
                    self.dbg(
                        3,
                        f"ZDBG {sp_name=} =="
                        f" {self.etcd.data['byName'][kv_name]}"
                    )
                    notes.append(
                        f"{sp_name} <> byName/{kv_name}="
                        f"{self.etcd.data['byName'][kv_name]}"
                    )
            else:
                notes.append(f"byUid/{sp_name}={kv_name} not in byName/")
        else:
            notes.append(f"{sp_name} not in byUid")

    def _is_vm_undeployed(self, one_data: Dict[str, Any]) -> bool:
        """Check if the VM is undeployed"""
        ret: bool = False
        if one_data["state"] == 4:
            ret = True
        if one_data["state"] == 8:
            ret = True
        return ret

    def _analyze_storpool_legacy(
        self,
        sp_name: str,
        sp_entry: Dict[str, Any],
        notes: List[str],
    ) -> None:
        """Analyze StorPool entry with legacy name"""
        one_data: Optional[Dict[str, Any]] = self._get_by_legacy(sp_name)
        if one_data:
            spname: str = one_data["spname"]
            self.dbg(4, f"in ONE_data {sp_name=} {spname=}\n\t{one_data=}")
            sp_update: Dict[str, Any] = (
                self._build_sp_update(sp_entry, one_data)
            )
            if sp_update:
                self.update_data[spname] = sp_update
            try:
                self.etcd.validate_kv(
                    sp_entry["globalId"],
                    spname,
                )
            except (KvByNameError, KvByUidError) as err:
                self.dbg(6, f"etcd_manager.validate_kv:{err}")
                sp_update["kv"] = {
                    "byUid": f"~{sp_entry['globalId']}",
                    "byName": spname,
                }
                self.update_data[spname]["action"].append("kv")
            if sp_entry["snapshot"] is False and "host" in one_data:
                target: str = "/dev/storpool-byid/_SP_UID_"
                _target: str = target.replace("_SP_UID_", sp_entry["globalId"])
                if "target" not in one_data or one_data["target"] != _target:
                    self.update_data[spname]["data"]["symlink"] = {
                        "host": one_data["host"],
                        "target": target,
                        "link": one_data["link"],
                        "vm_id": one_data["vm_id"],
                    }
                    if not self._is_vm_undeployed(one_data):
                        self.update_data[spname]["action"].append("symlink")
            if sp_update:
                self.dbg(4, f"update {spname} {spname=} {sp_update=}")
                self.update_data[spname]["data"].update(sp_update["data"])
                self.dbg(3, f"updated {spname} {spname=} {self.update_data[spname]=}")  # noqa: E501
        else:
            if self.args.verbose > 5:
                notes.append(f"Legacy '{sp_name}' not in vmData/dsData")

    def _build_tags(self, onerec: Dict[str, Any]) -> Dict[str, str]:
        """Build expected StorPool tags from ONE data"""
        tags: Dict[str, str] = {}
        tagsmap: List[Tuple[str, str]] = [
            ("vm_id", "nvm"),
            ("nloc", "nloc"),
            ("virt", "virt"),
            ("snap", "snap"),
            ("img", "img"),
        ]
        self.dbg(7, f"build_tags {onerec=}")
        if not onerec["snapshot"]:
            # the volumes had diskid
            tagsmap.append(("disk_id", "diskid"))
            tagsmap.append(("vc-policy", "vc-policy"))
            tagsmap.append(("qosclass", "qc"))
        for onekey, spkey in tagsmap:
            self.dbg(15, f"{onerec['spname']} {onekey=} from tagsmap: {onekey=} -> {spkey=}")  # noqa: E501
            if onekey in onerec and onerec[onekey] is not None:
                tags[spkey] = str(onerec[onekey])
                self.dbg(15, f"{onerec['spname']} added {onekey=} -> {tags[spkey]=}")  # noqa: E501
        if onerec["snapshot"]:
            for tagkey, tagval in tags.items():
                if (
                    tagkey not in [tagtuple[1] for tagtuple in tagsmap]
                    and tagval != ""
                ):
                    self.dbg(15, f"{onerec['spname']} {tagkey=} removed from tags because not in tagsmap: {tagkey=} -> {tagval=}")  # noqa: E501
                    tags[tagkey] = ""
        else:
            if "disktype" in onerec:
                if onerec["disktype"].name == "CONTEXT":
                    tags["type"] = "CNTXT"
                elif onerec["disktype"].name == "CDROM":
                    tags["type"] = "CDROM"
                elif onerec["disktype"].name == "CHECKPOINT":
                    tags["type"] = "CHKPNT"
                elif onerec["disktype"].name == "NVRAM":
                    tags["type"] = "NVRAM"
                elif onerec["disktype"].name == "NONPERSISTENT":
                    tags["type"] = "NPERS"
                    # TODO: append RO if readonly
                elif onerec["disktype"].name == "PERSISTENT":
                    if "vms" not in onerec or onerec["vms"] == 1:
                        tags["type"] = "PERS"
                if "volatile" in onerec:
                    #  TODO: sync with tm/storpool/mkimage
                    if onerec["volatile"] == "swap":
                        tags["type"] = "VOLSWAP"
                    elif onerec["volatile"] == "fs":
                        tags["type"] = "VOLRAW"
                    if "fs" in onerec:
                        tags["fs"] = onerec["fs"]
        # name: str = onerec["spname"]
        # if "snap" in onerec:
        #     name += f"-{onerec['snap']}"
        self.dbg(6, f"ONE {onerec['spname']} {tags=}")
        return tags

    def _build_sp_update(
        self, sp_record: Dict[str, Any], one_record: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Validate sp/ONE and output alterations"""
        cmd: str = "Update"
        if sp_record["snapshot"]:
            cmd = "Update"
        response: Dict[str, Any] = {
            "action": [cmd],
            "data": {
                "uid": sp_record["globalId"],
                "spname": one_record["spname"],
                "snapshot": sp_record["snapshot"],
                "sptags": sp_record["tags"],
                "legacy": one_record["legacy"],
                "tags": {},
            },
        }
        if "link" in one_record:
            response["data"]["link"] = one_record["link"]
        if "target" in one_record:
            response["data"]["target"] = one_record["target"]
        to_globalid: bool = False
        if sp_record["name"][0] != "~":
            # not globalid, so we have to convert to globalId
            to_globalid = True
        new_tags = self._build_tags(one_record)
        if len(sp_record["tags"]) > 0:
            # there are storpoool tags, let's check them
            for tagname, tagval in new_tags.items():
                if (
                    tagname not in sp_record["tags"]
                    or sp_record["tags"][tagname] != tagval
                ):
                    response["data"]["tags"][tagname] = tagval
                    to_globalid = True
            for tagname, tagval in sp_record["tags"].items():
                if tagname not in new_tags:
                    response["data"]["tags"][tagname] = ""
                    to_globalid = True
        else:
            response["data"]["tags"] = new_tags
            to_globalid = True
        self.dbg(5, f"SP_record {sp_record=}")
        self.dbg(5, f"ON_record {one_record=}")
        self.dbg(
            5,
            f"response[tags] ({len(response['data']['tags'])}):"
            f"{response['data']['tags']}",
        )
        if len(response["data"]["tags"]) == 0:
            del response["data"]["tags"]
        if one_record["snapshot"] is True:
            if sp_record["snapshot"] is False:
                response["action"].insert(0, "VolumeFreeze")
            else:
                response["data"]["snap"] = one_record["snap"]
        self.dbg(3, f"UPDATE_RECORD [{to_globalid=}] {response=}")
        if to_globalid:
            return response
        return {}

    def process_updates(self) -> None:
        """Process the pending updates."""
        actions: Dict[str, Callable[..., None]] = {
            "VolumeFreeze": self.sp.volumefreeze,
            "Delete": self.sp.action,
            "Update": self.sp.action,
            "kv": self.etcd.action,
            "kvupdate": self.etcd.action,
            "symlink": self.ssh.action,
        }
        self.dbg(1, f"PROCESSING {len(self.update_data)} update records")
        record: int = 0
        for name, data in self.update_data.items():
            self.dbg(1, f">>> WALKING [{record}] {name} {data['action']} {data['data']=}")  # noqa: E501
            for action in data["action"]:
                if action in actions:
                    self.dbg(6, f"+++ BEGIN '{action}' {name=}")
                    actions[action](data["data"], action)
                    self.dbg(6, f"+++ END '{action}' {name=}")
                else:
                    self.err(f"!!! Unknown action: {action} for {name}", "!!!")
            self.dbg(5, f">>> DONE [{record}] {name}")
            self.dbg(6, f"{'= '*20}")
            record += 1
