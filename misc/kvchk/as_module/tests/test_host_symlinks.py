import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.enums import DiskType  # type: ignore[import-untyped] # noqa: E501


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
    return args


@pytest.fixture
def processor(mock_args):
    """Setup with basic managers for host symlink testing"""
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

    # Initialize empty data structures for testing
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


def _sp_vol(name="~fir.b.jm", gid="fir.b.jm", **overrides):
    """The StorPool volume backing the migrated VM disk"""
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
    """A migrated running VM disk with a stale legacy symlink"""
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
        "target": "/dev/storpool/one-sys-26-1-raw",
    }
    data.update(overrides)
    return data


class TestHostSymlinks:
    """Test detection of stale/missing disk.N symlinks on the hosts"""

    def test_stale_legacy_symlink(self, processor, capsys):
        """A migrated volume (in KV) with the disk.N symlink still
        pointing to the legacy /dev/storpool/<name> device is reported
        and a fix is queued."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "stale legacy symlink" in out
        assert (
            "ssh kvm1 ln -vsfn /dev/storpool-byid/fir.b.jm"
            " /var/lib/one/datastores/0/26/disk.1"
        ) in out
        # a fix action is queued for --execute
        assert "one-sys-26-1" in processor.update_data
        entry = processor.update_data["one-sys-26-1"]
        assert "symlink" in entry["action"]
        assert entry["data"]["uid"] == "fir.b.jm"
        assert entry["data"]["symlink"] == {
            "host": "kvm1",
            "target": "/dev/storpool-byid/_SP_UID_",
            "link": "/var/lib/one/datastores/0/26/disk.1",
            "vm_id": 26,
        }

    def test_correct_symlink_is_silent(self, processor, capsys):
        """A disk.N symlink already pointing to the globalId device
        is not reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_missing_symlink(self, processor, capsys):
        """A running VM disk without a symlink on the host is reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk(target=None)}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "missing symlink" in out
        assert "symlink" in processor.update_data["one-sys-26-1"]["action"]

    def test_no_links_collected_is_silent(self, processor, capsys):
        """When the host symlinks could not be collected (ssh failure)
        the missing target is not reported as an issue."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk(target=None)}
        processor.one.one_hosts = {"kvm1": {}}  # no "links" key
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_poweroff_vm_is_queued_too(self, processor, capsys):
        """A stale symlink of a VM in POWEROFF is reported with a
        suggested fix command and a symlink action is queued."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=8, lcm_state=0)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "stale legacy symlink" in out
        assert "ln -vsfn /dev/storpool-byid/fir.b.jm" in out
        assert "symlink" in processor.update_data["one-sys-26-1"]["action"]

    def test_stopped_vm_is_not_queued(self, processor, capsys):
        """A stale symlink of a VM in STOPPED state is reported but
        no symlink action is queued."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=4, lcm_state=0)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "one-sys-26-1" not in processor.update_data

    def test_globalid_from_kv_legacy_name(self, processor, capsys):
        """An old migration wrote the legacy name into KV byName;
        the globalId is still resolved."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {"one-sys-26-1-raw": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1-raw"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "ln -vsfn /dev/storpool-byid/fir.b.jm" in out
        assert "symlink" in processor.update_data["one-sys-26-1"]["action"]

    def test_globalid_from_kv_byuid_only(self, processor, capsys):
        """The byName entry is lost but byUid still maps the uid to
        the volume name; the globalId is resolved from byUid."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {"~fir.b.jm": _sp_vol()}
        processor.etcd.data = {
            "byName": {},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "ln -vsfn /dev/storpool-byid/fir.b.jm" in out
        assert "symlink" in processor.update_data["one-sys-26-1"]["action"]

    def test_globalid_from_storpool_tags(self, processor, capsys):
        """The volume is renamed to ~globalId and the KV entries are
        lost; the globalId is resolved by the StorPool tags."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {
            "~fir.b.jm": {
                "globalId": "fir.b.jm",
                "name": "~fir.b.jm",
                "tags": {
                    "virt": "one",
                    "nloc": "one",
                    "nvm": "26",
                    "diskid": "1",
                    "img": "one-sys-26-1",
                },
                "snapshot": False,
                "sp_api_http_host": "localhost",
            },
            "~fir.b.zz": {
                "globalId": "fir.b.zz",
                "name": "~fir.b.zz",
                "tags": {
                    "virt": "one",
                    "nloc": "one",
                    "nvm": "26",
                    "diskid": "1",
                    "img": "one-sys-26-1",
                    "snap": "snap0",
                },
                "snapshot": True,
                "sp_api_http_host": "localhost",
            },
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        # the volume is matched, not its snapshot
        assert "ln -vsfn /dev/storpool-byid/fir.b.jm" in out
        assert "fir.b.zz" not in out

    def test_unresolvable_stale_symlink_is_reported(
        self, processor, capsys
    ):
        """A stale old-format symlink whose globalId cannot be resolved
        from KV or StorPool is still reported as an issue."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "stale legacy symlink" in out
        assert "no globalId found in KV/StorPool" in out
        # nothing can be queued without a globalId
        assert processor.update_data == {}

    def test_globalid_from_storpool_legacy_name(self, processor, capsys):
        """When the volume is not in KV yet, the globalId is resolved
        from the StorPool data by the legacy name."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {
            "one-sys-26-1-raw": {
                "globalId": "fir.b.jm",
                "name": "one-sys-26-1-raw",
                "tags": {},
                "snapshot": False,
                "sp_api_http_host": "localhost",
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "ln -vsfn /dev/storpool-byid/fir.b.jm" in out

    def test_orphan_symlink(self, processor, capsys):
        """A StorPool symlink on a host not matching any known VM disk
        is reported as an orphan artefact."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {99: {"disk.0": "/dev/storpool/one-sys-99-0-raw"}}
                }
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "orphan symlink on kvm1" in out
        assert "(VM 99 not in ONE)" in out
        assert (
            "# ssh kvm1 rm -v /var/lib/one/datastores/0/99/disk.0"
        ) in out
        # orphans are report-only, nothing is queued
        assert processor.update_data == {}

    def test_migration_queues_symlink_for_poweroff_vm(self, processor):
        """Migrating a legacy volume of a VM in POWEROFF queues the
        symlink fix too (used to be skipped, leaving stale symlinks)."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=8, lcm_state=0)
        }
        processor.sp.data = {
            "one-sys-26-1-raw": {
                "globalId": "fir.b.jm",
                "name": "one-sys-26-1-raw",
                "tags": {},
                "snapshot": False,
                "sp_api_http_host": "localhost",
            }
        }

        processor.analyze_storpool()

        entry = processor.update_data["one-sys-26-1"]
        assert "symlink" in entry["action"]
        assert entry["data"]["symlink"] == {
            "host": "kvm1",
            "target": "/dev/storpool-byid/_SP_UID_",
            "link": "/var/lib/one/datastores/0/26/disk.1",
            "vm_id": 26,
        }

    def test_migration_skips_symlink_for_undeployed_vm(self, processor):
        """Migrating a legacy volume of an UNDEPLOYED VM does not queue
        a symlink fix (the datastore dir is not on the host)."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.sp.data = {
            "one-sys-26-1-raw": {
                "globalId": "fir.b.jm",
                "name": "one-sys-26-1-raw",
                "tags": {},
                "snapshot": False,
                "sp_api_http_host": "localhost",
            }
        }

        processor.analyze_storpool()

        entry = processor.update_data["one-sys-26-1"]
        assert "symlink" not in entry["action"]

    def test_untagged_renamed_volume_is_still_reported(
        self, processor, capsys
    ):
        """A volume migrated by a very old tool version: renamed to
        ~globalId, no KV entries and no tags. No resolution tier can
        find it, but the stale symlink is still reported as an issue
        (nothing is queued)."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=8, lcm_state=0)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        # KV lost, volume renamed and carries no tags at all
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.sp.data = {
            "~fir.b.jm": {
                "globalId": "fir.b.jm",
                "name": "~fir.b.jm",
                "tags": {},
                "snapshot": False,
                "sp_api_http_host": "localhost",
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "stale legacy symlink" in out
        assert "no globalId found in KV/StorPool" in out
        assert processor.update_data == {}

    def test_foreign_tags_are_not_matched(self, processor, capsys):
        """Renamed volumes tagged for another virt/location or for a
        different VM/disk must not be matched by the tag tier - the
        stale symlink is reported as unresolvable instead of being
        'fixed' to the wrong globalId."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=8, lcm_state=0)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.etcd.data = {"byName": {}, "byUid": {}}
        processor.sp.data = {
            # not managed by the addon
            "~aaa.b.aa": {
                "globalId": "aaa.b.aa",
                "name": "~aaa.b.aa",
                "tags": {"nvm": "26", "diskid": "1"},  # no virt=one
                "snapshot": False,
                "sp_api_http_host": "localhost",
            },
            # other ONE instance (different nloc prefix)
            "~bbb.b.bb": {
                "globalId": "bbb.b.bb",
                "name": "~bbb.b.bb",
                "tags": {
                    "virt": "one",
                    "nloc": "two",
                    "nvm": "26",
                    "diskid": "1",
                    "img": "two-sys-26-1",
                },
                "snapshot": False,
                "sp_api_http_host": "localhost",
            },
            # same location but different VM/disk
            "~ccc.b.cc": {
                "globalId": "ccc.b.cc",
                "name": "~ccc.b.cc",
                "tags": {
                    "virt": "one",
                    "nloc": "one",
                    "nvm": "27",
                    "diskid": "1",
                    "img": "one-sys-27-1",
                },
                "snapshot": False,
                "sp_api_http_host": "localhost",
            },
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "no globalId found in KV/StorPool" in out
        assert "aaa.b.aa" not in out
        assert "bbb.b.bb" not in out
        assert "ccc.b.cc" not in out
        assert processor.update_data == {}

    def test_unresolvable_with_orphan_leftovers(self, processor, capsys):
        """The combined production picture: a poweroff VM with an
        unresolvable stale symlink plus leftover symlinks of a VM that
        is no longer in ONE - both are reported in the same run."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=8, lcm_state=0)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {
                        26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"},
                        99: {"disk.0": "/dev/storpool/one-sys-99-0-raw"},
                    }
                }
            }
        }
        processor.etcd.data = {"byName": {}, "byUid": {}}

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "no globalId found in KV/StorPool" in out
        assert "orphan symlink on kvm1" in out
        assert "(VM 99 not in ONE)" in out
        assert (
            "# ssh kvm1 rm -v /var/lib/one/datastores/0/99/disk.0"
        ) in out
        assert processor.update_data == {}

    def test_non_storpool_symlink_ignored(self, processor, capsys):
        """Symlinks not pointing to StorPool devices are ignored."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {99: {"disk.0": "/some/other/path"}}
                }
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out

    def test_reverted_volume_symlink_on_preserved_id_silent(
        self, processor, capsys
    ):
        """After VolumeRevert the canonical globalId drifts but the KV
        and the disk.N symlink keep the preserved (original) id - that
        is the stable state, not an issue."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.sp.data = {
            "~fir.b.jm": _sp_vol(
                gid="fir.b.xx", preservedGlobalId="fir.b.jm"
            )
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_dead_kv_id_never_gets_a_symlink_fix(self, processor, capsys):
        """A KV entry keeping an id StorPool no longer resolves (an
        intermediate id of a reverted volume) must not produce an
        ln to the dead /dev/storpool-byid path."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {"one-sys-26-1": _vm_disk()}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool/one-sys-26-1-raw"}}
                }
            }
        }
        processor.sp.data = {
            "~fir.b.jm": _sp_vol(
                gid="fir.b.xx", preservedGlobalId="fir.b.jm"
            )
        }
        # the dead intermediate id fir.b.yt from an old migration
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.yt"},
            "byUid": {"~fir.b.yt": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "ln -vsfn /dev/storpool-byid/fir.b.yt" not in out
        assert "symlink" not in processor.update_data.get(
            "one-sys-26-1", {"action": []}
        )["action"]


class TestHostLeftovers:
    """Check the symlinks collected from the hosts against the
    OpenNebula data - left-over artefacts on hosts where the VM
    is not expected to be running"""

    def test_leftover_on_unexpected_host(self, processor, capsys):
        """Artefacts of a VM found on a host where the VM is not
        expected to be running (e.g. after a failed/live migration)
        are reported with the expected host."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            },
            "kvm2": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            },
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "orphan symlink on kvm2" in out
        assert "(VM 26 expected on host kvm1)" in out
        assert (
            "# ssh kvm2 rm -v /var/lib/one/datastores/0/26/disk.1"
        ) in out
        # the symlink on the expected host is not reported
        assert "orphan symlink on kvm1" not in out
        # leftovers are report-only, nothing is queued
        assert processor.update_data == {}

    def test_leftover_of_undeployed_vm(self, processor, capsys):
        """Artefacts of an UNDEPLOYED VM left on its last host are
        reported - the VM files are expected on the frontend."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "orphan symlink on kvm1" in out
        assert "(VM 26 state 9, expected on the frontend)" in out
        assert (
            "# ssh kvm1 rm -v /var/lib/one/datastores/0/26/disk.1"
        ) in out
        assert processor.update_data == {}

    def test_suspended_vm_is_expected_on_host(self, processor, capsys):
        """A SUSPENDED VM keeps its files on the host - its symlinks
        there are not left-overs."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                state=5,
                lcm_state=0,
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_leftover_in_other_datastore(self, processor, capsys):
        """Symlinks of a VM under a system datastore different from
        the one the VM is deployed in are reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}},
                    102: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}},
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "(VM 26 expected in datastore 0)" in out
        assert (
            "# ssh kvm1 rm -v /var/lib/one/datastores/102/26/disk.1"
        ) in out
        assert processor.update_data == {}

    def test_extra_disk_symlink_on_expected_host(self, processor, capsys):
        """A disk.N symlink on the expected host that is not a disk
        of the VM (e.g. a detached disk) is reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {
                        26: {
                            "disk.1": "/dev/storpool-byid/fir.b.jm",
                            "disk.2": "/dev/storpool-byid/fir.b.zz",
                        }
                    }
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "disk.2 -> /dev/storpool-byid/fir.b.zz" in out
        assert "(not a disk of VM 26)" in out
        # only the extra disk is reported
        assert out.count("[Issue]") == 1
        assert processor.update_data == {}

    def test_disk_snapshot_symlink_is_not_reported(
        self, processor, capsys
    ):
        """A disk.N.snapM symlink of a VM deployed on the host could
        be legitimate (disk snapshot) and is not reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {
                        26: {
                            "disk.1": "/dev/storpool-byid/fir.b.jm",
                            "disk.1.snap0":
                                "/dev/storpool-byid/fir.b.zz",
                        }
                    }
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    @pytest.mark.parametrize("state", [4])
    def test_undeployed_vm_artefacts_on_frontend_are_expected(
        self, processor, capsys, state
    ):
        """The files of a STOPPED VM live on the frontend - its
        symlinks there are not left-overs. (An UNDEPLOYED VM's
        symlinks are dangling and handled separately.)"""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=state, lcm_state=0, target=None)
        }
        processor.one.frontend = {
            "name": "fe1",
            "links": {
                0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
            },
        }
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_running_vm_artefacts_on_frontend(self, processor, capsys):
        """A VM running on a host with left-over artefacts on the
        frontend is reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(
                target="/dev/storpool-byid/fir.b.jm",
            )
        }
        processor.one.frontend = {
            "name": "fe1",
            "links": {
                0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
            },
        }
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "orphan symlink on the frontend fe1" in out
        assert (
            "(VM 26 expected on host kvm1, not on the frontend)"
        ) in out
        # the frontend clean-up is local, no ssh
        assert (
            "# rm -v /var/lib/one/datastores/0/26/disk.1"
        ) in out
        assert "# ssh fe1" not in out
        assert processor.update_data == {}

    def test_deleted_vm_artefacts_on_frontend(self, processor, capsys):
        """Left-over artefacts on the frontend of a VM that is no
        longer in ONE are reported."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {}
        processor.one.frontend = {
            "name": "fe1",
            "links": {
                0: {99: {"disk.0": "/dev/storpool/one-sys-99-0-raw"}}
            },
        }
        processor.one.one_hosts = {"kvm1": {"links": {}}}

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "orphan symlink on the frontend fe1" in out
        assert "(VM 99 not in ONE)" in out
        assert (
            "# rm -v /var/lib/one/datastores/0/99/disk.0"
        ) in out
        assert processor.update_data == {}

    def test_undeployed_dangling_symlink_on_hypervisor_frontend(
        self, processor, capsys
    ):
        """When the frontend is also a hypervisor host, the dangling
        disk symlink of an UNDEPLOYED VM there is reported with an ssh
        removal command (the volume is detached, re-created on resume)."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.one.frontend = {"name": "kvm1"}
        processor.one.one_hosts = {
            "kvm1": {
                "links": {
                    0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}
                }
            }
        }
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "undeployed: dangling symlink" in out
        assert (
            "# ssh kvm1 rm -v /var/lib/one/datastores/0/26/disk.1"
        ) in out
        # a removal is queued for --execute, over ssh to the frontend host
        assert processor.update_data == {
            "one-sys-26-1": {
                "data": {
                    "unlink": {
                        "link": "/var/lib/one/datastores/0/26/disk.1",
                        "host": "kvm1",
                    }
                },
                "action": ["unlink"],
            }
        }

    def test_missing_frontend_data_is_reported(self, processor, capsys):
        """A STOPPED VM without its disk symlinks on the frontend is
        reported when the VM home move is not disabled."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=4, lcm_state=0, target=None)
        }
        # frontend collected, no data for the VM
        processor.one.frontend = {"name": "fe1", "links": {}}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert (
            "missing /var/lib/one/datastores/0/26/disk.1"
            " on the frontend"
        ) in out
        assert processor.update_data == {}

    def test_undeployed_dangling_symlink_removed(self, processor, capsys):
        """An UNDEPLOYED VM with a StorPool disk symlink left on the
        frontend is reported as dangling with a local rm command."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.one.frontend = {
            "name": "fe1",
            "links": {0: {26: {"disk.1": "/dev/storpool-byid/fir.b.jm"}}},
        }
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "undeployed: dangling symlink" in out
        assert "# rm -v /var/lib/one/datastores/0/26/disk.1" in out
        # not an ssh removal - the frontend is the local node
        assert "ssh fe1 rm" not in out
        # a local removal is queued for --execute (host is None)
        assert processor.update_data == {
            "one-sys-26-1": {
                "data": {
                    "unlink": {
                        "link": "/var/lib/one/datastores/0/26/disk.1",
                        "host": None,
                    }
                },
                "action": ["unlink"],
            }
        }

    def test_undeployed_no_symlink_no_issue(self, processor, capsys):
        """An UNDEPLOYED VM with no disk symlink on the frontend is not
        reported - there is nothing to remove and the addon re-creates
        it on resume."""
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.one.frontend = {"name": "fe1", "links": {}}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_missing_frontend_data_skip_undeploy_ssh(
        self, processor, capsys
    ):
        """With SKIP_UNDEPLOY_SSH enabled the VM home is not moved to
        the frontend on stop/undeploy - the missing VM data on the
        frontend is not reported."""
        processor.args.skip_undeploy_ssh = True
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=9, lcm_state=0, target=None)
        }
        processor.one.frontend = {"name": "fe1", "links": {}}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_missing_frontend_data_storpool_only_vm(
        self, processor, capsys
    ):
        """With SP_CHECKPOINT_BD set, tm/mv auto-enables the skip
        for a VM with all disks on StorPool TMs - the missing VM
        data on the frontend is not reported."""
        processor.args.sp_checkpoint_bd = True
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=4, lcm_state=0, target=None)
        }
        processor.one.one_vms = {
            26: {
                "vm_id": 26,
                "state": 4,
                "lcm_state": 0,
                "host": "kvm1",
                "ds_id": 0,
                "disk_tm_mads": ["storpool", "storpool_xfer"],
            }
        }
        processor.one.frontend = {"name": "fe1", "links": {}}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" not in out
        assert processor.update_data == {}

    def test_missing_frontend_data_mixed_tm_mads(
        self, processor, capsys
    ):
        """SP_CHECKPOINT_BD does not auto-enable the skip for a VM
        with a non-StorPool disk - the missing VM data on the
        frontend is still reported."""
        processor.args.sp_checkpoint_bd = True
        processor.one.vm_ids = [26]
        processor.one.vm_disks = {
            "one-sys-26-1": _vm_disk(state=4, lcm_state=0, target=None)
        }
        processor.one.one_vms = {
            26: {
                "vm_id": 26,
                "state": 4,
                "lcm_state": 0,
                "host": "kvm1",
                "ds_id": 0,
                # a missing TM_MAD is an empty entry, non-StorPool
                "disk_tm_mads": ["storpool", ""],
            }
        }
        processor.one.frontend = {"name": "fe1", "links": {}}
        processor.one.one_hosts = {"kvm1": {"links": {}}}
        processor.etcd.data = {
            "byName": {"one-sys-26-1": "~fir.b.jm"},
            "byUid": {"~fir.b.jm": "one-sys-26-1"},
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert (
            "missing /var/lib/one/datastores/0/26/disk.1"
            " on the frontend"
        ) in out

    def test_placement_from_one_vms(self, processor, capsys):
        """The expected placement of a VM without StorPool disks in
        vm_disks is taken from the collected VM pool data."""
        processor.one.vm_ids = [30]
        processor.one.vm_disks = {}
        processor.one.one_vms = {
            30: {
                "vm_id": 30,
                "name": "vm30",
                "state": 3,
                "lcm_state": 3,
                "host": "kvm1",
                "ds_id": 0,
            }
        }
        processor.one.one_hosts = {
            "kvm2": {
                "links": {
                    0: {30: {"disk.0": "/dev/storpool-byid/fir.b.aa"}}
                }
            }
        }

        processor.analyze_host_symlinks()

        out = capsys.readouterr().out
        assert "orphan symlink on kvm2" in out
        assert "(VM 30 expected on host kvm1)" in out
        assert processor.update_data == {}
