"""Tests for the StorPool backup datastore rules: kept backup
snapshots (bkp), service volumes (SVC) and the /bkName/ KV records."""
import time

import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager, parse_backup_source  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501

OLD = time.time() - 7 * 86400
EPOCH = 1793976561


@pytest.fixture
def mock_args():
    args = Mock()
    args.verbose = 0
    args.dry_run = False
    args.execute = False
    args.one_px = "one"
    args.vm_tag = "nvm"
    args.loc_tag = "nloc"
    args.loc_tag_val = "one"
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
    one_manager.backup_images = {}
    one_manager.one_hosts = {}
    one_manager.one_datastores = {}
    one_manager.one_vms = {}
    one_manager.frontend = {}
    one_manager.vm_ids = []
    one_manager.vm_list = {}

    with patch('storpool_kvchk.managers.storpool_manager.SPConfig'):
        sp_manager = spManager(mock_args)
    sp_manager.data = {}

    with patch.object(etcdManager, '_load_data'):
        etcd_manager = etcdManager(mock_args)
    etcd_manager.data = {"byName": {}, "byUid": {}, "bkName": {}}

    return DataProcessing(
        mock_args, etcd_manager, sp_manager, one_manager, ssh_manager
    )


def _snap(gid, **tags):
    all_tags = {"virt": "one", "nloc": "one", "nvm": "4"}
    all_tags.update(tags)
    return {
        "globalId": gid,
        "name": f"~{gid}",
        "tags": all_tags,
        "size": 1024,
        "snapshot": True,
        "parentName": "",
        "creationTimestamp": OLD,
        "sp_api_http_host": "localhost",
    }


def _backup_image(vm_id=4, epoch=EPOCH, location="local", ids=None):
    ids = ids or {"0": "fir.b.btbe", "nvram": "fir.b.btbj", "svc": "fir.b.btbk"}
    return {
        "image_id": 8, "name": "4 backup", "datastore_id": 105,
        "state": 1, "location": location, "vm_id": vm_id,
        "epoch": epoch, "ids": ids,
    }


class TestBackupSource:

    def test_parse_local(self):
        m = parse_backup_source("local:4:1793976561:0=fir.b.btbe,nvram=fir.b.btbj,svc=fir.b.btbk")
        assert m == {
            "location": "local", "vm_id": 4, "epoch": 1793976561,
            "ids": {"0": "fir.b.btbe", "nvram": "fir.b.btbj", "svc": "fir.b.btbk"},
        }

    def test_parse_remote_strips_tilde(self):
        m = parse_backup_source("devA1:3:1793977538:0=~fir.b.btbh,svc=fir.b.btb7")
        assert m["location"] == "devA1"
        assert m["ids"] == {"0": "fir.b.btbh", "svc": "fir.b.btb7"}

    def test_other_drivers_source(self):
        assert parse_backup_source("102/7/1762400000") is None
        assert parse_backup_source("") is None
        assert parse_backup_source(None) is None
        assert parse_backup_source("local:4:abc:0=x") is None
        assert parse_backup_source("local:4:1793976561:0=") is None


class TestKeptBackupSnapshots:

    def test_kept_by_backup_image(self, processor, capsys):
        processor.one.backup_images = {8: _backup_image()}
        processor.sp.data = {
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", img="one-img-3-4-0"),
            "~fir.b.btbk": _snap("fir.b.btbk", bkp=str(EPOCH), diskid="svc", img=f"one-sys-4-SVC-{EPOCH}"),
        }
        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging" not in out

    def test_left_behind(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 3}}
        processor.sp.data = {
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", img="one-img-3-4-0"),
        }
        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging snapshot ~fir.b.btbe" in out
        assert f"backup snapshot (bkp={EPOCH}) in no backup image SOURCE" in out
        assert "VM 4 is not in BACKUP" in out
        assert "SnapshotUnexport ~fir.b.btbe all force" in out

    def test_in_progress(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 69}}
        processor.sp.data = {
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", img="one-img-3-4-0"),
        }
        processor.analyze_hanging()
        assert "hanging" not in capsys.readouterr().out

    def test_vm_gone(self, processor, capsys):
        processor.sp.data = {
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", img="one-img-3-4-0"),
        }
        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging snapshot ~fir.b.btbe" in out
        assert "VM 4 is gone" in out

    def test_stuck_transient_export(self, processor, capsys):
        """The transient of a VolumesGroupBackup (transient + autoName) left
        by a failed postbackup is reported like a kept snapshot"""
        processor.one.one_vms = {4: {"lcm_state": 3}}
        processor.sp.data = {
            "~fir.b.btn9": _snap("fir.b.btn9", bkp=str(EPOCH), transient=True, autoName=True),
        }
        processor.sp.data["~fir.b.btn9"]["transient"] = True
        processor.sp.data["~fir.b.btn9"]["autoName"] = True
        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging snapshot ~fir.b.btn9" in out
        assert f"backup transient (bkp={EPOCH}) in no backup image SOURCE" in out

    def test_transient_export_in_progress(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 69}}
        processor.sp.data = {"~fir.b.btn9": _snap("fir.b.btn9", bkp=str(EPOCH))}
        processor.sp.data["~fir.b.btn9"]["transient"] = True
        processor.sp.data["~fir.b.btn9"]["autoName"] = True
        processor.analyze_hanging()
        assert "hanging" not in capsys.readouterr().out

    def test_foreign_instance(self, processor, capsys):
        processor.sp.data = {
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", nloc="other"),
        }
        processor.analyze_hanging()
        assert "hanging" not in capsys.readouterr().out


class TestKeptBackupNotADuplicate:

    def test_kept_snapshot_does_not_claim_the_live_disk(self, processor, capsys):
        """A kept backup snapshot carries the img tag of the live disk;
        it is not a second claimant of that OpenNebula record"""
        processor.one.backup_images = {8: _backup_image()}
        processor.one.vm_disks = {
            "one-img-3-4-0": {
                "vm_id": 4, "disk_id": 0, "spname": "one-img-3-4-0",
                "img": "one-img-3-4-0", "legacy": "one-img-3-4-0",
                "snapshot": False, "state": 3, "lcm_state": 3,
            }
        }
        processor.etcd.data["byName"] = {"one-img-3-4-0": "~fir.b.btbi"}
        processor.etcd.data["byUid"] = {"~fir.b.btbi": "one-img-3-4-0"}
        live = _snap("fir.b.btbi", diskid="0", img="one-img-3-4-0")
        live["snapshot"] = False
        processor.sp.data = {
            "~fir.b.btbi": live,
            "~fir.b.btbe": _snap("fir.b.btbe", bkp=str(EPOCH), diskid="0", img="one-img-3-4-0"),
        }
        processor.analyze_duplicates()
        out = capsys.readouterr().out
        assert "claim OpenNebula" not in out
        assert "leftover" not in out


class TestServiceVolume:

    def test_left_behind(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 3}}
        vol = _snap("fir.b.btbg", type="SVC", img=f"one-sys-4-SVC-{EPOCH}")
        vol["snapshot"] = False
        processor.sp.data = {"~fir.b.btbg": vol}
        processor.analyze_hanging()
        out = capsys.readouterr().out
        assert "hanging volume ~fir.b.btbg" in out
        assert "service volume of a backup left behind" in out

    def test_in_progress(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 70}}
        vol = _snap("fir.b.btbg", type="SVC", img=f"one-sys-4-SVC-{EPOCH}")
        vol["snapshot"] = False
        processor.sp.data = {"~fir.b.btbg": vol}
        processor.analyze_hanging()
        assert "hanging" not in capsys.readouterr().out


class TestBackupKv:

    def test_reachable_family(self, processor, capsys):
        processor.one.backup_images = {8: _backup_image()}
        processor.etcd.data["bkName"] = {
            f"one-bak-4-{EPOCH}": "mode=local svc=~fir.b.btbg",
            f"one-bak-4-{EPOCH}-0": "~fir.b.btbe",
            f"one-bak-4-{EPOCH}-nvram": "~fir.b.btbj",
            f"one-bak-4-{EPOCH}-svc": "~fir.b.btbk",
        }
        processor.analyze_backup_kv()
        assert "[Issue]" not in capsys.readouterr().out

    def test_mismatch(self, processor, capsys):
        processor.one.backup_images = {8: _backup_image()}
        processor.etcd.data["bkName"] = {
            f"one-bak-4-{EPOCH}": "mode=local svc=-",
            f"one-bak-4-{EPOCH}-0": "~fir.b.other",
            f"one-bak-4-{EPOCH}-1": "~fir.b.extra",
        }
        processor.analyze_backup_kv()
        out = capsys.readouterr().out
        assert f"/bkName/one-bak-4-{EPOCH}-0 = ~fir.b.other differs" in out
        assert f"/bkName/one-bak-4-{EPOCH}-1 = ~fir.b.extra has no entry" in out

    def test_stale_local_family(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 3}}
        processor.etcd.data["bkName"] = {
            f"one-bak-4-{EPOCH}": "mode=local svc=- loc=-",
            f"one-bak-4-{EPOCH}-0": "~fir.b.btbe",
        }
        processor.analyze_backup_kv()
        out = capsys.readouterr().out
        assert f"stale backup KV records /bkName/one-bak-4-{EPOCH}* (2)" in out
        assert f"# ETCDCTL_API=3 etcdctl del --prefix /bkName/one-bak-4-{EPOCH}" in out

    def test_stale_remote_family_keeps_the_pointer(self, processor, capsys):
        """The records of a remote epoch name the copies on the target:
        the advice is to remove the copies first"""
        processor.one.one_vms = {4: {"lcm_state": 3}}
        processor.etcd.data["bkName"] = {
            f"one-bak-4-{EPOCH}": "mode=remote svc=- loc=devA1-cl2",
            f"one-bak-4-{EPOCH}-0": "~fir.b.btbe",
            f"one-bak-4-{EPOCH}-svc": "~fir.b.btbk",
        }
        processor.analyze_backup_kv()
        out = capsys.readouterr().out
        assert "may remain on the target devA1-cl2" in out
        assert "0=~fir.b.btbe svc=~fir.b.btbk" in out
        assert "remove the copies on devA1-cl2 first" in out

    def test_in_progress_family(self, processor, capsys):
        processor.one.one_vms = {4: {"lcm_state": 69}}
        processor.etcd.data["bkName"] = {
            f"one-bak-4-{EPOCH}": "mode=remote svc=~fir.b.btbg",
            f"one-bak-4-{EPOCH}-0": "~fir.b.btbe",
        }
        processor.analyze_backup_kv()
        assert "[Issue]" not in capsys.readouterr().out

    def test_odd_key(self, processor, capsys):
        processor.etcd.data["bkName"] = {"one-bak-x": "y"}
        processor.analyze_backup_kv()
        assert "does not match one-bak-<vm>-<epoch>[-<did>]" in capsys.readouterr().out
