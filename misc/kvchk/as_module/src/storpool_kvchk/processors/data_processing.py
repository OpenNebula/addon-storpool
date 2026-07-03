from __future__ import annotations
from typing import List, Dict, Any, Optional, Tuple, Callable

import argparse
from ..managers.base_manager import BaseManager
from ..managers.ssh_manager import SshManager
from ..managers.one_manager import oneManager
from ..managers.storpool_manager import spManager
from ..managers.etcd_manager import etcdManager
from ..models.exceptions import KvByNameError, KvByUidError
from ..models.enums import DiskType, ImageType

# VM states where the VM files (and the disk.N symlinks) are
# expected to be present on the VM host:
# 3 - ACTIVE, 5 - SUSPENDED, 8 - POWEROFF
VM_ON_HOST_STATES = (3, 5, 8)

# VM states where the VM files are expected to be on the frontend:
# 4 - STOPPED, 9 - UNDEPLOYED
VM_ON_FRONTEND_STATES = (4, 9)


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
        self.one: oneManager = one_manager
        self.sp: spManager = sp_manager
        self.ssh: SshManager = ssh_manager
        self.update_data: Dict[str, Dict[str, Any]] = {}
        self.update_entry: Dict[str, Any] = {}
        self._uid_index: Optional[Dict[str, Dict[str, Any]]] = None

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

    def _sp_by_uid(self, kv_uid: str) -> Optional[Dict[str, Any]]:
        """Look up a StorPool record by KV uid ('~globalId').
        sp.data is keyed by name, so volumes still under their legacy
        name are found via the globalId index."""
        if kv_uid in self.sp.data:
            return self.sp.data[kv_uid]
        if self._uid_index is None:
            self._uid_index = {}
            for sp_entry in self.sp.data.values():
                self._uid_index[sp_entry["globalId"]] = sp_entry
        return self._uid_index.get(kv_uid.lstrip("~"))

    def _resolve_one_record(self, name: str) -> Optional[Dict[str, Any]]:
        """Find an OpenNebula record by current or legacy name"""
        if name in self.one.vm_disks:
            return self.one.vm_disks[name]
        if name in self.one.ds_images:
            return self.one.ds_images[name]
        return self._get_by_legacy(name)

    def _sp_tags_this_instance(self, sp_entry: Dict[str, Any]) -> bool:
        """Check if the StorPool tags claim the record belongs to
        this OpenNebula instance"""
        tags: Dict[str, str] = sp_entry.get("tags") or {}
        if tags.get("virt") != "one":
            return False
        if tags.get("nloc") and tags["nloc"] != self.args.one_px:
            return False
        return True

    def _resolve_one_by_tags(
        self, sp_entry: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        """Resolve the OpenNebula record for a StorPool record
        using its tags"""
        if not self._sp_tags_this_instance(sp_entry):
            return None
        tags: Dict[str, str] = sp_entry.get("tags") or {}
        img: Optional[str] = tags.get("img")
        if img:
            candidate: str = img
            if tags.get("snap"):
                candidate = f"{img}-{tags['snap']}"
            one_data: Optional[Dict[str, Any]] = (
                self._resolve_one_record(candidate)
            )
            if one_data:
                return one_data
        if sp_entry["snapshot"] is False:
            nvm: Optional[str] = tags.get("nvm")
            diskid: Optional[str] = tags.get("diskid")
            if nvm and diskid:
                for rec in self.one.vm_disks.values():
                    if rec.get("snapshot"):
                        continue
                    if (
                        str(rec.get("vm_id")) == nvm
                        and str(rec.get("disk_id")) == diskid
                    ):
                        return rec
        return None

    def _queue_kv_repair(
        self, spname: str, sp_entry: Dict[str, Any]
    ) -> None:
        """Queue restoring the byName/byUid pair for a StorPool record"""
        if spname not in self.update_data:
            self.update_data[spname] = {"data": {}, "action": []}
        entry: Dict[str, Any] = self.update_data[spname]
        if "spname" not in entry["data"]:
            entry["data"]["spname"] = spname
        if "uid" not in entry["data"]:
            entry["data"]["uid"] = sp_entry["globalId"]
        if "kv" not in entry["action"]:
            entry["action"].append("kv")
        self.dbg(2, f"queued KV repair {spname} ->"
                    f" ~{sp_entry['globalId']}")

    def _kv_check_one_record(self, name: str, uid: str) -> None:
        """Check that a KV byName entry is still backed by an
        OpenNebula record"""
        if self._resolve_one_record(name):
            return
        sp_entry: Optional[Dict[str, Any]] = (
            self._sp_by_uid(uid) or self.sp.data.get(name)
        )
        if sp_entry is None:
            self.err(
                f"[kv] byName[{name}] = {uid} not in OpenNebula"
                " and not in StorPool - stale KV record",
                "Issue",
            )
            self.dbg(0, f"etcdctl del /byName/{name}")
            if self.etcd.data["byUid"].get(uid) == name:
                self.dbg(0, f"etcdctl del /byUid/{uid}")
        else:
            # e.g. a backup image (not tracked in ds_images) or an
            # unreferenced leftover - report only, never suggest delete
            self.dbg(
                1,
                f"[kv] byName[{name}] = {uid} not in OpenNebula but"
                f" StorPool has {sp_entry['name']}"
                " (backup image or leftover?)",
            )

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
            self._kv_check_one_record(name, uid)
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
        sp_uid_entry: Optional[Dict[str, Any]] = self._sp_by_uid(uid)
        if name != self.etcd.data["byUid"][uid]:
            self.dbg(
                2,
                f"[kv] byName[{name}] != byUid[{uid}]"
                f"={self.etcd.data['byUid'][uid]}",
            )
            # Check if uid is in StorPool
            if sp_uid_entry is not None:
                if sp_uid_entry["snapshot"]:
                    self.dbg(2, f"[kv] UID snapshot:{sp_uid_entry}")
                else:
                    self.dbg(2, f"[kv] UID volume:{sp_uid_entry}")
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
            if sp_uid_entry is None:
                self.err(
                    f"[kv] byName[{name}] = {uid}"
                    " UID not in StorPool!",
                    "Issue",
                )
                self.dbg(0, f"# etcdctl del /byName/{name}"
                            "  # verify before removing")
                self.dbg(0, f"# etcdctl del /byUid/{uid}"
                            "  # verify before removing")
            elif (
                sp_uid_entry["name"][0] == "~"
                and name in self.sp.data
            ):
                self.dbg(
                    2,
                    f"[kv] byName[{name}] = {uid}"
                    " NAME in StorPool //Migrate?",
                )

    def _kv_handle_missing_uid(self, name: str, uid: str) -> None:
        """Handle case when uid is missing from byUid"""
        sp_uid_entry: Optional[Dict[str, Any]] = self._sp_by_uid(uid)
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
        elif sp_uid_entry is not None:
            if sp_uid_entry["snapshot"]:
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
            self.err(
                f"[kv] byName[{name}] = {uid}"
                " not in byUid and not in StorPool!",
                "Issue",
            )
            self.dbg(0, f"# etcdctl del /byName/{name}"
                        "  # verify before removing")

    def _update_kv_data(self, name: str, uid: str) -> None:
        """Update KV data for name/uid pair"""
        if name not in self.update_data:
            self.update_data[name] = {"data": {}, "action": []}
        if "name" not in self.update_data[name]["data"]:
            self.update_data[name]["data"]["name"] = name
        # write_kv_data() keys on 'spname'
        if "spname" not in self.update_data[name]["data"]:
            self.update_data[name]["data"]["spname"] = name
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
                    # repair KV under the current name, not the legacy one
                    self._fix_one_data(uid, one_data["spname"])
                else:
                    self.dbg(2, f" byUid[{uid}] = {name} not in ONE")
                    self.dbg(0, f"etcdctl del /byUid/{uid}")

    def _fix_uid_mismatch(self, uid: str, name: str) -> None:
        """Fix uid mismatch cases"""
        sp_uid_entry: Optional[Dict[str, Any]] = self._sp_by_uid(uid)
        if sp_uid_entry is not None:
            if sp_uid_entry["snapshot"]:
                self.dbg(
                    2,
                    f" byUid[{uid}]={name}"
                    f" has SP snapshot {sp_uid_entry['tags']},"
                    f" byName[{name}]={self.etcd.data['byName'][name]}",
                )
                self.dbg(0, f"etcdctl del /byUid/{uid}")
                self.dbg(0, f"storpool -M -B snapshot {uid} delete {uid}")
            else:
                self.dbg(
                    2,
                    f" byUid[{uid}]={name}"
                    f" has SP volume {sp_uid_entry['tags']},"
                    f" byName[{name}]={self.etcd.data['byName'][name]}",
                )
                self.dbg(0, f"etcdctl del /byUid/{uid}")
                sp_api_http_host = sp_uid_entry["sp_api_http_host"]
                self.dbg(
                    0,
                    f"storpool -M -B volume {uid} delete {uid}"
                    f" # API: {sp_api_http_host}",
                )
        else:
            self.dbg(0, f"etcdctl del /byUid/{uid}")

    def _fix_one_data(self, uid: str, name: str) -> None:
        """Fix OpenNebula data cases"""
        if self._sp_by_uid(uid) is not None:
            self.dbg(
                2,
                f" byUid[{uid}] = {name} in ONE and StorPool, KV update",
            )
            if name not in self.update_data:
                self.update_data[name] = {"data": {}, "action": []}
            self.update_data[name]["data"] = {
                "name": name,
                # write_kv_data() keys on 'spname'
                "spname": name,
                "uid": uid,
            }
            self.dbg(6, f"ZDBG {self.update_data=}")
            self.update_data[name]["action"].append("kvupdate")
        else:
            # report and continue - a single inconsistent record
            # must not abort the whole validation run
            self.err(
                f" byUid[{uid}] = {name} in ONE but not in StorPool!",
                "Issue",
            )

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
                if self._sp_by_uid(by_name_uid) is None:
                    err = True
                    msg += f" UID {by_name_uid} not in StorPool!"
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
                sp_rec: Optional[Dict[str, Any]] = (
                    self._sp_by_uid(by_name_uid)
                )
                if sp_rec is not None:
                    msg += (
                        " SPsnapshot:"
                        f"{sp_rec['snapshot']}"
                    )
                    if data["disktype"] == DiskType.PERSISTENT:
                        if data["vms"] > 0:
                            msg += " _but_ VM list " + repr(data["vmlist"])
                        elif sp_rec["snapshot"] is not True:
                            msg += " no VMs but volume! [CONVERT TO SNAPSHOT?]"
                    elif data["imagetype"] == ImageType.CDROM:
                        if data["vms"] > 0:
                            msg += " VM list " + repr(data["vmlist"])
                        if sp_rec["snapshot"] is not True:
                            msg += " is SPvolume! [CONVERT TO SNAPSHOT?]"
                else:
                    err = True
                    msg += " UID not in StorPool!"
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
            err: bool = False
            msg: str = f"IMG {data['image_id']} {snapname=}"
            if snapname in self.etcd.data["byName"]:
                by_name_uid: str = self.etcd.data["byName"][snapname]
                msg += f" UID {by_name_uid} (in KV)"
                sp_rec: Optional[Dict[str, Any]] = (
                    self._sp_by_uid(by_name_uid)
                )
                if sp_rec is not None:
                    msg += (
                        " snapshot="
                        f"{sp_rec['snapshot']}"
                        " in StorPool"
                    )
                else:
                    err = True
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
            if err:
                self.err(msg, "Issue")
            else:
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
                # repair the lost byName entry when ONE confirms it
                one_rec: Optional[Dict[str, Any]] = (
                    self._resolve_one_record(kv_name)
                )
                if one_rec:
                    notes.append(
                        f"KV repair queued for {one_rec['spname']}"
                    )
                    self._queue_kv_repair(one_rec["spname"], sp_entry)
        else:
            # not in byUid at all - use the tags to find the ONE record
            one_rec = self._resolve_one_by_tags(sp_entry)
            if one_rec:
                notes.append(
                    f"{sp_name} not in byUid, matched ONE"
                    f" {one_rec['spname']} by tags - KV repair queued"
                )
                self._queue_kv_repair(one_rec["spname"], sp_entry)
            elif self._sp_tags_this_instance(sp_entry):
                notes.append(
                    f"{sp_name} tagged for this OpenNebula instance"
                    " but no matching record found (orphan?)"
                    f" {sp_entry.get('tags')}"
                )
            else:
                # not tagged for this ONE instance - do not spam notes
                self.dbg(3, f"{sp_name} not in byUid (foreign/untagged)")

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
            if (
                sp_entry["snapshot"] is False
                and "host" in one_data
                and "link" in one_data
            ):
                _target: str = f"/dev/storpool-byid/{sp_entry['globalId']}"
                if "target" not in one_data or one_data["target"] != _target:
                    self._queue_symlink_fix(
                        spname, one_data, sp_entry["globalId"]
                    )
            if sp_update:
                self.dbg(4, f"update {spname} {spname=} {sp_update=}")
                self.update_data[spname]["data"].update(sp_update["data"])
                self.dbg(3, f"updated {spname} {spname=} {self.update_data[spname]=}")  # noqa: E501
        else:
            if self.args.verbose > 5:
                notes.append(f"Legacy '{sp_name}' not in vmData/dsData")

    def _expected_globalid(
        self,
        one_data: Dict[str, Any],
    ) -> Optional[str]:
        """Resolve the StorPool globalId expected for a given ONE volume,
        walking all known relations: KV byName (current and legacy name),
        KV byUid reverse mapping, StorPool by name and StorPool by tags"""
        spname: str = one_data["spname"]
        legacy: Optional[str] = one_data.get("legacy")
        # KV byName, by the current and by the legacy name
        for candidate in (spname, legacy):
            if candidate and candidate in self.etcd.data["byName"]:
                uid: str = self.etcd.data["byName"][candidate]
                if candidate != spname:
                    self.dbg(2, f"{spname} found in KV byName"
                                f" as legacy '{candidate}'")
                return uid.lstrip("~")
        # KV byUid reverse lookup (byName entry lost/inconsistent)
        for uid, kv_name in self.etcd.data["byUid"].items():
            if kv_name in (spname, legacy):
                self.dbg(2, f"{spname} found only in KV"
                            f" byUid[{uid}]={kv_name}")
                return uid.lstrip("~")
        # StorPool volume/snapshot still under the ONE name
        for candidate in (spname, legacy):
            if candidate and candidate in self.sp.data:
                return self.sp.data[candidate]["globalId"]
        # StorPool tags (volume renamed to ~globalId, KV entries lost)
        vm_id: Optional[int] = one_data.get("vm_id")
        disk_id: Optional[int] = one_data.get("disk_id")
        for sp_name, sp_entry in self.sp.data.items():
            tags: Dict[str, str] = sp_entry.get("tags") or {}
            if tags.get("virt") != "one":
                continue
            if tags.get("nloc") and tags["nloc"] != self.args.one_px:
                continue
            if tags.get("snap"):
                # a snapshot of the volume, not the volume itself
                continue
            if tags.get("img") == spname or (
                vm_id is not None
                and disk_id is not None
                and tags.get("nvm") == str(vm_id)
                and tags.get("diskid") == str(disk_id)
            ):
                self.dbg(2, f"{spname} matched StorPool tags"
                            f" of {sp_name} {tags=}")
                return sp_entry["globalId"]
        return None

    def _queue_symlink_fix(
        self,
        spname: str,
        one_data: Dict[str, Any],
        globalid: str,
    ) -> None:
        """Queue a 'symlink' action re-creating the disk.N symlink"""
        if one_data.get("state") not in [3, 8]:
            # fix only Running or PowerOff VMs, where the disk.N
            # symlinks are expected to be present on the host
            self.dbg(3, f"{spname} VM {one_data['vm_id']} state"
                        f" {one_data.get('state')},"
                        " not queueing symlink fix")
            return
        if spname not in self.update_data:
            self.update_data[spname] = {"data": {}, "action": []}
        entry: Dict[str, Any] = self.update_data[spname]
        if "symlink" in entry["action"]:
            self.dbg(3, f"{spname} symlink action already queued")
            return
        if "uid" not in entry["data"]:
            entry["data"]["uid"] = globalid
        entry["data"]["symlink"] = {
            "host": one_data["host"],
            "target": "/dev/storpool-byid/_SP_UID_",
            "link": one_data["link"],
            "vm_id": one_data["vm_id"],
        }
        entry["action"].append("symlink")

    def analyze_host_symlinks(self) -> None:
        """Detect stale/missing disk.N symlinks on the hosts still
        pointing to the legacy /dev/storpool/<name> devices instead
        of /dev/storpool-byid/<globalId>, then check the symlinks
        collected from the hosts against the OpenNebula data for
        left-over artefacts on hosts where the VM is not expected
        to be running"""
        self.dbg(1, "processing host symlinks...")
        known_links: Dict[str, str] = {}
        frontend_name: Optional[str] = (
            (self.one.frontend or {}).get("name")
        )
        for name, data in self.one.vm_disks.items():
            if data.get("snapshot"):
                continue
            link: Optional[str] = data.get("link")
            host: Optional[str] = data.get("host")
            if not link or not host:
                continue
            if data.get("state") in VM_ON_HOST_STATES:
                # only VMs deployed on the host are expected
                # to have their disk.N symlinks there
                known_links[f"{host}:{link}"] = name
            elif (
                data.get("state") in VM_ON_FRONTEND_STATES
                and frontend_name
            ):
                # the files of STOPPED/UNDEPLOYED VMs are moved
                # back to the system datastore on the frontend
                known_links[f"{frontend_name}:{link}"] = name
            target: Optional[str] = data.get("target")
            globalid: Optional[str] = self._expected_globalid(data)
            if globalid is None:
                if target and target.startswith("/dev/storpool/"):
                    # never stay silent about an old-format symlink
                    self.err(
                        f"VM {data['vm_id']} {name} on {host}:"
                        f" stale legacy symlink {link} -> {target}"
                        " but no globalId found in KV/StorPool!",
                        "Issue",
                    )
                else:
                    # not in KV/StorPool - reported by the other passes
                    self.dbg(4, f"{name} {link} on {host}:"
                                " no globalId found in KV/StorPool")
                continue
            expected: str = f"/dev/storpool-byid/{globalid}"
            if target == expected:
                continue
            msg: str = f"VM {data['vm_id']} {name} on {host}:"
            if target is None:
                if data.get("state") not in [3, 8] or "links" not in \
                        self.one.one_hosts.get(host, {}):
                    # no symlink data collected for this VM/host
                    continue
                msg += f" missing symlink {link}"
            elif target.startswith("/dev/storpool/"):
                msg += f" stale legacy symlink {link} -> {target}"
            else:
                msg += f" unexpected symlink {link} -> {target}"
            msg += f", expected -> {expected}"
            self.err(msg, "Issue")
            self.dbg(0, f"ssh {host} ln -vsfn {expected} {link}")
            self._queue_symlink_fix(name, data, globalid)
        self._report_missing_frontend_data()
        self._report_orphan_symlinks(known_links)

    def _report_missing_frontend_data(self) -> None:
        """Report STOPPED/UNDEPLOYED VMs with disk symlinks missing
        on the frontend, where their files are expected. With
        SKIP_UNDEPLOY_SSH enabled the VM home is not moved to the
        frontend on stop/undeploy, so nothing is expected there"""
        if getattr(self.args, "skip_undeploy_ssh", False):
            self.dbg(2, "SKIP_UNDEPLOY_SSH enabled - not checking"
                        " the VM data on the frontend")
            return
        frontend: Dict[str, Any] = self.one.frontend or {}
        links: Optional[Dict[int, Any]] = frontend.get("links")
        if links is None and frontend.get("name") in self.one.one_hosts:
            # the frontend is a hypervisor host
            links = self.one.one_hosts[frontend["name"]].get("links")
        if links is None:
            # frontend symlinks not collected
            return
        for name, data in self.one.vm_disks.items():
            if data.get("snapshot"):
                continue
            if data.get("state") not in VM_ON_FRONTEND_STATES:
                continue
            link: Optional[str] = data.get("link")
            if not link:
                continue
            vm_id: int = int(data["vm_id"])
            ds_id: int = int(data["sys_ds_id"])
            disk_name: str = link.rsplit("/", 1)[-1]
            if links.get(ds_id, {}).get(vm_id, {}).get(disk_name):
                continue
            self.err(
                f"VM {vm_id} {name} state {data.get('state')}:"
                f" missing {link} on the frontend",
                "Issue",
            )

    def _expected_vm_placement(self) -> Dict[int, Dict[str, Any]]:
        """Build the expected VM placement (host, ds_id, state) from
        the OpenNebula data, falling back to the VM disk records when
        the VM pool data is not available"""
        placement: Dict[int, Dict[str, Any]] = {}
        for vm_id, vm_rec in self.one.one_vms.items():
            placement[int(vm_id)] = dict(vm_rec)
        for data in self.one.vm_disks.values():
            if "vm_id" not in data:
                continue
            entry: Dict[str, Any] = placement.setdefault(
                int(data["vm_id"]), {}
            )
            for one_key, key in (
                ("host", "host"),
                ("state", "state"),
                ("sys_ds_id", "ds_id"),
            ):
                if key not in entry and data.get(one_key) is not None:
                    entry[key] = data[one_key]
        return placement

    def _classify_leftover(
        self,
        hostname: str,
        ds_id: int,
        vm_id: int,
        disk_name: str,
        vm_rec: Optional[Dict[str, Any]],
        is_frontend: bool,
    ) -> Optional[str]:
        """Explain why a StorPool symlink collected from a host or
        the frontend is a left-over artefact according to the
        OpenNebula data.
        Returns None when the symlink could be legitimate."""
        if vm_id not in self.one.vm_ids:
            return f" (VM {vm_id} not in ONE)"
        if not vm_rec:
            # in ONE but no placement data collected
            return ""
        state: Optional[int] = vm_rec.get("state")
        exp_host: Optional[str] = vm_rec.get("host")
        exp_ds: Optional[int] = vm_rec.get("ds_id")
        if state in VM_ON_FRONTEND_STATES:
            if not is_frontend:
                return (f" (VM {vm_id} state {state},"
                        " expected on the frontend)")
        elif state is not None and state not in VM_ON_HOST_STATES:
            return (f" (VM {vm_id} state {state},"
                    " not expected on any host)")
        elif exp_host and exp_host != hostname:
            if is_frontend:
                return (f" (VM {vm_id} expected on host {exp_host},"
                        " not on the frontend)")
            return f" (VM {vm_id} expected on host {exp_host})"
        if exp_ds is not None and int(exp_ds) != ds_id:
            return f" (VM {vm_id} expected in datastore {exp_ds})"
        # VM expected here: an unknown disk.N is a left-over
        # (e.g. a detached disk), anything else (disk.N.snapM, ...)
        # could be legitimate
        if disk_name.startswith("disk.") and disk_name[5:].isdigit():
            return f" (not a disk of VM {vm_id})"
        return None

    def _report_orphan_symlinks(self, known_links: Dict[str, str]) -> None:
        """Check the StorPool symlinks collected from the hosts and
        the frontend against the OpenNebula data and report the
        left-over artefacts: symlinks of VMs that are deleted, not
        deployed, expected on another host, on the frontend or in
        another datastore, and unknown disk.N symlinks"""
        placement: Dict[int, Dict[str, Any]] = (
            self._expected_vm_placement()
        )
        frontend: Dict[str, Any] = self.one.frontend or {}
        frontend_name: Optional[str] = frontend.get("name")
        # (hostname, links, is_frontend, remote)
        sources: List[Tuple[str, Dict[int, Any], bool, bool]] = [
            (hostname, host_e.get("links", {}),
             hostname == frontend_name, True)
            for hostname, host_e in self.one.one_hosts.items()
        ]
        if frontend_name and frontend_name not in self.one.one_hosts:
            sources.append(
                (frontend_name, frontend.get("links", {}), True, False)
            )
        for hostname, host_links, is_frontend, remote in sources:
            where: str = hostname
            if not remote:
                where = f"the frontend {hostname}"
            for ds_id, host_vms in host_links.items():
                for vm_id, disks in host_vms.items():
                    vm_rec: Optional[Dict[str, Any]] = (
                        placement.get(vm_id)
                    )
                    for disk_name, target in disks.items():
                        link: str = (f"/var/lib/one/datastores"
                                     f"/{ds_id}/{vm_id}/{disk_name}")
                        if f"{hostname}:{link}" in known_links:
                            continue
                        if not target.startswith("/dev/storpool"):
                            continue
                        note: Optional[str] = self._classify_leftover(
                            hostname, ds_id, vm_id, disk_name,
                            vm_rec, is_frontend,
                        )
                        if note is None:
                            self.dbg(3, f"skipping {hostname}:{link}"
                                        f" -> {target}")
                            continue
                        self.err(
                            f"orphan symlink on {where}:"
                            f" {link} -> {target}{note}",
                            "Issue",
                        )
                        rm_cmd: str = f"# ssh {hostname} rm -v {link}"
                        if not remote:
                            rm_cmd = f"# rm -v {link}"
                        self.dbg(0, f"{rm_cmd}"
                                    "  # verify before removing")

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
                "sp_api_http_host": sp_record["sp_api_http_host"],
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
                if "snap" in one_record:
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
