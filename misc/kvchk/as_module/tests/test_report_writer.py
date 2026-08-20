"""Tests for --report: the reported issues are logged to
per-category {timestamp}-{category}.txt files."""
import pytest
from unittest.mock import Mock

from storpool_kvchk.managers.base_manager import BaseManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.utils.report_writer import ReportWriter  # type: ignore[import-untyped] # noqa: E501


class FakeProcessor(BaseManager):
    """Reporting methods named like the DataProcessing passes"""

    def analyze_vm_disks(self):
        self.err("VM 1 one-sys-1-1-0 not in KV", "Issue")

    def _report_orphan_symlinks(self):
        self.err("orphan symlink on host1: disk.0", "Issue")
        self.dbg(0, "# ssh host1 rm -v disk.0  # verify before removing")

    def _report_hanging(self):
        self.err("hanging volume ~q.b.1", "Issue")

    def manager_error(self):
        self.err("API request failed")
        self.dbg(0, "[dry-run] execution chatter")


@pytest.fixture
def reporter(tmp_path):
    writer = ReportWriter(
        directory=str(tmp_path), timestamp="20260820-2034"
    )
    BaseManager.reporter = writer
    yield writer
    BaseManager.reporter = None
    writer.close()


@pytest.fixture
def processor():
    return FakeProcessor(Mock(verbose=0))


def test_issues_land_in_category_files(tmp_path, reporter, processor):
    processor.analyze_vm_disks()
    processor._report_orphan_symlinks()
    processor._report_hanging()

    vm_disks = tmp_path / "20260820-2034-vm-disks.txt"
    symlinks = tmp_path / "20260820-2034-symlinks.txt"
    hanging = tmp_path / "20260820-2034-hanging.txt"
    assert vm_disks.read_text() == "[Issue] VM 1 one-sys-1-1-0 not in KV\n"
    assert (
        symlinks.read_text()
        == "[Issue] orphan symlink on host1: disk.0\n"
        "# ssh host1 rm -v disk.0  # verify before removing\n"
    )
    assert hanging.read_text() == "[Issue] hanging volume ~q.b.1\n"


def test_uncategorized_err_lands_in_errors(tmp_path, reporter, processor):
    processor.manager_error()

    errors = tmp_path / "20260820-2034-errors.txt"
    # the err() is kept, the level-0 execution chatter is not
    assert errors.read_text() == "[Error] API request failed\n"


def test_no_issues_no_files(tmp_path, reporter, processor):
    processor.dbg(0, "[dummy] uncategorized level-0 line")

    assert reporter.close() == []
    assert list(tmp_path.iterdir()) == []


def test_no_reporter_no_files(tmp_path, processor):
    assert BaseManager.reporter is None
    processor.analyze_vm_disks()

    assert list(tmp_path.iterdir()) == []


def test_close_returns_written_paths(tmp_path, reporter, processor):
    processor.analyze_vm_disks()
    processor._report_hanging()

    assert reporter.close() == [
        str(tmp_path / "20260820-2034-hanging.txt"),
        str(tmp_path / "20260820-2034-vm-disks.txt"),
    ]
