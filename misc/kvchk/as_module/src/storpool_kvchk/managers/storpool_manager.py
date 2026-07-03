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
    api_dsid: dict[int, Api] = {}
    api_host: dict[str, Api] = {}

    def __init__(
        self,
        args: argparse.Namespace,
        datastore_config: dict[int, dict[str, str]] = {},
    ):
        super().__init__(args)
        spconfig = SPConfig()
        for ds_id, ds_config in datastore_config.items():
            sp_api_http_host = (
                ds_config.get("SP_API_HTTP_HOST")
                or spconfig["SP_API_HTTP_HOST"]
            )
            sp_api_http_port = (
                ds_config.get("SP_API_HTTP_PORT")
                or spconfig["SP_API_HTTP_PORT"]
            )
            sp_auth_token = (
                ds_config.get("SP_AUTH_TOKEN")
                or spconfig["SP_AUTH_TOKEN"]
            )
            if sp_api_http_host not in self.api_host:
                self.api_host[sp_api_http_host] = Api(
                    host=sp_api_http_host,
                    port=sp_api_http_port,
                    auth=sp_auth_token,
                    multiCluster=True,
                )

            self.api_dsid[ds_id] = self.api_host[sp_api_http_host]
        self.dbg(8, f"{self.api_host=}")
        self.dbg(8, f"{self.api_dsid=}")
        self._load_data()

    def _load_data(self) -> None:
        """Get StorPool data as an dict with reduced set of elements"""
        self._attachments()
        self._volumes()
        self._snapshots()
        self.dbg(2, pprint.pformat(self.data))

    def _attachments(self) -> None:
        """Get StorPool attachments"""
        self.attachments: Dict[str, Dict[str, Any]] = {}
        for sp_api_http_host, api in self.api_host.items():
            try:
                attach_list = api.attachmentsList()  # noqa
            except Exception as error:
                self.err(f"Error! {error}")
                raise error
            for entry in attach_list:
                if entry.volume in self.attachments:
                    entry_volume = self.attachments[entry.volume]
                    entry_volume["client"].append(int(entry.client))
                    entry_volume["rights"].append(entry.rights)
                    entry_volume["clusterId"].append(entry.clusterId)
                    entry_volume["sp_api_http_host"].append(sp_api_http_host)
                    entry_volume["count"] += 1
                else:
                    self.attachments[entry.volume] = {
                        "globalId": entry.globalId,
                        "clusterId": [entry.clusterId],
                        "cluster": entry.cluster,
                        "client": [int(entry.client)],
                        "rights": [entry.rights],
                        "volume": entry.volume,
                        "snapshot": entry.snapshot,
                        "sp_api_http_host": [sp_api_http_host],
                        "count": 1,
                        "ZDBG": "attachmentsList",
                    }
                self.dbg(4, f"{self.attachments[entry.volume]}")

    def _volumes(self) -> None:
        """Get StorPool volumes"""
        for sp_api_http_host, api in self.api_host.items():
            try:
                volumes_list = api.volumesList()  # noqa
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
                    "parentName": getattr(entry, "parentName", "") or "",
                    "templateName": getattr(entry, "templateName", "") or "",  # noqa: E501
                    "creationTimestamp": getattr(entry, "creationTimestamp", None),  # noqa: E501
                    "sp_api_http_host": sp_api_http_host,
                    "ZDBG": "volumesList",
                }
                if entry.name in self.attachments:
                    self.data[entry.name]["attached"] = copy.deepcopy(
                        self.attachments[entry.name]
                    )
                self.dbg(4, f"{self.data[entry.name]}")

    def _snapshots(self) -> None:
        """Get StorPool snapshots"""
        for sp_api_http_host, api in self.api_host.items():
            try:
                snaps_list = api.snapshotsList()  # noqa
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
                    "parentName": getattr(entry, "parentName", "") or "",
                    "templateName": getattr(entry, "templateName", "") or "",  # noqa: E501
                    "creationTimestamp": getattr(entry, "creationTimestamp", None),  # noqa: E501
                    "onVolume": getattr(entry, "onVolume", "") or "",
                    "autoName": bool(getattr(entry, "autoName", False)),
                    "transient": bool(getattr(entry, "transient", False)),
                    "deleted": bool(getattr(entry, "deleted", False)),
                    "bound": bool(getattr(entry, "bound", False)),
                    "targetDeleteDate": getattr(entry, "targetDeleteDate", None),  # noqa: E501
                    "sp_api_http_host": sp_api_http_host,
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
        sp_api_http_host = in_data["sp_api_http_host"]
        api = self.api_host[sp_api_http_host]
        if self.args.execute:
            if self.args.dry_run:
                self.dbg(
                    0,
                    f"[[dry-run]] {sp_api_http_host} snapshotCreate "
                    f"{in_data=} {payload=}",
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
        response = api.snapshotCreate(  # noqa
            spname,
            payload,
        )
        self.dbg(
            1,
            f"{sp_api_http_host} snapshotCreate({spname}) "
            f"{payload=} {response.ok=}",
        )
        if response.ok:
            snapshot_globalid: str = response.snapshotGlobalId
            in_data["uid"] = snapshot_globalid
            in_data["snapshot"] = True
            self.dbg(
                1,
                f"{sp_api_http_host} UPDATED {spname=} old {old_globalid} "
                f"to {snapshot_globalid} and {in_data['snapshot']=}",
            )
            response = api.volumeDelete(spname)  # noqa
            self.dbg(
                1,
                f"{sp_api_http_host} volumeDelete({spname}) {response.ok=}"
            )
        else:
            self.err(
                f"{sp_api_http_host} snapshotCreate({spname}) {payload=}"
                f"{response.err=}",
            )
            raise Exception(f"{sp_api_http_host} snapshotCreate({spname}) {payload=} {response.ok=}")  # noqa: E501

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
        sp_api_http_host: str,
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
                self.err(
                    f"{sp_api_http_host} {err.name} {err.desc} {err.json}"
                )
                raise
        try:
            return api_actions[cmd]["call"](spname)  # noqa
        except ApiError as err:
            self.err(f"{sp_api_http_host} {err.name} {err.desc} {err.json}")
            raise

    def _handle_action(
        self,
        sp_api_http_host: str,
        cmd: str,
        action: str,
        action_data: Dict[str, Any],
        api_actions: Dict[str, Any],
    ) -> None:
        """Handle the actual StorPool API call"""
        self.dbg(8, f"{sp_api_http_host} {cmd=} {action=} {action_data=}")
        spname: str = f"~{action_data['uid']}"
        response: Any = None
        if self.args.execute:
            if self.args.dry_run:
                runmsg = (
                    f"[dry-run] {sp_api_http_host} {cmd}/{spname} "
                    f"{{'name': ''"
                )
                response = "dummy-response"
                if "tags" in action_data:
                    runmsg += f", 'tags': {action_data['tags']}"
                runmsg += "}"
                self.dbg(0, runmsg)
            else:
                response = self._make_api_call(
                    sp_api_http_host,
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

    def action(
        self,
        action_data: Dict[str, Any],
        action: str,
    ) -> None:
        """Get StorPool data as an dict with reduced set of elements"""
        sp_api_http_host = action_data["sp_api_http_host"]
        try:
            api = self.api_host[sp_api_http_host]
            api_actions: Dict[str, Dict[str, Any]] = {
                "VolumeDelete": {"call": api.volumeDelete, "data": False},
                "VolumeUpdate": {"call": api.volumeUpdate, "data": True},
                "SnapshotDelete": {
                    "call": api.snapshotDelete,
                    "data": False,
                },
                "SnapshotUpdate": {
                    "call": api.snapshotUpdate,
                    "data": True,
                },
            }
            cmd: str = f"Volume{action}"
            if action_data["snapshot"]:
                cmd = f"Snapshot{action}"
            if cmd not in api_actions:
                self.err(f"{sp_api_http_host} Unknown API call '{action}'")
                raise UnknownApiCall(action)

            self._handle_action(
                sp_api_http_host,
                cmd,
                action,
                action_data,
                api_actions,
            )

        except Exception as error:
            self.err(f"{sp_api_http_host} storpool_action Error! {error}")
            raise error
