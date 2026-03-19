"""StorPool Manager."""

from __future__ import annotations
from typing import Any, Dict

import copy
import pprint
import argparse
from storpool.spapi import Api, ApiError  # type: ignore
from storpool.spconfig import SPConfig  # type: ignore

from ..models.exceptions import UnknownApiCall
from .base_manager import BaseManager


class spManager(BaseManager):
    """StorPool Manager"""

    data: Dict[str, Any] = {}

    def __init__(self, args: argparse.Namespace):
        super().__init__(args)
        spconfig = SPConfig()
        self.api = Api(
            host=spconfig["SP_API_HTTP_HOST"],
            port=spconfig["SP_API_HTTP_PORT"],
            auth=spconfig["SP_AUTH_TOKEN"],
            multiCluster=True,
        )
        self._load_data()

    def _load_data(self) -> None:
        """Get StorPool data as an dict with reduced set of elements"""
        self._attachments()
        self._volumes()
        self._snapshots()
        self.dbg(2, pprint.pformat(self.data))

    def _attachments(self) -> None:
        """Get StorPool attachments"""
        try:
            attach_list = self.api.attachmentsList()  # noqa
        except Exception as error:
            self.err(f"Error! {error}")
            raise error
        self.attachments: Dict[str, Dict[str, Any]] = {}
        for entry in attach_list:
            if entry.volume in self.attachments:
                entry_volume = self.attachments[entry.volume]
                entry_volume["client"].append(int(entry.client))
                entry_volume["rights"].append(entry.rights)
                entry_volume["count"] += 1
            else:
                self.attachments[entry.volume] = {
                    "globalId": entry.globalId,
                    "clusterId": entry.clusterId,
                    "cluster": entry.cluster,
                    "client": [int(entry.client)],
                    "rights": [entry.rights],
                    "volume": entry.volume,
                    "snapshot": entry.snapshot,
                    "count": 1,
                    "ZDBG": "attachmentsList",
                }
            self.dbg(4, f"{self.attachments[entry.volume]}")

    def _volumes(self) -> None:
        """Get StorPool volumes"""
        try:
            volumes_list = self.api.volumesList()  # noqa
        except Exception as error:
            self.err(f"Error! {error}")
            raise error
        for entry in volumes_list:
            self.data[entry.name] = {
                "globalId": entry.globalId,
                "name": entry.name,
                "clusterId": entry.clusterId,
                "tags": entry.tags,
                "size": entry.size,
                "snapshot": False,
                "ZDBG": "volumesList",
            }
            if entry.name in self.attachments:
                self.data[entry.name]["attached"] = copy.deepcopy(
                    self.attachments[entry.name]
                )
            self.dbg(4, f"{self.data[entry.name]}")

    def _snapshots(self) -> None:
        """Get StorPool snapshots"""
        try:
            snaps_list = self.api.snapshotsList()  # noqa
        except Exception as error:
            self.err(f"Error! {error}")
            raise error
        for entry in snaps_list:
            self.data[entry.name] = {
                "globalId": entry.globalId,
                "name": entry.name,
                "clusterId": entry.clusterId,
                "tags": entry.tags,
                "size": entry.size,
                "snapshot": True,
                "ZDBG": "snapshotsList",
            }
            if entry.name in self.attachments:
                self.data[entry.name]["attached"] = copy.deepcopy(
                    self.attachments[entry.name]
                )
            self.dbg(4, f"{self.data[entry.name]}")

    def volumefreeze(
        self,
        in_data: Dict[str, Any],
        action: str,
    ) -> None:
        """Freeze the volume"""
        del action
        in_data["snapshot"] = True
        old_globalid = in_data["uid"]
        tags: Dict[str, str] = in_data["sptags"].copy()
        if "tags" in in_data:
            tags.update(in_data["tags"])
        tags["img"] = in_data["spname"]
        payload: Dict[str, Any] = {"name": "", "tags": tags}
        spname = in_data["spname"]
        if self.args.execute:
            if self.args.dry_run:
                self.dbg(
                    0, f"[[dry-run]] snapshotCreate {in_data=} {payload=}"
                )
                in_data["uid"] = "new.globalid"
                in_data["snapshot"] = True
                self.dbg(
                    0,
                    f"[[dry-run]] UPDATED {old_globalid=} to {in_data['uid']}"
                    f", {in_data['snapshot']=} {spname=}"
                )
                self.dbg(0, f"[[dry-run]] volumeDelete {spname=}")
                return
        else:
            self.dbg(0, f"[[to-execute]] {in_data=} {payload=}")
            return
        response = self.api.snapshotCreate(  # noqa
            spname,
            payload,
        )
        self.dbg(
            1,
            f"snapshotCreate({spname}) {payload=} {response.ok=}"
        )
        if response.ok:
            snapshot_globalid: str = response.snapshotGlobalId
            in_data["uid"] = snapshot_globalid
            in_data["snapshot"] = True
            self.dbg(
                1,
                f"UPDATED {spname=} old {old_globalid} to {snapshot_globalid}"
                f" and {in_data['snapshot']=}",
            )
            response = self.api.volumeDelete(spname)  # noqa
            self.dbg(1, f"volumeDelete({spname}) {response.ok=}")
        else:
            self.err(f"snapshotCreate({spname}) {payload=} {response.err=}")
            raise Exception(f"snapshotCreate({spname}) {payload=} {response.ok=}")  # noqa: E501

    def _get_request_data(
        self, action: str, action_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Build request data dictionary"""
        req_data = {"name": ""}
        if action == "Update":
            req_data = {"rename": ""}
        if "tags" in action_data:
            req_data["tags"] = action_data["tags"]
        return req_data

    def _make_api_call(
        self,
        cmd: str,
        action: str,
        action_data: Dict[str, Any],
        api_actions: Dict[str, Any],
    ) -> Any:
        """Make the actual API call"""
        spname = f"~{action_data['uid']}"
        if api_actions[cmd]["data"]:
            req_data = self._get_request_data(action, action_data)
            try:
                return api_actions[cmd]["call"](spname, req_data)  # noqa
            except ApiError as err:
                self.err(f"{err.name} {err.desc} {err.json}")
                raise
        try:
            return api_actions[cmd]["call"](spname)  # noqa
        except ApiError as err:
            self.err(f"{err.name} {err.desc} {err.json}")
            raise

    def action(
        self,
        action_data: Dict[str, Any],
        action: str,
    ) -> None:
        """Get StorPool data as an dict with reduced set of elements"""
        try:
            api_actions: Dict[str, Dict[str, Any]] = {
                "VolumeDelete": {"call": self.api.volumeDelete, "data": False},
                "VolumeUpdate": {"call": self.api.volumeUpdate, "data": True},
                "SnapshotDelete": {
                    "call": self.api.snapshotDelete,
                    "data": False,
                },
                "SnapshotUpdate": {
                    "call": self.api.snapshotUpdate,
                    "data": True,
                },
            }
            cmd: str = f"Volume{action}"
            if action_data["snapshot"]:
                cmd = f"Snapshot{action}"
            if cmd not in api_actions:
                self.err(f"Unknown API call '{action}'")
                raise UnknownApiCall(action)

            self._handle_action(cmd, action, action_data, api_actions)

        except Exception as error:
            self.err(f"storpool_action Error! {error}")
            raise error

    def _handle_action(
        self,
        cmd: str,
        action: str,
        action_data: Dict[str, Any],
        api_actions: Dict[str, Any],
    ) -> None:
        """Handle the actual StorPool API call"""
        self.dbg(8, f"{cmd=} {action=} {action_data=}")
        spname: str = f"~{action_data['uid']}"
        response: Any = None
        if self.args.execute:
            if self.args.dry_run:
                runmsg = f"[dry-run] {cmd}/{spname} {{'name': ''"
                response = "dummy-response"
                if "tags" in action_data:
                    runmsg += f", 'tags': {action_data['tags']}"
                runmsg += "}"
                self.dbg(0, runmsg)
            else:
                response = self._make_api_call(
                    cmd,
                    action,
                    action_data,
                    api_actions,
                )
        else:
            response = "dummy-response"
        request_data: Dict[str, Any] = self._get_request_data(
            action, action_data
        )
        self.dbg(
            2,
            f"END {cmd}/{spname} :: {action=}"
            + f" {request_data=} {response=} {action_data=}",
        )
