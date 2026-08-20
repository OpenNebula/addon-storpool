"""Log the reported issues to per-category files (--report)."""
from __future__ import annotations
from typing import Dict, List, Optional, TextIO

import os
import time

# Map the reporting method to the issue category (the file name
# suffix). Reports from methods not listed here land in 'errors'.
CALLER_CATEGORIES: Dict[str, str] = {
    # KV (etcd) byName/byUid consistency
    "analyze_kv_by_name": "kv",
    "_kv_check_one_record": "kv",
    "_kv_check_name_uid_match": "kv",
    "_kv_handle_missing_uid": "kv",
    "analyze_kv_by_uid": "kv",
    "_fix_uid_mismatch": "kv",
    "_fix_one_data": "kv",
    "_queue_kv_repair": "kv",
    # VM disks vs KV/StorPool
    "analyze_vm_disks": "vm-disks",
    # OpenNebula images vs KV/StorPool
    "analyze_one_images": "images",
    "_analyze_one_image_snapshots": "images",
    # StorPool volumes/snapshots vs OpenNebula
    "analyze_storpool": "volumes",
    "_analyze_storpool_globalid": "volumes",
    "_analyze_storpool_legacy": "volumes",
    # unreachable StorPool records
    "analyze_hanging": "hanging",
    "_report_hanging": "hanging",
    "_report_foreign": "foreign",
    # several StorPool records claiming one OpenNebula record
    "analyze_duplicates": "duplicates",
    "_report_duplicates": "duplicates",
    "_report_leftovers": "duplicates",
    # disk.N symlinks on the hosts and the frontend
    "analyze_host_symlinks": "symlinks",
    "_report_missing_frontend_data": "symlinks",
    "_report_undeployed_symlink": "symlinks",
    "_report_orphan_symlinks": "symlinks",
    # queued updates blocked from execution
    "process_updates": "updates",
}


class ReportWriter:
    """Write the reported issues to {timestamp}-{category}.txt files.

    The files are created lazily - a category with no issues leaves
    no file behind. The same lines that go to stdout are written, so
    the files can be grepped/diffed between runs."""

    def __init__(
        self, directory: str = ".", timestamp: Optional[str] = None
    ) -> None:
        self.directory: str = directory
        self.timestamp: str = timestamp or time.strftime("%Y%m%d-%H%M")
        self._files: Dict[str, TextIO] = {}

    def category(self, caller: str) -> Optional[str]:
        """The issue category of a reporting method, None if unknown"""
        return CALLER_CATEGORIES.get(caller)

    def path(self, category: str) -> str:
        """The report file path of a category"""
        return os.path.join(
            self.directory, f"{self.timestamp}-{category}.txt"
        )

    def write(self, category: str, line: str) -> None:
        """Append a line to the category report file"""
        out: Optional[TextIO] = self._files.get(category)
        if out is None:
            out = open(self.path(category), "a")
            self._files[category] = out
        out.write(line + "\n")
        out.flush()

    def files(self) -> List[str]:
        """The report files written so far"""
        return sorted(
            self.path(category) for category in self._files
        )

    def close(self) -> List[str]:
        """Close the report files, return their paths"""
        paths: List[str] = self.files()
        for out in self._files.values():
            out.close()
        self._files = {}
        return paths
