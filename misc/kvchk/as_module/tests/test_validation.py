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
        matching record is reported by the hanging analysis (not by
        analyze_storpool anymore)."""
        processor.args.hanging_min_age = 3600
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
        assert "orphan?" not in out

        processor.analyze_hanging()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "hanging volume ~fir.b.jm" in out
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


def _checkpoint_disk(**overrides):
    """ONE record for a STOPPED/SUSPENDED VM checkpoint volume"""
    data = {
        "vm_id": 26,
        "spname": "one-sys-26-rawcheckpoint",
        "img": "one-sys-26-rawcheckpoint",
        "legacy": "one-sys-26-rawcheckpoint",
        "snapshot": False,
        "disktype": DiskType.CHECKPOINT,
        "nloc": "one",
        "virt": "one",
        "state": 4,
        "lcm_state": 0,
    }
    data.update(overrides)
    return data


def _context_disk(**overrides):
    """ONE record for a CONTEXT iso volume (legacy suffix -iso)"""
    data = {
        "vm_id": 26,
        "disk_id": 2,
        "spname": "one-sys-26-2",
        "img": "one-sys-26-2",
        "legacy": "one-sys-26-2-iso",
        "snapshot": False,
        "disktype": DiskType.CONTEXT,
        "host": "kvm1",
        "nloc": "one",
        "virt": "one",
        "state": 3,
        "lcm_state": 3,
        "sys_ds_id": 0,
        "link": "/var/lib/one/datastores/0/26/disk.2",
    }
    data.update(overrides)
    return data


class TestStorpoolLegacy:
    """_analyze_storpool_legacy(): volumes still under a human-readable
    name must be queued for rename to the multicluster ~globalId form."""

    def test_legacy_volume_queued_when_kv_already_ok(self, processor, capsys):
        """KV already maps the current spname; StorPool still carries
        the legacy name. analyze_vm_disks stays quiet (no TO_MIGRATE),
        but analyze_storpool must still queue the Update rename."""
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
        assert "TO_MIGRATE" not in out
        assert processor.update_data == {}

        processor.analyze_storpool()

        entry = processor.update_data["one-sys-26-1"]
        assert "Update" in entry["action"]
        assert entry["data"]["uid"] == "fir.b.jm"
        assert entry["data"]["legacy"] == "one-sys-26-1-raw"
        assert entry["data"]["spname"] == "one-sys-26-1"

    def test_legacy_volume_queued_when_not_in_kv(self, processor, capsys):
        """No KV entry: analyze_vm_disks reports TO_MIGRATE and
        analyze_storpool queues the Update."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.sp.data = {
            "one-sys-26-1-raw": _sp_vol("one-sys-26-1-raw", "fir.b.jm")
        }

        processor.analyze_vm_disks()
        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "<<TO_MIGRATE>>" in out
        assert "legacy:one-sys-26-1-raw" in out

        processor.analyze_storpool()

        entry = processor.update_data["one-sys-26-1"]
        assert "Update" in entry["action"]
        assert "kv" in entry["action"]
        assert entry["data"]["uid"] == "fir.b.jm"

    @pytest.mark.parametrize(
        "legacy_name,spname,disk_factory",
        [
            ("one-sys-26-1-raw", "one-sys-26-1", _vm_disk),
            ("one-sys-26-2-iso", "one-sys-26-2", _context_disk),
        ],
    )
    def test_legacy_suffix_variants_queued(
        self, processor, legacy_name, spname, disk_factory
    ):
        """Volatile -raw and CONTEXT -iso legacy names resolve via
        the ONE legacy field and queue an Update."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.vm_disks = {spname: disk_factory()}
        processor.sp.data = {
            legacy_name: _sp_vol(legacy_name, "fir.b.jm")
        }

        processor.analyze_storpool()

        entry = processor.update_data[spname]
        assert "Update" in entry["action"]
        assert entry["data"]["legacy"] == legacy_name

    def test_image_legacy_queued_for_multicluster(self, processor, capsys):
        """An image still under its legacy StorPool name (not in KV)
        is reported TO_MIGRATE and queued for Update."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {"one-img-48": _ds_image()}
        processor.sp.data = {
            "one-img-48": _sp_vol(
                "one-img-48", "img.b.aa", snapshot=True
            )
        }

        processor.analyze_one_images()
        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "<TO_MIGRATE>" in out

        processor.analyze_storpool()

        entry = processor.update_data["one-img-48"]
        assert "Update" in entry["action"]
        assert entry["data"]["uid"] == "img.b.aa"

    def test_no_one_record_not_queued(self, processor, capsys):
        """A legacy-named volume with no matching ONE record is not
        queued for migration (hanging analysis covers leftovers)."""
        processor.args.hanging_min_age = 0
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.sp.data = {
            "one-sys-99-0-raw": _sp_vol("one-sys-99-0-raw", "old.b.xx")
        }

        processor.analyze_storpool()
        assert processor.update_data == {}

        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging volume one-sys-99-0-raw" in out

    def test_name_mismatch_reachable_by_tags_queued(
        self, processor, capsys
    ):
        """StorPool name is neither spname nor legacy (e.g. checkpoint
        vs rawcheckpoint), but tags resolve to the ONE record: the
        volume is still queued for the multicluster rename (tags
        fallback, same recovery as the ~globalId path)."""
        processor.args.hanging_min_age = 0
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.vm_disks = {
            "one-sys-26-rawcheckpoint": _checkpoint_disk()
        }
        processor.sp.data = {
            "one-sys-26-checkpoint": _sp_vol(
                "one-sys-26-checkpoint",
                "chk.b.aa",
                tags={
                    "virt": "one",
                    "nloc": "one",
                    "img": "one-sys-26-rawcheckpoint",
                },
            )
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "matched ONE one-sys-26-rawcheckpoint by tags" in out
        entry = processor.update_data["one-sys-26-rawcheckpoint"]
        assert "Update" in entry["action"]
        assert entry["data"]["uid"] == "chk.b.aa"
        assert "kv" in entry["action"]

        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging" not in out

    def test_npers_base_in_ds_images_queued_normally(self, processor, capsys):
        """When imagepool.info(ALL) includes the base image, the
        legacy volume is migrated via normal ds_images lookup (no
        clone-based recovery needed)."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {
            "one-img-1448": _ds_image(
                image_id=1448,
                spname="one-img-1448",
                legacy="one-img-1448",
                disktype=DiskType.NONPERSISTENT,
                snapshot=True,
                vms=3,
                vmlist=[4951, 4961, 5011],
            )
        }
        processor.one.vm_disks = {}
        processor.sp.data = {
            "one-img-1448": _sp_vol("one-img-1448", "n9jc.b.jpk", tags={})
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "recovered as NPERS base" not in out
        entry = processor.update_data["one-img-1448"]
        assert "VolumeFreeze" in entry["action"]
        assert "Update" in entry["action"]

    def test_npers_base_image_missing_from_ds_images_queued(
        self, processor, capsys
    ):
        """Base image one-img-N is a leftover StorPool volume (empty
        tags) and absent from ds_images (filter/ACL miss), while NPERS
        clone disks one-img-N-{vm}-{disk} still exist in ONE.

        Safety net when imagepool.info did not return the image: recover
        from clones and queue VolumeFreeze + multicluster rename."""
        processor.args.hanging_min_age = 0
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {}
        processor.one.vm_disks = {
            "one-img-1448-4951-0": {
                "vm_id": 4951,
                "disk_id": 0,
                "spname": "one-img-1448-4951-0",
                "img": "one-img-1448-4951-0",
                "legacy": "one-img-1448-4951-0",
                "snapshot": False,
                "disktype": DiskType.NONPERSISTENT,
                "nloc": "one",
                "virt": "one",
                "state": 3,
                "lcm_state": 3,
            }
        }
        processor.sp.data = {
            "one-img-1448": _sp_vol(
                "one-img-1448",
                "n9jc.b.jpk",
                tags={},
                parentName="one-img-1448@9642",
            ),
            "~n9jc.b.mm7": _sp_vol(
                "~n9jc.b.mm7",
                "n9jc.b.mm7",
                tags={
                    "virt": "one",
                    "nloc": "one",
                    "type": "NPERS",
                    "img": "one-img-1448-4951-0",
                    "nvm": "4951",
                    "diskid": "0",
                },
            ),
        }

        processor.analyze_storpool()

        out = capsys.readouterr().out
        assert "recovered as NPERS base image 1448 from clones" in out
        entry = processor.update_data["one-img-1448"]
        assert "VolumeFreeze" in entry["action"]
        assert "Update" in entry["action"]
        assert entry["data"]["uid"] == "n9jc.b.jpk"
        assert entry["data"]["snapshot"] is False

        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging volume one-img-1448" not in out

    def test_npers_base_without_clones_not_recovered(self, processor):
        """An orphan one-img-N volume with no clone disks is not
        synthesised into a base-image record."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {}
        processor.one.vm_disks = {}
        processor.sp.data = {
            "one-img-1448": _sp_vol("one-img-1448", "n9jc.b.jpk")
        }

        processor.analyze_storpool()

        assert "one-img-1448" not in processor.update_data


def _attached(volume, client=27, rights="rw"):
    """A StorPool attachment record"""
    return {
        "volume": volume,
        "client": [client],
        "rights": [rights],
        "count": 1,
    }


class TestBlockedActions:
    """Attached volumes due for conversion are skipped and reported"""

    def test_attached_image_blocks_the_record(self, processor):
        """An attached image gets the block reason and detach command"""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {
            "one-img-200": _ds_image(
                image_id=200, spname="one-img-200", legacy="one-img-200"
            )
        }
        processor.sp.data = {
            "one-img-200": _sp_vol(
                "one-img-200",
                "n9wb.b.qr1d",
                attached=_attached("one-img-200"),
            )
        }

        processor.analyze_storpool()

        entry = processor.update_data["one-img-200"]
        assert "VolumeFreeze" in entry["action"]
        assert "attached to client(s) [27]" in entry["data"]["blocked"]
        assert entry["data"]["blocked_cmds"] == [
            "storpool detach volume one-img-200 client 27"
        ]

    def test_detached_image_not_blocked(self, processor):
        """The same image without an attachment is queued normally."""
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.one.ds_images = {
            "one-img-200": _ds_image(
                image_id=200, spname="one-img-200", legacy="one-img-200"
            )
        }
        processor.sp.data = {
            "one-img-200": _sp_vol("one-img-200", "n9wb.b.qr1d")
        }

        processor.analyze_storpool()

        entry = processor.update_data["one-img-200"]
        assert "VolumeFreeze" in entry["action"]
        assert "blocked" not in entry["data"]

    def test_blocked_record_actions_not_executed(self, processor, capsys):
        """process_updates() skips blocked records and prints why"""
        processor.args.execute = True
        processor.update_data = {
            "one-img-200": {
                "action": ["VolumeFreeze", "Update", "kv"],
                "data": {
                    "uid": "n9wb.b.qr1d",
                    "spname": "one-img-200",
                    "snapshot": False,
                    "sp_api_http_host": "localhost",
                    "blocked": "one-img-200 must be converted to a"
                               " snapshot but is attached to client(s)"
                               " [27] ['rw']",
                    "blocked_cmds": [
                        "storpool detach volume one-img-200 client 27"
                    ],
                },
            }
        }
        processor.sp.volumefreeze = Mock()
        processor.sp.action = Mock()
        processor.etcd.action = Mock()

        processor.process_updates()

        processor.sp.volumefreeze.assert_not_called()
        processor.sp.action.assert_not_called()
        processor.etcd.action.assert_not_called()
        out = capsys.readouterr().out
        assert "[BLOCKED]" in out
        assert "NOT executed" in out
        assert "storpool detach volume one-img-200 client 27" in out
