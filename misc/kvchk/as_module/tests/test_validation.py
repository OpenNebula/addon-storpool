"""Tests for the three-way etcd <-> StorPool <-> OpenNebula
record validation."""
import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.enums import DiskType, ImageType  # type: ignore[import-untyped] # noqa: E501


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
    return args


@pytest.fixture
def processor(mock_args):
    """Setup with basic managers for validation testing"""
    ssh_manager = SshManager(mock_args)

    # Mock oneManager initialization to avoid real API calls
    with patch('storpool_kvchk.managers.one_manager.pyone'):
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0, stdout=b"")
            with patch.object(oneManager, '_init_hosts'):
                with patch.object(oneManager, '_init_datastores'):
                    with patch.object(oneManager, '_init_ds_images'):
                        with patch.object(oneManager, '_get_vm_disks'):
                            one_manager = oneManager(
                                mock_args, ssh_manager
                            )

    one_manager.vm_disks = {}
    one_manager.ds_images = {}
    one_manager.one_hosts = {}
    one_manager.one_datastores = {}
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


def _sp_vol(name, gid, **overrides):
    """A StorPool volume record"""
    data = {
        "globalId": gid,
        "name": name,
        "tags": {},
        "snapshot": False,
        "sp_api_http_host": "localhost",
    }
    data.update(overrides)
    return data


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
        "target": "/dev/storpool-byid/fir.b.jm",
    }
    data.update(overrides)
    return data


class TestSpByUid:
    """_sp_by_uid(): uid lookup must also find volumes still under
    their legacy name (sp.data is keyed by name, not by uid)."""

    def test_direct_key(self, processor):
        vol = _sp_vol("~fir.b.jm", "fir.b.jm")
        processor.sp.data = {"~fir.b.jm": vol}
        assert processor._sp_by_uid("~fir.b.jm") is vol

    def test_legacy_named_volume(self, processor):
        vol = _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        processor.sp.data = {"one-sys-26-1-raw": vol}
        assert processor._sp_by_uid("~fir.b.jm") is vol

    def test_missing(self, processor):
        processor.sp.data = {"~aaa.b.aa": _sp_vol("~aaa.b.aa", "aaa.b.aa")}
        assert processor._sp_by_uid("~fir.b.jm") is None


class TestKvByName:
    """analyze_kv_by_name(): byName entries validated against byUid,
    StorPool and OpenNebula."""

    def test_consistent_kv_uid_not_in_storpool(self, processor, capsys):
        """byName/byUid consistent but the uid has no StorPool record:
        an Issue with commented remediation hints (was a -vv debug)."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}

        processor.analyze_kv_by_name()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "UID not in StorPool!" in out
        assert "# etcdctl del /byName/one-sys-26-1" in out
        assert "# etcdctl del /byUid/~fir.b.jm" in out

    def test_consistent_kv_with_legacy_named_volume_ok(
        self, processor, capsys
    ):
        """The volume still carries its legacy name in StorPool but
        the globalId matches - no false 'not in StorPool'."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_kv_by_name()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_missing_uid_and_storpool_reported(self, processor, capsys):
        """byName entry with no byUid and no StorPool record is an
        Issue (was a -vv debug)."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}

        processor.analyze_kv_by_name()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "not in byUid and not in StorPool!" in out
        assert "# etcdctl del /byName/one-sys-26-1" in out

    def test_missing_uid_found_via_legacy_named_volume(self, processor):
        """byUid entry lost, the volume is still under its legacy name:
        the KV update is queued (uid resolved via the globalId index)."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_kv_by_name()

        entry = processor.update_data["one-sys-26-1"]
        assert "kv" in entry["action"]
        # write_kv_data() keys on 'spname'
        assert entry["data"]["spname"] == "one-sys-26-1"

    def test_stale_byname_record(self, processor, capsys):
        """byName entry with no OpenNebula and no StorPool backing is
        a stale KV record - both KV entries suggested for removal."""
        processor.etcd.data = {
            "byName": {"one-sys-99-0": "~old.b.xx"},
            "byUid": {"~old.b.xx": "one-sys-99-0"},
        }

        processor.analyze_kv_by_name()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "stale KV record" in out
        assert "etcdctl del /byName/one-sys-99-0" in out
        assert "etcdctl del /byUid/~old.b.xx" in out

    def test_byname_backed_by_storpool_not_flagged_stale(
        self, processor, capsys
    ):
        """byName entry unknown to OpenNebula (e.g. a backup image,
        not tracked in ds_images) but present in StorPool must not be
        suggested for deletion."""
        processor.etcd.data = {
            "byName": {"one-img-77": "~bkp.b.aa"},
            "byUid": {"~bkp.b.aa": "one-img-77"},
        }
        processor.sp.data = {
            "~bkp.b.aa": _sp_vol("~bkp.b.aa", "bkp.b.aa", snapshot=True)
        }

        processor.analyze_kv_by_name()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert "etcdctl del" not in out


class TestKvByUid:
    """analyze_kv_by_uid(): byUid entries validated against byName,
    OpenNebula and StorPool."""

    def test_one_record_not_in_storpool_reports_not_raises(
        self, processor, capsys
    ):
        """A byUid entry resolvable in ONE but missing from StorPool is
        reported as an Issue - it must not abort the validation run."""
        processor.etcd.data = {
            "byName": {},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}

        processor.analyze_kv_by_uid()  # no exception

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "not in StorPool!" in out

    def test_kvupdate_uses_current_spname(self, processor):
        """A byUid entry holding the legacy name is repaired under the
        current spname of the OpenNebula record."""
        processor.etcd.data = {
            "byName": {},
            "byUid": {"~fir.b.jm": "one-sys-26-1-raw"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "~fir.b.jm": _sp_vol("~fir.b.jm", "fir.b.jm")
        }

        processor.analyze_kv_by_uid()

        entry = processor.update_data["one-sys-26-1"]
        assert "kvupdate" in entry["action"]
        assert entry["data"]["spname"] == "one-sys-26-1"

    def test_process_updates_kv_actions_no_keyerror(self, processor):
        """write_kv_data() keys on 'spname': the kv/kvupdate records
        queued by the analysis must carry it (used to KeyError)."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1-raw"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "~fir.b.jm": _sp_vol("~fir.b.jm", "fir.b.jm")
        }

        processor.analyze_kv_by_name()
        processor.analyze_kv_by_uid()

        assert processor.update_data
        with patch('storpool_kvchk.managers.etcd_manager.etcd3'):
            processor.process_updates()  # no KeyError

    def test_fix_uid_mismatch_with_legacy_named_volume(
        self, processor, capsys
    ):
        """The uid mismatch remediation hints are printed also when
        the StorPool record is found via the globalId index."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~new.b.aa"},
            "byUid": {
                "~fir.b.jm": "one-sys-26-1",
                "~new.b.aa": "one-sys-26-1",
            },
        }
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_kv_by_uid()

        out = capsys.readouterr().out
        assert "etcdctl del /byUid/~fir.b.jm" in out
        assert "storpool -M -B volume ~fir.b.jm delete ~fir.b.jm" in out


class TestVmDisks:
    """analyze_vm_disks(): VM disks validated against KV and StorPool."""

    def test_kv_uid_missing_in_storpool(self, processor, capsys):
        """A KV-registered disk whose uid has no StorPool record is
        reported (this check did not exist)."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}

        processor.analyze_vm_disks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "UID ~fir.b.jm not in StorPool!" in out

    def test_kv_uid_legacy_named_volume_ok(self, processor, capsys):
        """No false report when the volume is still under its legacy
        name with a matching globalId."""
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_vm_disks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out


def _ds_image(**overrides):
    """An OpenNebula image record"""
    data = {
        "image_id": 48,
        "name": "an image",
        "spname": "one-img-48",
        "legacy": "one-img-48",
        "imagetype": ImageType.OS,
        "disktype": DiskType.PERSISTENT,
        "vms": 0,
        "vmlist": [],
        "snapshot": True,
        "snapshots": {},
    }
    data.update(overrides)
    return data


class TestImages:
    """analyze_one_images(): images and their snapshots validated
    against KV and StorPool."""

    def test_image_uid_missing_in_storpool(self, processor, capsys):
        """A KV-registered image whose uid has no StorPool record is
        an Issue at default verbosity (used to require -vv)."""
        processor.etcd.data = {
            "byName": {"one-img-48": "~img.b.aa"},
            "byUid": {"~img.b.aa": "one-img-48"},
        }
        processor.one.ds_images = {"one-img-48": _ds_image()}

        processor.analyze_one_images()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "UID not in StorPool!" in out

    def test_image_uid_via_legacy_named_volume_ok(
        self, processor, capsys
    ):
        """No false report when the image data is still under the
        legacy StorPool name with a matching globalId."""
        processor.etcd.data = {
            "byName": {"one-img-48": "~img.b.aa"},
            "byUid": {"~img.b.aa": "one-img-48"},
        }
        processor.one.ds_images = {"one-img-48": _ds_image()}
        processor.sp.data = {
            "one-img-48": _sp_vol("one-img-48", "img.b.aa", snapshot=True)
        }

        processor.analyze_one_images()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_image_snapshot_missing_in_storpool(self, processor, capsys):
        """A KV-registered image snapshot missing from StorPool is an
        Issue at default verbosity (used to be a -v debug)."""
        processor.etcd.data = {
            "byName": {
                "one-img-48": "~img.b.aa",
                "one-img-48-snap0": "~img.b.ab",
            },
            "byUid": {
                "~img.b.aa": "one-img-48",
                "~img.b.ab": "one-img-48-snap0",
            },
        }
        processor.one.ds_images = {
            "one-img-48": _ds_image(
                snapshots={
                    "one-img-48-snap0": {
                        "spname": "one-img-48-snap0",
                        "legacy": "one-img-48-snap0",
                        "snap": "snap0",
                        "snapshot": True,
                    }
                }
            )
        }
        processor.sp.data = {
            "~img.b.aa": _sp_vol("~img.b.aa", "img.b.aa", snapshot=True)
        }

        processor.analyze_one_images()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "StorPool snapshot not found!" in out


class TestStorpoolGlobalId:
    """_analyze_storpool_globalid(): migrated (~globalId) StorPool
    records validated against KV and OpenNebula, with KV repair."""

    def test_repair_lost_byname(self, processor, capsys):
        """byUid intact but byName lost: the pair is re-queued when
        OpenNebula confirms the record (used to be a note only)."""
        processor.etcd.data = {
            "byName": {},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "~fir.b.jm": _sp_vol("~fir.b.jm", "fir.b.jm")
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "not in byName/" in out
        entry = processor.update_data["one-sys-26-1"]
        assert "kv" in entry["action"]
        assert entry["data"]["spname"] == "one-sys-26-1"
        assert entry["data"]["uid"] == "fir.b.jm"

    def test_repair_from_tags_no_kv(self, processor, capsys):
        """KV lost entirely: the OpenNebula record is resolved via the
        StorPool tags and the KV pair is re-queued."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "~fir.b.jm": _sp_vol(
                "~fir.b.jm",
                "fir.b.jm",
                tags={
                    "virt": "one",
                    "nloc": "one",
                    "nvm": "26",
                    "diskid": "1",
                    "img": "one-sys-26-1",
                },
            )
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "KV repair queued" in out
        entry = processor.update_data["one-sys-26-1"]
        assert "kv" in entry["action"]
        assert entry["data"]["uid"] == "fir.b.jm"

    def test_repair_snapshot_from_tags(self, processor):
        """A snapshot with lost KV is resolved by img+snap tags."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {
            "one-img-48": _ds_image(
                snapshots={
                    "one-img-48-snap0": {
                        "spname": "one-img-48-snap0",
                        "legacy": "one-img-48-snap0",
                        "snap": "snap0",
                        "snapshot": True,
                    }
                }
            )
        }
        processor.sp.data = {
            "~img.b.ab": _sp_vol(
                "~img.b.ab",
                "img.b.ab",
                snapshot=True,
                tags={
                    "virt": "one",
                    "nloc": "one",
                    "img": "one-img-48",
                    "snap": "snap0",
                },
            )
        }

        processor.analyze_storpool()

        entry = processor.update_data["one-img-48-snap0"]
        assert "kv" in entry["action"]
        assert entry["data"]["uid"] == "img.b.ab"

    def test_orphan_tagged_volume_note(self, processor, capsys):
        """A volume tagged for this OpenNebula instance without any
        matching record is reported as a possible orphan."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.sp.data = {
            "~fir.b.jm": _sp_vol(
                "~fir.b.jm",
                "fir.b.jm",
                tags={
                    "virt": "one",
                    "nloc": "one",
                    "nvm": "99",
                    "diskid": "0",
                    "img": "one-sys-99-0",
                },
            )
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "[NOTE]" in out
        assert "orphan?" in out
        assert processor.update_data == {}

    def test_foreign_volume_silent(self, processor, capsys):
        """Volumes not tagged for this OpenNebula instance do not
        produce notes (no spam for foreign/untagged volumes)."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.sp.data = {
            "~aaa.b.aa": _sp_vol("~aaa.b.aa", "aaa.b.aa"),
            "~bbb.b.bb": _sp_vol(
                "~bbb.b.bb",
                "bbb.b.bb",
                tags={"virt": "one", "nloc": "two", "img": "two-img-1"},
            ),
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "[NOTE]" not in out
        assert processor.update_data == {}
