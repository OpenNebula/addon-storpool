#!/usr/bin/env python3
"""Live StorPool backup sizes for one VM.

OpenNebula stores each backup SIZE when the backup finishes and never
writes it again. This process reads the VM and its backup images as the
FireEdge user, joins each SOURCE snapshot to the VolumesSpace and
SnapshotsSpace files monitor_helper-sync already keeps, and serves a page
beside FireEdge.

    python3 backup_space.py serve
    python3 backup_space.py vm 7          # oneadmin, from one_auth

The page is http://127.0.0.1:2874/ . Sunstone's StorPool sidebar loads
/storpool/api/ui from the same process. Publish it on the FireEdge vhost
with misc/etc/nginx/snippets/storpool-backup.conf .

The browser sends the FireedgeToken cookie (path /, httpOnly). The
service checks it with /var/lib/one/.one/fireedge_key and calls oned as
that user. The `vm` subcommand is the operator path and reads one_auth.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import xmlrpc.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_BIND = "127.0.0.1"
DEFAULT_PORT = 2874
DEFAULT_ONE_URL = "http://127.0.0.1:2633/RPC2"
DEFAULT_CACHE = "/var/cache/addon-storpool-monitor"
DEFAULT_KEY = "/var/lib/one/.one/fireedge_key"
DEFAULT_AUTH = "/var/lib/one/.one/one_auth"
COOKIE_NAME = "FireedgeToken"
_HERE = os.path.dirname(os.path.abspath(__file__))
STATIC_PAGE = os.path.join(_HERE, "static", "index.html")
REMOTE_ENTRY = os.path.join(_HERE, "fireedge", "remoteEntry.js")

# one.vmpool.info / one.imagepool.info filter flags. These are OpenNebula's
# RequestManagerPoolInfoFilter values, the same ones FireEdge sends
# (OpenNebula::Pool::INFO_*):
#   -1 group, -2 all, -3 mine, -4 primary group.
# all is every object this user may USE: owner, group, other, and ACL rules.
# oneadmin, and the oneadmin group, receive the whole pool for all.
POOL_GROUP = -1
POOL_ALL = -2
POOL_MINE = -3
POOL_PRIMARY_GROUP = -4

_POOL_FILTERS = {
    "all": POOL_ALL,
    "mine": POOL_MINE,
    "group": POOL_GROUP,
    "primary": POOL_PRIMARY_GROUP,
    "primary-group": POOL_PRIMARY_GROUP,
}
_POOL_FILTER_NAMES = {
    POOL_GROUP: "group",
    POOL_ALL: "all",
    POOL_MINE: "mine",
    POOL_PRIMARY_GROUP: "primary",
}

_VM_STATE = {
    0: "INIT",
    1: "PENDING",
    2: "HOLD",
    3: "ACTIVE",
    4: "STOPPED",
    5: "SUSPENDED",
    6: "DONE",
    8: "POWEROFF",
    9: "UNDEPLOYED",
    10: "CLONING",
    11: "CLONING_FAILURE",
}
_LCM_STATE = {
    3: "RUNNING",
    69: "BACKUP",
    70: "BACKUP_POWEROFF",
}


def pool_filter(value):
    """FireEdge filter name or flag -> the oned filter_flag. Default is all."""
    if value is None or value == "":
        return POOL_ALL
    key = str(value).strip().lower().replace("_", "-")
    if key in _POOL_FILTERS:
        return _POOL_FILTERS[key]
    if key in ("-1", "-2", "-3", "-4"):
        return int(key)
    raise ValueError(value)


def pool_filter_name(flag):
    return _POOL_FILTER_NAMES.get(flag, "all")


class AuthError(Exception):
    pass


class OneError(Exception):
    pass


def parse_backup_source(source):
    """StorPool SOURCE: location/vm/epoch/disk=id/nvram=id/svc=id.

    None when the string is some other driver's SOURCE. Snapshot ids are
    stored without the leading '~'.
    """
    if not isinstance(source, str) or not source or any(c in source for c in " \t,"):
        return None
    location, sep, rest = source.partition("/")
    vm_id, sep2, rest = rest.partition("/")
    epoch, sep3, entries = rest.partition("/")
    if not sep or not sep2 or not sep3:
        return None
    if not location or not vm_id.isdigit() or not epoch.isdigit() or not entries:
        return None
    ids = {}
    for entry in entries.split("/"):
        key, eq, value = entry.partition("=")
        if not eq or not key or not value:
            return None
        ids[key] = value[1:] if value.startswith("~") else value
    return {
        "location": location,
        "vm_id": int(vm_id),
        "epoch": int(epoch),
        "ids": ids,
    }


def cluster_of(global_id):
    """fir.b.snap -> fir.b. The cluster id is the first two fields."""
    if not global_id:
        return None
    parts = str(global_id).lstrip("~").split(".")
    if len(parts) < 3 or not parts[0] or not parts[1]:
        return None
    return parts[0] + "." + parts[1]


def _as_int(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def _sum_present(values):
    total = None
    for value in values:
        if value is None:
            continue
        total = value if total is None else total + value
    return total


def _xml_text(elem, path):
    if elem is None:
        return None
    node = elem.find(path)
    if node is None or node.text is None:
        return None
    text = node.text.strip()
    return text or None


def _xml_all(elem, path):
    if elem is None:
        return []
    return list(elem.findall(path))


def _fetch_end(obj):
    """spFetch.end of a document or of one cluster response, or None."""
    if not isinstance(obj, dict):
        return None
    fetch = obj.get("spFetch")
    if not isinstance(fetch, dict):
        return None
    return _as_int(fetch.get("end"))


def iter_space_entries(doc):
    """(entry, fetch_end) pairs of a per-cluster body or an all-clusters body.

    A per-cluster body stamps spFetch on the document. An all-clusters body
    stamps each cluster response, and that stamp is the sample time of the
    entries in the response. A response without a stamp inherits the document
    stamp.
    """
    if not isinstance(doc, dict):
        return []
    data = doc.get("data")
    doc_end = _fetch_end(doc)
    if isinstance(data, list):
        return [(entry, doc_end) for entry in data if isinstance(entry, dict)]
    if not isinstance(data, dict):
        return []
    pairs = []
    for cluster in data.get("clusters") or []:
        if not isinstance(cluster, dict):
            continue
        response = cluster.get("response")
        if not isinstance(response, dict) or not isinstance(response.get("data"), list):
            continue
        end = _fetch_end(response)
        if end is None:
            end = doc_end
        for entry in response["data"]:
            if isinstance(entry, dict):
                pairs.append((entry, end))
    return pairs


class SpaceBody(object):
    def __init__(self, path, doc):
        self.path = path
        self.mtime = int(os.stat(path).st_mtime) if path and os.path.isfile(path) else None
        doc_ok = isinstance(doc, dict)
        data = doc.get("data") if doc_ok else None
        # data is a list on a per-cluster file and a clusters object on the rollup
        self.per_cluster = isinstance(data, list)
        self.cluster = doc.get("clusterId") if doc_ok else None
        if self.cluster in ("", "null"):
            self.cluster = None
        self.fetch_end = _fetch_end(doc) if doc_ok else None
        self.entries = []
        self.fetch_of = {}
        self.by_gid = {}
        for entry, end in iter_space_entries(doc if doc_ok else {}):
            self.entries.append(entry)
            self.fetch_of[id(entry)] = end
            gid = entry.get("globalId")
            if not gid:
                continue
            key = str(gid).lstrip("~")
            if key not in self.by_gid:
                self.by_gid[key] = entry

    def meta(self, call):
        return {
            "call": call,
            "cluster": self.cluster,
            "mtime": self.mtime,
            "fetch_end": self.fetch_end,
        }


def _load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_bodies(directory, call):
    """Current cache files for one call. .1 and .2 are older samples and are left out."""
    if not directory or not os.path.isdir(directory):
        return []
    prefix = "json-%s-" % call
    bodies = []
    for name in sorted(os.listdir(directory)):
        if not name.startswith(prefix):
            continue
        if name.endswith(".1") or name.endswith(".2") or name.endswith(".lock"):
            continue
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        try:
            doc = _load_json(path)
        except (OSError, ValueError):
            continue
        bodies.append(SpaceBody(path, doc))
    return bodies


def load_local_cluster(directory):
    """clusterId of the cached ClustersList, the API this front-end talks to."""
    if not directory or not os.path.isdir(directory):
        return None
    newest = None
    chosen = None
    for name in os.listdir(directory):
        if not name.startswith("json-ClustersList-"):
            continue
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        mtime = os.stat(path).st_mtime
        if newest is not None and mtime < newest:
            continue
        try:
            doc = _load_json(path)
        except (OSError, ValueError):
            continue
        cluster = doc.get("clusterId") if isinstance(doc, dict) else None
        if cluster and cluster != "null":
            newest = mtime
            chosen = cluster
    return chosen


def _sample_beats(challenger, incumbent):
    """True when challenger is the sample to keep.

    Both arguments are (body, entry). A later spFetch.end wins when both
    samples carry one. A missing stamp is compared by file mtime instead, so
    an unstamped file is not treated as older than every stamped one. Equal
    times keep the per-cluster file over the all-clusters rollup, then the
    file whose clusterId is the global id's own cluster.
    """
    cbody, centry = challenger
    ibody, ientry = incumbent
    c_end = cbody.fetch_of.get(id(centry))
    i_end = ibody.fetch_of.get(id(ientry))
    if c_end is not None and i_end is not None:
        if c_end != i_end:
            return c_end > i_end
    else:
        c_mtime = -1 if cbody.mtime is None else cbody.mtime
        i_mtime = -1 if ibody.mtime is None else ibody.mtime
        if c_mtime != i_mtime:
            return c_mtime > i_mtime
    if cbody.per_cluster != ibody.per_cluster:
        return cbody.per_cluster
    gid = centry.get("globalId") or ientry.get("globalId") or ""
    want = cluster_of(str(gid))
    if want:
        c_match = cbody.cluster == want
        i_match = ibody.cluster == want
        if c_match != i_match:
            return c_match
    return False


def _freshest(pairs):
    chosen = None
    for pair in pairs:
        if chosen is None or _sample_beats(pair, chosen):
            chosen = pair
    if chosen is None:
        return None
    return chosen[1]


class SpaceCache(object):
    def __init__(self, directory):
        self.directory = directory
        self.snapshots = load_bodies(directory, "SnapshotsSpace")
        self.volumes = load_bodies(directory, "VolumesSpace")
        self.local_cluster = load_local_cluster(directory)
        self.missing_dir = not (directory and os.path.isdir(directory))

    def meta(self):
        return {
            "directory": self.directory,
            "missing": self.missing_dir,
            "local_cluster": self.local_cluster,
            "files": (
                [body.meta("SnapshotsSpace") for body in self.snapshots]
                + [body.meta("VolumesSpace") for body in self.volumes]
            ),
        }

    def snapshot(self, global_id):
        key = str(global_id).lstrip("~")
        found = []
        for body in self.snapshots:
            entry = body.by_gid.get(key)
            if entry is not None:
                found.append((body, entry))
        return _freshest(found)

    def volumes_of(self, vm_id):
        want = str(vm_id)
        best = {}
        order = []
        for body in self.volumes:
            for entry in body.entries:
                tags = entry.get("tags") if isinstance(entry.get("tags"), dict) else {}
                if str(tags.get("nvm", "")) != want:
                    continue
                gid = str(entry.get("globalId") or "").lstrip("~")
                if not gid:
                    continue
                pair = (body, entry)
                if gid not in best:
                    best[gid] = pair
                    order.append(gid)
                elif _sample_beats(pair, best[gid]):
                    best[gid] = pair
        return [best[gid][1] for gid in order]

    def snapshot_by_tags(self, vm_id, epoch, role, remote, source_id):
        matches = []
        for body in self.snapshots:
            for entry in body.entries:
                tags = entry.get("tags") if isinstance(entry.get("tags"), dict) else {}
                if str(tags.get("nvm", "")) != str(vm_id):
                    continue
                if str(tags.get("bkp", "")) != str(epoch):
                    continue
                if str(tags.get("diskid", "")) != str(role):
                    continue
                matches.append((body, entry))
        if not matches:
            return None
        live = [pair for pair in matches if not pair[1].get("deleted")]
        pool = live or matches
        if remote and self.local_cluster:
            foreign = [
                pair for pair in pool
                if cluster_of(pair[1].get("globalId") or "") != self.local_cluster
            ]
            if foreign:
                pool = foreign
        if not remote:
            exact = [
                pair for pair in pool
                if str(pair[1].get("globalId") or "").lstrip("~") == source_id
            ]
            if exact:
                pool = exact
        return _freshest(pool)


def _role_key(role):
    if str(role).isdigit():
        return (0, int(role), str(role))
    if role == "nvram":
        return (1, 0, role)
    if role == "svc":
        return (2, 0, role)
    return (3, 0, role)


def _point_note(manifest, inc_type):
    if manifest["location"] != "local":
        return (
            "Remote backup. OpenNebula recorded the full content of the disks. "
            "storedSize is the copy in the cache when its tags match, otherwise the SOURCE id. "
            "On a snapshot, spaceUsed is the bytes freed if that snapshot is deleted."
        )
    if inc_type == "INCREMENT":
        return (
            "Local increment. The recorded SIZE was the storedSize estimate printed when the backup finished. "
            "On a snapshot, spaceUsed is the bytes freed if that snapshot is deleted."
        )
    return (
        "Full backup. The recorded SIZE was the volume spaceUsed estimate printed when the backup finished. "
        "The snapshot storedSize is the bytes that snapshot holds. "
        "On a snapshot, spaceUsed is the bytes freed if that snapshot is deleted."
    )


def _plain_id(value):
    if not value:
        return None
    text = str(value).lstrip("~").strip()
    return text or None


def _part(role, source_id, entry):
    measured = source_id
    if entry is not None and entry.get("globalId"):
        measured = str(entry.get("globalId")).lstrip("~")
    # onVolume is the disk (or nvram/service volume) the snapshot sits on.
    # parentName is the previous snapshot in the chain.
    return {
        "role": role,
        "source_id": source_id,
        "global_id": measured,
        "volume_global_id": _plain_id(entry.get("onVolume")) if entry else None,
        "in_cache": entry is not None,
        "deleted": bool(entry.get("deleted")) if entry else False,
        "name": entry.get("name") if entry else None,
        "stored_bytes": _as_int(entry.get("storedSize")) if entry else None,
        "space_used_bytes": _as_int(entry.get("spaceUsed")) if entry else None,
        "excluded_from_size": role == "svc",
    }


def _point_from_manifest(manifest, recorded_mb, inc_id, inc_type, date, cache):
    remote = manifest["location"] != "local"
    parts = []
    for role, global_id in sorted(manifest["ids"].items(), key=lambda item: _role_key(item[0])):
        entry = None
        if remote:
            entry = cache.snapshot_by_tags(manifest["vm_id"], manifest["epoch"], role, True, global_id)
        if entry is None:
            entry = cache.snapshot(global_id)
        if entry is None:
            entry = cache.snapshot_by_tags(manifest["vm_id"], manifest["epoch"], role, remote, global_id)
        parts.append(_part(role, global_id, entry))
    counted = [part for part in parts if not part["excluded_from_size"]]
    stored_partial = any(
        (not part["in_cache"]) or part["stored_bytes"] is None for part in counted
    )
    space_partial = any(
        (not part["in_cache"]) or part["space_used_bytes"] is None for part in counted
    )
    return {
        "increment_id": inc_id,
        "type": inc_type,
        "date": date,
        "recorded_mb": recorded_mb,
        "location": manifest["location"],
        "epoch": manifest["epoch"],
        "storpool": True,
        "note": _point_note(manifest, inc_type),
        "parts": parts,
        "comparable_stored_bytes": _sum_present(part["stored_bytes"] for part in counted),
        "comparable_space_used_bytes": _sum_present(part["space_used_bytes"] for part in counted),
        "stored_partial": stored_partial,
        "space_partial": space_partial,
    }


def _foreign_point(source, recorded_mb, inc_id, inc_type, date):
    return {
        "increment_id": inc_id,
        "type": inc_type,
        "date": date,
        "recorded_mb": recorded_mb,
        "location": None,
        "epoch": None,
        "storpool": False,
        "source": source,
        "note": "Not a StorPool SOURCE. OpenNebula's recorded SIZE is the only figure.",
        "parts": [],
        "comparable_stored_bytes": None,
        "comparable_space_used_bytes": None,
        "stored_partial": False,
        "space_partial": False,
    }


def _restore_point(source, recorded_mb, inc_id, inc_type, date, cache):
    manifest = parse_backup_source(source)
    if manifest is None:
        return _foreign_point(source, recorded_mb, inc_id, inc_type, date)
    return _point_from_manifest(manifest, recorded_mb, inc_id, inc_type, date, cache)


def _backup_totals(points):
    storpool_points = [point for point in points if point["storpool"]]
    latest = storpool_points[-1] if storpool_points else None
    return {
        "stored_bytes": _sum_present(point["comparable_stored_bytes"] for point in storpool_points),
        "stored_partial": any(point["stored_partial"] for point in storpool_points),
        "latest_space_used_bytes": None if latest is None else latest["comparable_space_used_bytes"],
        "latest_space_partial": False if latest is None else latest["space_partial"],
    }


def backup_report(image_elem, cache):
    """One backup image: its frozen SIZE and one row per restore point."""
    increments = _xml_all(image_elem, "BACKUP_INCREMENTS/INCREMENT")
    points = []
    if increments:
        def inc_id(elem):
            return _as_int(_xml_text(elem, "ID")) or 0

        for inc in sorted(increments, key=inc_id):
            points.append(_restore_point(
                _xml_text(inc, "SOURCE"),
                _as_int(_xml_text(inc, "SIZE")),
                _as_int(_xml_text(inc, "ID")),
                _xml_text(inc, "TYPE"),
                _as_int(_xml_text(inc, "DATE")),
                cache,
            ))
    else:
        points.append(_restore_point(
            _xml_text(image_elem, "SOURCE"),
            _as_int(_xml_text(image_elem, "SIZE")),
            None,
            "FULL",
            _as_int(_xml_text(image_elem, "REGTIME")),
            cache,
        ))
    report = {
        "image_id": _as_int(_xml_text(image_elem, "ID")),
        "name": _xml_text(image_elem, "NAME"),
        "recorded_mb": _as_int(_xml_text(image_elem, "SIZE")),
        "points": points,
    }
    report.update(_backup_totals(points))
    return report


def _disk_report(disk, volumes):
    disk_id = _xml_text(disk, "DISK_ID")
    names = {
        name for name in (
            _xml_text(disk, "SOURCE"),
            _xml_text(disk, "IMAGE"),
            _xml_text(disk, "CLONE"),
        ) if name
    }
    matched = None
    for entry in volumes:
        tags = entry.get("tags") if isinstance(entry.get("tags"), dict) else {}
        if disk_id is not None and str(tags.get("diskid", "")) == disk_id:
            matched = entry
            break
        if entry.get("name") and entry["name"] in names:
            matched = entry
            break
    return {
        "disk_id": disk_id,
        "virtual_mb": _as_int(_xml_text(disk, "SIZE")),
        "image": _xml_text(disk, "IMAGE"),
        "source": _xml_text(disk, "SOURCE"),
        "tm_mad": _xml_text(disk, "TM_MAD"),
        "global_id": None if matched is None else str(matched.get("globalId") or "").lstrip("~") or None,
        "in_cache": matched is not None,
        "stored_bytes": _as_int(matched.get("storedSize")) if matched else None,
        "space_used_bytes": _as_int(matched.get("spaceUsed")) if matched else None,
        "size_bytes": _as_int(matched.get("size")) if matched else None,
    }


def _volume_row(entry):
    tags = entry.get("tags") if isinstance(entry.get("tags"), dict) else {}
    return {
        "global_id": str(entry.get("globalId") or "").lstrip("~"),
        "name": entry.get("name"),
        "disk_id": tags.get("diskid"),
        "stored_bytes": _as_int(entry.get("storedSize")),
        "space_used_bytes": _as_int(entry.get("spaceUsed")),
        "size_bytes": _as_int(entry.get("size")),
    }


def vm_report(vm_elem, images, cache):
    """images: image id -> <IMAGE> element, or Exception for one the user cannot read."""
    vm_id = _as_int(_xml_text(vm_elem, "ID"))
    volumes = cache.volumes_of(vm_id) if vm_id is not None else []
    backups = []
    for node in _xml_all(vm_elem, "BACKUPS/BACKUP_IDS/ID"):
        image_id = _as_int(node.text.strip() if node.text else None)
        if image_id is None:
            continue
        image = images.get(image_id)
        if isinstance(image, Exception):
            backups.append({"image_id": image_id, "error": str(image)})
        elif image is None:
            backups.append({"image_id": image_id, "error": "backup image was not read"})
        else:
            backups.append(backup_report(image, cache))
    return {
        "vm": {"id": vm_id, "name": _xml_text(vm_elem, "NAME")},
        "cache": cache.meta(),
        "disks": [_disk_report(disk, volumes) for disk in _xml_all(vm_elem, "TEMPLATE/DISK")],
        "volumes": [_volume_row(entry) for entry in volumes],
        "backups": backups,
    }


def parse_image_xml(xml_text):
    root = ET.fromstring(xml_text)
    if root.tag == "IMAGE":
        return root
    image = root.find("IMAGE")
    if image is None:
        raise OneError("reply has no IMAGE")
    return image


def parse_vm_xml(xml_text):
    root = ET.fromstring(xml_text)
    if root.tag == "VM":
        return root
    vm = root.find("VM")
    if vm is None:
        raise OneError("reply has no VM")
    return vm


def parse_vm_pool(xml_text):
    root = ET.fromstring(xml_text)
    if root.tag == "VM_POOL":
        return list(root.findall("VM"))
    return list(root.findall(".//VM"))


def parse_image_pool(xml_text):
    root = ET.fromstring(xml_text)
    if root.tag == "IMAGE_POOL":
        return list(root.findall("IMAGE"))
    return list(root.findall(".//IMAGE"))


def _vm_state_label(state, lcm_state):
    name = _VM_STATE.get(state, str(state) if state is not None else "")
    if state == 3 and lcm_state in _LCM_STATE:
        return "%s / %s" % (name, _LCM_STATE[lcm_state])
    return name


def _backup_ids(vm_elem):
    ids = []
    for node in _xml_all(vm_elem, "BACKUPS/BACKUP_IDS/ID"):
        image_id = _as_int(node.text.strip() if node.text else None)
        if image_id is not None:
            ids.append(image_id)
    return ids


def summarize_vm(vm_elem, images_by_id, cache):
    """One row: how many backups the VM has, the frozen SIZE, and the live storedSize."""
    image_ids = _backup_ids(vm_elem)
    recorded = None
    stored = None
    partial = False
    points = 0
    missing = 0
    for image_id in image_ids:
        image = images_by_id.get(image_id)
        if image is None:
            missing += 1
            partial = True
            continue
        report = backup_report(image, cache)
        points += len(report["points"])
        if report["recorded_mb"] is not None:
            recorded = report["recorded_mb"] if recorded is None else recorded + report["recorded_mb"]
        if report["stored_bytes"] is not None:
            stored = report["stored_bytes"] if stored is None else stored + report["stored_bytes"]
        if report["stored_partial"]:
            partial = True
    state = _as_int(_xml_text(vm_elem, "STATE"))
    return {
        "id": _as_int(_xml_text(vm_elem, "ID")),
        "name": _xml_text(vm_elem, "NAME"),
        "owner": _xml_text(vm_elem, "UNAME"),
        "group": _xml_text(vm_elem, "GNAME"),
        "state": _vm_state_label(state, _as_int(_xml_text(vm_elem, "LCM_STATE"))),
        "backup_images": len(image_ids),
        "restore_points": points,
        "recorded_mb": recorded,
        "stored_bytes": stored,
        "stored_partial": partial,
        "missing_images": missing,
    }


def summary_report(vm_elems, image_elems, cache):
    """VMs the caller can see. A DONE VM with no backup is left out."""
    images_by_id = {}
    for image in image_elems:
        image_id = _as_int(_xml_text(image, "ID"))
        if image_id is not None:
            images_by_id[image_id] = image
    rows = []
    for vm in vm_elems:
        state = _as_int(_xml_text(vm, "STATE"))
        row = summarize_vm(vm, images_by_id, cache)
        if state == 6 and row["backup_images"] == 0:
            continue
        rows.append(row)
    rows.sort(key=lambda row: (row["backup_images"] == 0, -(row["id"] or 0)))
    return {"cache": cache.meta(), "vms": rows}


class OneClient(object):
    def __init__(self, url=DEFAULT_ONE_URL):
        self.url = url

    def call(self, method, session, *args):
        proxy = xmlrpc.client.ServerProxy(self.url, allow_none=True)
        fn = proxy
        for part in method.split("."):
            fn = getattr(fn, part)
        try:
            result = fn(session, *args)
        except xmlrpc.client.Fault as exc:
            raise OneError(exc.faultString)
        except OSError as exc:
            raise OneError(str(exc))
        if not isinstance(result, (list, tuple)) or len(result) < 2 or result[0] is not True:
            message = result[1] if isinstance(result, (list, tuple)) and len(result) > 1 else result
            raise OneError(str(message))
        return result[1]

    def vm_xml(self, session, vm_id):
        return parse_vm_xml(self.call("one.vm.info", session, int(vm_id)))

    def image_xml(self, session, image_id):
        return parse_image_xml(self.call("one.image.info", session, int(image_id)))

    def vm_pool_xml(self, session, filter_flag=POOL_ALL):
        # filter, start id, end id, state, query. -1 spans the whole pool.
        # infoextended carries BACKUPS; the short pool listing does not.
        # The flag is applied by oned for this session. There is no retry as
        # mine: that would hide group and shared VMs FireEdge still shows.
        args = (int(filter_flag), -1, -1, -1, "")
        try:
            return self.call("one.vmpool.infoextended", session, *args)
        except OneError as exc:
            if "not defined" not in str(exc).lower():
                raise
            return self.call("one.vmpool.info", session, *args)

    def image_pool_xml(self, session):
        # Always the caller's ACL view, not the VM-list filter. A backup image
        # this user may read still joins when the list is Mine or Group.
        return self.call("one.imagepool.info", session, POOL_ALL, -1, -1)


def report_vm(one, cache, session, vm_id):
    vm = one.vm_xml(session, vm_id)
    images = {}
    for node in _xml_all(vm, "BACKUPS/BACKUP_IDS/ID"):
        image_id = _as_int(node.text.strip() if node.text else None)
        if image_id is None:
            continue
        try:
            images[image_id] = one.image_xml(session, image_id)
        except OneError as exc:
            images[image_id] = exc
    return vm_report(vm, images, cache)


def report_vms(one, cache, session, filter_flag=POOL_ALL):
    vms = parse_vm_pool(one.vm_pool_xml(session, filter_flag))
    images = parse_image_pool(one.image_pool_xml(session))
    report = summary_report(vms, images, cache)
    report["filter"] = pool_filter_name(filter_flag)
    return report


def _b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(text):
    pad = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


def jwt_hs256_encode(payload, key):
    """jwt-simple compatible HS256. Tests and nothing else."""
    header = _b64url(json.dumps({"typ": "JWT", "alg": "HS256"}, separators=(",", ":")).encode("utf-8"))
    body = _b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    sig = hmac.new(key.encode("utf-8"), ("%s.%s" % (header, body)).encode("ascii"), hashlib.sha256).digest()
    return "%s.%s.%s" % (header, body, _b64url(sig))


def jwt_hs256_decode(token, key):
    try:
        header_b, body_b, sig_b = token.split(".")
    except ValueError:
        raise AuthError("bad token")
    signing = ("%s.%s" % (header_b, body_b)).encode("ascii")
    try:
        signature = _b64url_decode(sig_b)
        payload = json.loads(_b64url_decode(body_b))
    except (ValueError, TypeError):
        raise AuthError("bad token")
    expected = hmac.new(key.encode("utf-8"), signing, hashlib.sha256).digest()
    if not hmac.compare_digest(expected, signature):
        raise AuthError("bad token")
    if not isinstance(payload, dict):
        raise AuthError("bad token")
    return payload


def key_candidates(path):
    try:
        text = open(path, "r", encoding="utf-8").read()
    except OSError as exc:
        raise AuthError("cannot read %s" % path) from exc
    if not text:
        raise AuthError("empty fireedge key")
    stripped = text.strip("\r\n")
    if stripped and stripped != text:
        return [text, stripped]
    return [text]


def session_from_cookie(header, keys):
    """FireedgeToken cookie -> 'user:token' for one.vm.info.

    keys is one or more copies of the fireedge key file (raw, and without a trailing newline).
    """
    if not header:
        raise AuthError("not logged in to FireEdge")
    raw = None
    for part in header.split(";"):
        name, eq, value = part.strip().partition("=")
        if eq and name == COOKIE_NAME:
            raw = value
            break
    if not raw:
        raise AuthError("not logged in to FireEdge")
    raw = urllib.parse.unquote(raw)
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = raw[1:-1]
    try:
        token = json.loads(raw).get("token")
    except (ValueError, AttributeError):
        token = raw
    if not token or not isinstance(token, str):
        raise AuthError("not logged in to FireEdge")
    last = AuthError("bad token")
    payload = None
    for key in keys:
        try:
            payload = jwt_hs256_decode(token, key)
            break
        except AuthError as exc:
            last = exc
    if payload is None:
        raise last
    user = payload.get("aud")
    secret = payload.get("jti")
    if not user or not secret:
        raise AuthError("bad token")
    return "%s:%s" % (user, secret)


def _read_auth(path):
    line = open(path, "r", encoding="utf-8").readline().strip()
    if ":" not in line:
        raise OneError("%s is not user:secret" % path)
    return line


def _json_bytes(payload, status=200):
    body = json.dumps(payload).encode("utf-8")
    return status, "application/json; charset=utf-8", body


class App(object):
    def __init__(self, one, cache, keys):
        self.one = one
        self.cache = cache
        self.keys = keys

    def current_cache(self):
        """Read the monitor files again. The process otherwise keeps the set it loaded at start."""
        directory = getattr(self.cache, "directory", None)
        if not directory:
            return self.cache
        return SpaceCache(directory)

    def do_get(self, handler):
        path = urllib.parse.urlsplit(handler.path).path
        if path in ("/", "/api/ui"):
            self._page(handler)
            return
        if path == "/remoteEntry.js":
            self._file(handler, REMOTE_ENTRY, "text/javascript; charset=utf-8")
            return
        if path == "/api/vms":
            self._vms(handler)
            return
        prefix = "/api/vm/"
        if path.startswith(prefix):
            self._vm(handler, path[len(prefix):])
            return
        _send(handler, 404, "text/plain; charset=utf-8", b"not found\n")

    def _file(self, handler, path, content_type):
        try:
            body = open(path, "rb").read()
        except OSError:
            _send(handler, 500, "text/plain; charset=utf-8", b"file is missing\n")
            return
        _send(handler, 200, content_type, body)

    def _page(self, handler):
        self._file(handler, STATIC_PAGE, "text/html; charset=utf-8")

    def _vms(self, handler):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(handler.path).query)
        raw = (query.get("filter") or [None])[0]
        try:
            flag = pool_filter(raw)
        except ValueError:
            status, ctype, body = _json_bytes(
                {"error": "filter must be all, mine, group, or primary"}, 400)
            _send(handler, status, ctype, body)
            return
        try:
            session = session_from_cookie(handler.headers.get("Cookie"), self.keys)
            report = report_vms(self.one, self.current_cache(), session, flag)
        except AuthError as exc:
            status, ctype, body = _json_bytes({"error": str(exc)}, 401)
            _send(handler, status, ctype, body)
            return
        except (OneError, ET.ParseError) as exc:
            status, ctype, body = _json_bytes({"error": str(exc)}, 502)
            _send(handler, status, ctype, body)
            return
        status, ctype, body = _json_bytes(report)
        _send(handler, status, ctype, body)

    def _vm(self, handler, vm_id):
        if not vm_id.isdigit():
            status, ctype, body = _json_bytes({"error": "vm id must be a number"}, 400)
            _send(handler, status, ctype, body)
            return
        try:
            session = session_from_cookie(handler.headers.get("Cookie"), self.keys)
            report = report_vm(self.one, self.current_cache(), session, int(vm_id))
        except AuthError as exc:
            status, ctype, body = _json_bytes({"error": str(exc)}, 401)
            _send(handler, status, ctype, body)
            return
        except (OneError, ET.ParseError) as exc:
            status, ctype, body = _json_bytes({"error": str(exc)}, 502)
            _send(handler, status, ctype, body)
            return
        status, ctype, body = _json_bytes(report)
        _send(handler, status, ctype, body)


def _send(handler, status, content_type, body):
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def make_handler(app):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):
            app.do_get(self)

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    return Handler


def serve(bind, port, one, cache, keys):
    httpd = ThreadingHTTPServer((bind, port), make_handler(App(one, cache, keys)))
    sys.stderr.write("backup-space http://%s:%s/\n" % (bind, port))
    httpd.serve_forever()


def main(argv):
    parser = argparse.ArgumentParser(description="StorPool backup space for one VM")
    parser.add_argument("--cache", default=os.environ.get("SP_BACKUP_SPACE_CACHE", DEFAULT_CACHE))
    parser.add_argument("--one-url", default=os.environ.get("SP_BACKUP_SPACE_ONE_URL", DEFAULT_ONE_URL))
    sub = parser.add_subparsers(dest="cmd")

    serve_p = sub.add_parser("serve", help="serve the page and /api/vm/<id>")
    serve_p.add_argument("--bind", default=os.environ.get("SP_BACKUP_SPACE_BIND", DEFAULT_BIND))
    serve_p.add_argument("--port", type=int, default=int(os.environ.get("SP_BACKUP_SPACE_PORT", DEFAULT_PORT)))
    serve_p.add_argument("--key", default=os.environ.get("SP_BACKUP_SPACE_KEY", DEFAULT_KEY))

    vm_p = sub.add_parser("vm", help="print one VM as JSON, using one_auth")
    vm_p.add_argument("vm_id")
    vm_p.add_argument("--session", default=os.environ.get("SP_BACKUP_SPACE_SESSION"))
    vm_p.add_argument("--auth-file", default=os.environ.get("ONE_AUTH", DEFAULT_AUTH))

    vms_p = sub.add_parser("vms", help="print the VM summary as JSON, using one_auth")
    vms_p.add_argument("--session", default=os.environ.get("SP_BACKUP_SPACE_SESSION"))
    vms_p.add_argument("--auth-file", default=os.environ.get("ONE_AUTH", DEFAULT_AUTH))
    vms_p.add_argument("--filter", default="all",
                       help="all, mine, group, or primary (the FireEdge pool filters)")

    args = parser.parse_args(argv)
    cache = SpaceCache(args.cache)
    if args.cmd == "serve":
        try:
            keys = key_candidates(args.key)
        except AuthError as exc:
            sys.stderr.write("%s\n" % exc)
            return 1
        serve(args.bind, args.port, OneClient(args.one_url), cache, keys)
        return 0
    if args.cmd == "vm":
        if not args.vm_id.isdigit():
            sys.stderr.write("vm id must be a number\n")
            return 2
        session = args.session or _read_auth(args.auth_file)
        report = report_vm(OneClient(args.one_url), cache, session, int(args.vm_id))
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if args.cmd == "vms":
        try:
            flag = pool_filter(args.filter)
        except ValueError:
            sys.stderr.write("filter must be all, mine, group, or primary\n")
            return 2
        session = args.session or _read_auth(args.auth_file)
        report = report_vms(OneClient(args.one_url), cache, session, flag)
        json.dump(report, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
