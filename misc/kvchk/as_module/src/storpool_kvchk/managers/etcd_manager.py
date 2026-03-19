from __future__ import annotations
from typing import Dict, Any, Tuple

import pprint
import etcd3  # type: ignore
import argparse

from ..models.exceptions import KvByNameError, KvByUidError
from .base_manager import BaseManager


class etcdManager(BaseManager):
    """Manages Key/Value operations in etcd"""

    data: Dict[str, Dict[str, str]] = {"byName": {}, "byUid": {}}

    def __init__(self, args: argparse.Namespace):
        super().__init__(args)
        if not self.args.dummy_etcd:
            self._load_data()

    def _load_data(self) -> None:
        """Load K/V data from etcd"""
        etcd: etcd3.Client = etcd3.client()
        for value, metadata in etcd.get_all():
            # b'~fir.b.jm' b'/byName/ans-sys-26-1'
            # b'ans-img-48' b'/byUid/~fir.b.e7'
            key: str = metadata.key.decode("utf-8")
            if not key.startswith("/by"):
                self.dbg(1, f"Skipping etcd key '{key}' <> '/by...'")
                continue
            array: list[str] = key.split("/")
            if not array[1] in self.data:
                self.data[array[1]] = {}
            if array[2] in self.data[array[1]]:
                # TBD
                self.dbg(
                    0,
                    f"{key} => {array[2]} duplicate! Key already exists as"
                    f" {self.data[array[1]][array[2]]}",
                )
            self.data[array[1]][array[2]] = value.decode("utf-8")
        self.dbg(2, pprint.pformat(self.data))

    def validate_kv(self, globalid: str, onename: str) -> bool:
        """Validate KV entry against expected StorPool globalId
        and OpenNebula named volume or snapshot"""
        ret: bool = False
        kvuid: str = f"~{globalid}"
        # fmt: off
        if (
            kvuid in self.data["byUid"]
            and self.data["byUid"][kvuid] == onename
        ):
            if (
                onename in self.data["byName"]
                and self.data["byName"][onename] == kvuid
            ):
                ret = True
            else:
                raise KvByNameError(f"{globalid} {onename}")
        else:
            raise KvByUidError(f"{globalid} {onename}")
        # fmt: on
        self.dbg(2, f"({globalid=},{onename=}): {ret=}")
        return ret

    def kv_data(self) -> Dict[str, Dict[str, str]]:
        """Get K/V data"""
        if self.args.dummy_etcd > 0:
            self.dbg(0, "Dummy etcd. No data")
            self.dbg(3, pprint.pformat(self.data))
        return self.data

    def write_kv_data(
        self,
        action_data: Dict[str, Any],
        *_: Tuple[Any, ...],
    ) -> None:
        """Write KV data to etcd
        action_data: {
            "spname": "ans-sys-26-1",
            "uid": "~fir.b.jm",
        }
        """
        try:
            etcd: etcd3.Client = etcd3.client()
            # /byName/name -> uid
            kv_key: str = f"/byName/{action_data['spname']}"
            kv_val: str = ""
            if "~" == action_data["uid"][0]:
                kv_val = action_data['uid']
            else:
                kv_val = f"~{action_data['uid']}"
            res: Tuple[bool, int] = (False, 0)
            if self.args.execute:
                self.dbg(2, f"{action_data=}")
                if self.args.dry_run:
                    self.dbg(0, f"[dry-run] etcd.put({kv_key}, {kv_val})")
                else:
                    res = etcd.put(kv_key, kv_val)
                    self.dbg(2, f"data {kv_key} {kv_val} {res=}")
            # /byUid/uid -> name
            kv_key = f"/byUid/{kv_val}"
            kv_val = action_data["spname"]
            if self.args.execute:
                if self.args.dry_run:
                    self.dbg(0, f"[dry-run] etcd.put({kv_key}, {kv_val})")
                else:
                    res = etcd.put(kv_key, kv_val)
                    res_str = str(res).replace('\n', '')
                    self.dbg(
                        2,
                        f"data {kv_key} {kv_val} {res_str}",
                    )
        except Exception as error:
            self.err(f"write_data Error! {action_data=} {error=}")
            raise error

    def action(self, action_data: Dict[str, Any], action: str) -> None:
        """Action on the given data"""
        # self.dbg(6, f"{action=} {action_data=}")
        if action == "kvupdate":
            self.write_kv_data(action_data)
        elif action == "kv":
            self.write_kv_data(action_data)
