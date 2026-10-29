"""StorPool Manager."""

from __future__ import annotations
from typing import Any, Dict, List, Optional

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
    # the datastore -> API host mapping behind api_dsid
    host_dsid: dict[int, str] = {}
    # ClustersList/LocationsList per API host (raw API dicts)
    clusters: Dict[str, List[Dict[str, Any]]] = {}
    locations: Dict[str, List[Dict[str, Any]]] = {}
    # SP_CLUSTER_ID of the frontend's storpool.conf, the cluster
    # behind the default API host
    local_cluster_id: str = ""

    def __init__(
        self,
        args: argparse.Namespace,
        datastore_config: dict[int, dict[str, str]] = {},
    ):
        super().__init__(args)
        self.data = {}
        self.api_dsid = {}
        self.api_host = {}
        self.host_dsid = {}
        self.clusters = {}
        self.locations = {}
        spconfig = SPConfig()
        self.local_cluster_id = str(spconfig.get("SP_CLUSTER_ID") or "")
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
            self.host_dsid[ds_id] = sp_api_http_host
        self.dbg(8, f"{self.api_host=}")
        self.dbg(8, f"{self.api_dsid=}")
        self._load_data()

    def _load_data(self) -> None:
        """Get StorPool data as an dict with reduced set of elements

        The lists are fetched with returnRawAPIData=True because the
        typed bindings drop any JSON field their spec does not declare
        (e.g. preservedGlobalId)."""
        self._clusters()
        self._attachments()
        self._volumes()
        self._snapshots()
        self.dbg(2, pprint.pformat(self.data))

    def _clusters(self) -> None:
        """Get the StorPool clusters and locations known to each API"""
        for sp_api_http_host, api in self.api_host.items():
            try:
                clusters = api.clustersList(returnRawAPIData=True)  # noqa
                locations = api.locationsList(returnRawAPIData=True)  # noqa
            except Exception as error:
                self.err(f"{sp_api_http_host} Error! {error}")
                raise error
            self.clusters[sp_api_http_host] = list(clusters.get("clusters", []))  # noqa: E501
            self.locations[sp_api_http_host] = list(locations.get("locations", []))  # noqa: E501
            self.dbg(4, f"{sp_api_http_host} clusters {self.clusters[sp_api_http_host]}")  # noqa: E501
            self.dbg(4, f"{sp_api_http_host} locations {self.locations[sp_api_http_host]}")  # noqa: E501

    def cluster_registered(
        self, sp_api_http_host: str, cluster_id: str
    ) -> Optional[str]:
        """Check a '<locationId>.<clusterId>' cluster id against the
        locations and clusters registered in the API at
        sp_api_http_host (storpool location list / cluster list).
        Return None when both are registered, the reason otherwise."""
        location_id, dot, short_id = cluster_id.rpartition(".")
        if not dot or not location_id or not short_id:
            return f"'{cluster_id}' is not a <location>.<cluster> id"
        locations = self.locations.get(sp_api_http_host, [])
        location = next(
            (loc for loc in locations if loc.get("id") == location_id),
            None,
        )
        if location is None:
            return (
                f"location '{location_id}' of cluster '{cluster_id}'"
                f" is not a StorPool location"
                f" (known: {[loc.get('id') for loc in locations]})"
            )
        clusters = self.clusters.get(sp_api_http_host, [])
        cluster = next(
            (
                cl for cl in clusters
                if cl.get("id") == short_id
                and cl.get("location") == location.get("name")
            ),
            None,
        )
        if cluster is None:
            known = [
                f"{cl.get('location')}/{cl.get('id')}" for cl in clusters
            ]
            return (
                f"cluster '{cluster_id}' is not a StorPool cluster"
                f" in location '{location_id}' ({location.get('name')})"
                f" (known location/cluster: {known})"
            )
        return None

    def _attachments(self) -> None:
        """Get StorPool attachments"""
        self.attachments: Dict[str, Dict[str, Any]] = {}
        for sp_api_http_host, api in self.api_host.items():
            try:
                attach_list = api.attachmentsList(returnRawAPIData=True)  # noqa
            except Exception as error:
                self.err(f"Error! {error}")
                raise error
            for entry in attach_list:
                volume = entry["volume"]
                if volume in self.attachments:
                    entry_volume = self.attachments[volume]
                    entry_volume["client"].append(int(entry["client"]))
                    entry_volume["rights"].append(entry["rights"])
                    entry_volume["clusterId"].append(entry.get("clusterId"))
                    entry_volume["sp_api_http_host"].append(sp_api_http_host)
                    entry_volume["count"] += 1
                else:
                    self.attachments[volume] = {
                        "globalId": entry.get("globalId"),
                        "clusterId": [entry.get("clusterId")],
                        "cluster": entry.get("cluster"),
                        "client": [int(entry["client"])],
                        "rights": [entry["rights"]],
                        "volume": volume,
                        "snapshot": bool(entry.get("snapshot", False)),
                        "sp_api_http_host": [sp_api_http_host],
                        "count": 1,
                        "ZDBG": "attachmentsList",
                    }
                self.dbg(4, f"{self.attachments[volume]}")

    def _volumes(self) -> None:
        """Get StorPool volumes"""
        for sp_api_http_host, api in self.api_host.items():
            try:
                volumes_list = api.volumesList(returnRawAPIData=True)  # noqa
            except Exception as error:
                self.err(f"Error! {error}")
                raise error
            for entry in volumes_list:
                name = entry["name"]
                self.data[name] = {
                    "globalId": entry["globalId"],
                    # the original globalId survives VolumeRevert,
                    # the canonical one changes on every revert
                    "preservedGlobalId": entry.get("preservedGlobalId", "") or "",  # noqa: E501
                    "name": name,
                    "clusterId": entry.get("clusterId"),
                    "tags": entry.get("tags", {}),
                    "size": entry["size"],
                    "snapshot": False,
                    "parentName": entry.get("parentName", "") or "",
                    "templateName": entry.get("templateName", "") or "",
                    "creationTimestamp": entry.get("creationTimestamp"),
                    "sp_api_http_host": sp_api_http_host,
                    "ZDBG": "volumesList",
                }
                if name in self.attachments:
                    self.data[name]["attached"] = copy.deepcopy(
                        self.attachments[name]
                    )
                self.dbg(4, f"{self.data[name]}")

    def _snapshots(self) -> None:
        """Get StorPool snapshots"""
        for sp_api_http_host, api in self.api_host.items():
            try:
                snaps_list = api.snapshotsList(returnRawAPIData=True)  # noqa
            except Exception as error:
                self.err(f"Error! {error}")
                raise error
            for entry in snaps_list:
                name = entry["name"]
                self.data[name] = {
                    "globalId": entry["globalId"],
                    "name": name,
                    "clusterId": entry.get("clusterId"),
                    "tags": entry.get("tags", {}),
                    "size": entry["size"],
                    "snapshot": True,
                    "parentName": entry.get("parentName", "") or "",
                    "templateName": entry.get("templateName", "") or "",
                    "creationTimestamp": entry.get("creationTimestamp"),
                    "onVolume": entry.get("onVolume", "") or "",
                    "autoName": bool(entry.get("autoName", False)),
                    "transient": bool(entry.get("transient", False)),
                    "deleted": bool(entry.get("deleted", False)),
                    "bound": bool(entry.get("bound", False)),
                    "targetDeleteDate": entry.get("targetDeleteDate"),
                    "sp_api_http_host": sp_api_http_host,
                    "ZDBG": "snapshotsList",
                }
                if name in self.attachments:
                    self.data[name]["attached"] = copy.deepcopy(
                        self.attachments[name]
                    )
                self.dbg(4, f"{self.data[name]}")

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
