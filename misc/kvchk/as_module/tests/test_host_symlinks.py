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
        reported - the VM is not expected on any host."""
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
        assert "(VM 26 state 9, not expected on any host)" in out
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
