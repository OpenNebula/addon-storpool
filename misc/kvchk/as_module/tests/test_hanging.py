"""Tests for the hanging StorPool volume/snapshot detection -
records that OpenNebula/addon-storpool can no longer reach."""
import time

import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.enums import DiskType  # type: ignore[import-untyped] # noqa: E501

OLD = time.time() - 7 * 86400


@pytest.fixture
def mock_args():
    args = Mock()
    args.verbose = 0
    args.dry_run = False
    args.execute = False
    args.one_px = "one"
    args.one_token = None
    args.dummy_etcd = 0
    args.default_qosclass = "default-qos"
    args.skip_undeploy_ssh = False
    args.sp_checkpoint_bd = False
    args.hanging_min_age = 3600
    args.report_foreign = False
    return args


@pytest.fixture
def processor(mock_args):
    """Setup with basic managers for hanging record testing"""
    ssh_manager = SshManager(mock_args)

    with patch('storpool_kvchk.managers.one_manager.pyone'):
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0, stdout=b"")
            with patch.object(oneManager, '_init_hosts'):
                with patch.object(oneManager, '_init_datastores'):
                    with patch.object(oneManager, '_init_ds_images'):
                        with patch.object(oneManager, '_init_frontend'):
                            with patch.object(oneManager, '_get_vm_disks'):  # noqa: E501
                                one_manager = oneManager(
                                    mock_args, ssh_manager
                                )

    one_manager.vm_disks = {}
    one_manager.ds_images = {}
    one_manager.one_hosts = {}
    one_manager.one_datastores = {}
    one_manager.one_vms = {}
    one_manager.frontend = {}
    one_manager.vm_ids = []

    with patch('storpool_kvchk.managers.storpool_manager.SPConfig'):
        sp_manager = spManager(mock_args)
    sp_manager.data = {}

    with patch.object(etcdManager, '_load_data'):
        etcd_manager = etcdManager(mock_args)
    etcd_manager.data = {"byName": {}, "byUid": {}}

    return DataProcessing(
        mock_args,
        etcd_manager,
        sp_manager,
        one_manager,
        ssh_manager
    )


def _sp_rec(name, gid, **overrides):
    """A StorPool volume/snapshot record"""
    data = {
        "globalId": gid,
        "name": name,
        "tags": {},
        "size": 1024,
        "snapshot": False,
        "parentName": "",
        "creationTimestamp": OLD,
        "sp_api_http_host": "localhost",
    }
    data.update(overrides)
    return data


def _one_tags(**overrides):
    """Tags of a record owned by this OpenNebula instance"""
    tags = {"virt": "one", "nloc": "one"}
    tags.update(overrides)
    return tags


def _vm_disk(**overrides):
    """A migrated running VM disk record"""
    data = {
        "vm_id": 26,
        "disk_id": 1,
        "spname": "one-sys-26-1",
        "img": "one-sys-26-1",
        "legacy": "one-sys-26-1-raw",
        "snapshot": False,
        "disktype": DiskType.VOLATILE,
        "host": "kvm1",
        "state": 3,
        "lcm_state": 3,
        "sys_ds_id": 0,
        "link": "/var/lib/one/datastores/0/26/disk.1",
    }
    data.update(overrides)
    return data


class TestHangingDetection:
    """Records not reachable through any relation are reported"""

    def test_tagged_orphan_volume(self, processor, capsys):
        """A volume tagged for this instance without any ONE record
        or KV entry is hanging."""
        processor.sp.data = {
            "~fir.b.jm": _sp_rec(
                "~fir.b.jm", "fir.b.jm",
                tags=_one_tags(nvm="99", diskid="0", img="one-sys-99-0"),
            )
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "hanging volume ~fir.b.jm" in out
        assert "not referenced by any OpenNebula record" in out
        assert (
            "# storpool -M -B volume ~fir.b.jm delete ~fir.b.jm"
        ) in out
        assert processor.update_data == {}

    def test_tagged_orphan_in_stale_kv(self, processor, capsys):
        """A tagged volume referenced only by KV entries whose ONE
        record is gone is hanging."""
        processor.etcd.data = {
            "byName": {"one-sys-99-0": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-99-0"},
        }
        processor.sp.data = {
            "~fir.b.jm": _sp_rec(
                "~fir.b.jm", "fir.b.jm",
                tags=_one_tags(nvm="99", diskid="0", img="one-sys-99-0"),
            )
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "hanging volume ~fir.b.jm" in out
        assert "in KV, but the OpenNebula record is gone" in out

    def test_legacy_named_leftover(self, processor, capsys):
        """An untagged volume matching the addon naming without any
        ONE record is hanging."""
        processor.sp.data = {
            "one-sys-99-0-raw": _sp_rec("one-sys-99-0-raw", "fir.b.jm")
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "hanging volume one-sys-99-0-raw" in out
        assert "(globalId fir.b.jm)" in out
        assert "matches the addon naming" in out

    def test_untagged_stale_kv_reference(self, processor, capsys):
        """An untagged renamed volume referenced only by a stale KV
        entry is hanging."""
        processor.etcd.data = {
            "byName": {"one-img-9": "~gon.e.xx"},
            "byUid": {},
        }
        processor.sp.data = {
            "~gon.e.xx": _sp_rec("~gon.e.xx", "gon.e.xx")
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "hanging volume ~gon.e.xx" in out
        assert "referenced only by stale KV entries" in out


class TestHangingExclusions:
    """Records that must not be reported as hanging"""

    def test_foreign_records_silent(self, processor, capsys):
        """Untagged, foreign-named and other-instance records are
        not reported."""
        processor.sp.data = {
            # no tags, non-addon name
            "database-vol1": _sp_rec("database-vol1", "aaa.b.aa"),
            # renamed, no tags, not in KV
            "~bbb.b.bb": _sp_rec("~bbb.b.bb", "bbb.b.bb"),
            # tagged for another OpenNebula instance
            "~ccc.b.cc": _sp_rec(
                "~ccc.b.cc", "ccc.b.cc",
                tags={"virt": "one", "nloc": "two", "img": "two-img-1"},
            ),
            # other instance prefix in the legacy name
            "two-img-5": _sp_rec("two-img-5", "ddd.b.dd"),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_storpool_internal_records_silent(self, processor, capsys):
        """Deleted, transient, anonymous and delayed-delete records
        are handled by StorPool itself."""
        processor.sp.data = {
            "*one-img-5": _sp_rec(
                "*one-img-5", "aaa.b.aa", snapshot=True, deleted=True,
            ),
            "~trn.b.aa": _sp_rec(
                "~trn.b.aa", "trn.b.aa", snapshot=True, transient=True,
                tags=_one_tags(),
            ),
            "~ano.b.aa": _sp_rec(
                "~ano.b.aa", "ano.b.aa", snapshot=True, autoName=True,
            ),
            "~del.b.aa": _sp_rec(
                "~del.b.aa", "del.b.aa", snapshot=True,
                targetDeleteDate=int(OLD) + 30 * 86400,
                tags=_one_tags(reason="revert"),
            ),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_young_record_suppressed(self, processor, capsys):
        """A record younger than --hanging-min-age could belong to
        an operation still in progress."""
        processor.sp.data = {
            "~fir.b.jm": _sp_rec(
                "~fir.b.jm", "fir.b.jm",
                tags=_one_tags(img="one-img-77"),
                creationTimestamp=time.time() - 60,
            )
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out


class TestHangingReachable:
    """Records reachable through any relation are not reported"""

    def test_reachable_via_kv(self, processor, capsys):
        """A record found through KV byUid and the ONE data is not
        hanging."""
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.sp.data = {
            "~fir.b.jm": _sp_rec("~fir.b.jm", "fir.b.jm")
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_reachable_via_legacy_name(self, processor, capsys):
        """A volume still under its legacy name backed by a ONE
        record is not hanging."""
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_rec("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_reachable_via_tags(self, processor, capsys):
        """A renamed volume with lost KV entries matching a ONE
        record by tags is not hanging."""
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "~fir.b.jm": _sp_rec(
                "~fir.b.jm", "fir.b.jm",
                tags=_one_tags(
                    nvm="26", diskid="1", img="one-sys-26-1",
                ),
            )
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" not in out


class TestForeignReport:
    """Inventory of the records not related to this OpenNebula
    instance with --report-foreign"""

    def test_foreign_records_reported(self, processor, capsys):
        """With --report-foreign all foreign records are inventoried
        with their details, tagged [Foreign] and not as issues."""
        processor.args.report_foreign = True
        processor.sp.data = {
            "database-vol1": _sp_rec(
                "database-vol1", "aaa.b.aa",
                clusterId="nvme.b",
                templateName="hybrid",
                attached={"client": [7], "volume": "database-vol1"},
            ),
            "~ccc.b.cc": _sp_rec(
                "~ccc.b.cc", "ccc.b.cc", snapshot=True,
                tags={"virt": "one", "nloc": "two", "img": "two-img-1"},
            ),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Foreign]" in out
        assert (
            "foreign volume database-vol1 (globalId aaa.b.aa)"
        ) in out
        assert "template hybrid" in out
        assert "cluster nvme.b" in out
        assert "attached to client(s) [7]" in out
        assert "foreign snapshot ~ccc.b.cc" in out
        assert "'nloc': 'two'" in out
        assert "[Issue]" not in out
        # inventory only, no removal suggestions
        assert "delete" not in out
        assert processor.update_data == {}

    def test_foreign_not_reported_by_default(self, processor, capsys):
        """Without --report-foreign the foreign records stay silent."""
        processor.sp.data = {
            "database-vol1": _sp_rec("database-vol1", "aaa.b.aa"),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Foreign]" not in out

    def test_foreign_report_keeps_internal_silent(
        self, processor, capsys
    ):
        """StorPool-internal records are not inventoried as foreign."""
        processor.args.report_foreign = True
        processor.sp.data = {
            "*gone-vol": _sp_rec(
                "*gone-vol", "aaa.b.aa", snapshot=True, deleted=True,
            ),
            "~trn.b.aa": _sp_rec(
                "~trn.b.aa", "trn.b.aa", snapshot=True, transient=True,
            ),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Foreign]" not in out

    def test_own_records_not_inventoried(self, processor, capsys):
        """Reachable and hanging records of this instance are not
        tagged [Foreign] - a hanging one stays an [Issue]."""
        processor.args.report_foreign = True
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.sp.data = {
            # reachable via KV
            "~fir.b.jm": _sp_rec("~fir.b.jm", "fir.b.jm"),
            # hanging (tagged for this instance)
            "~han.b.aa": _sp_rec(
                "~han.b.aa", "han.b.aa",
                tags=_one_tags(img="one-img-99"),
            ),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Foreign]" not in out
        assert "[Issue]" in out
        assert "hanging volume ~han.b.aa" in out


class TestHangingSafety:
    """No delete suggestion for records that are still in use"""

    def test_attached_hanging_volume(self, processor, capsys):
        """A hanging volume still attached to a client must be
        investigated, not deleted."""
        processor.sp.data = {
            "~fir.b.jm": _sp_rec(
                "~fir.b.jm", "fir.b.jm",
                tags=_one_tags(img="one-sys-99-0"),
                attached={"client": [12], "volume": "~fir.b.jm"},
            )
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "hanging volume ~fir.b.jm" in out
        assert "attached to client(s) [12]" in out
        assert "investigate before removing" in out
        assert "delete" not in out

    def test_hanging_parent_snapshot(self, processor, capsys):
        """A hanging snapshot that is the parent of other StorPool
        records must not be deleted."""
        processor.sp.data = {
            "~snp.b.aa": _sp_rec(
                "~snp.b.aa", "snp.b.aa", snapshot=True,
                tags=_one_tags(img="one-img-77"),
            ),
            # a foreign volume cloned from the hanging snapshot
            "~chl.b.aa": _sp_rec(
                "~chl.b.aa", "chl.b.aa", parentName="~snp.b.aa",
            ),
        }

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "hanging snapshot ~snp.b.aa" in out
        assert "parent of 1 StorPool object(s) - do not delete" in out
        assert "storpool -M -B snapshot ~snp.b.aa" not in out
