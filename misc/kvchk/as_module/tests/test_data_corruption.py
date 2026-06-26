import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.enums import DiskType, ImageType  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.exceptions import UnhandledCase  # type: ignore[import-untyped] # noqa: E501


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
def corrupted_setup(mock_args):
    """Setup with basic managers for corruption testing"""
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

    # spManager is multisite aware; with an empty datastore_config no real
    # StorPool Api is created. SPConfig is still instantiated, so patch it.
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


class TestEtcdCorruption:
    """Test scenarios with corrupted etcd data"""

    def test_orphaned_byname_entries(self, corrupted_setup):
        """Test handling of byName entries without corresponding
        byUid entries
        """
        processor = corrupted_setup

        # Set up corrupted etcd data
        processor.etcd.data = {
            "byName": {
                "one-img-456": "~123",  # Points to non-existent UID
                "one-img-789": "~456"   # Another orphaned entry
            },
            "byUid": {}  # Empty byUid
        }

        # Set up corresponding StorPool data
        processor.sp.data = {
            "~123": {
                "globalId": "123",
                "name": "one-img-456",
                "tags": {"type": "PERS"},
                "snapshot": False
            }
        }

        # Run analysis
        processor.analyze_kv_by_name()

        # Verify that update was triggered to fix orphaned entries
        assert "one-img-456" in processor.update_data
        assert "kv" in processor.update_data["one-img-456"]["action"]
        assert processor.update_data["one-img-456"]["data"]["uid"] == "~123"

    @pytest.mark.skip(
        reason="Forward/reverse KV mismatch detection not yet implemented"
    )
    def test_mismatched_kv_entries(self, corrupted_setup):
        """Test handling of mismatched byName and byUid entries

        TODO: Implement detection of mismatches where byName[name] -> uid
        but byUid[uid] -> different_name. This indicates a forward/reverse
        lookup inconsistency that should be detected and fixed.
        """
        processor = corrupted_setup

        # Set up corrupted data
        # where byName and byUid point to different names
        processor.etcd.data = {
            "byName": {
                "one-img-456": "~123"
            },
            "byUid": {
                "~123": "one-img-789"  # Mismatch!
            }
        }

        # Run analysis
        processor.analyze_kv_by_name()

        # Verify that update was triggered to fix mismatch
        assert "one-img-456" in processor.update_data
        assert "kv" in processor.update_data["one-img-456"]["action"]

    def test_duplicate_uid_references(self, corrupted_setup, capsys):
        """Test handling of multiple byName entries pointing to same UID

        byName has two names mapping to the same UID, while byUid only
        references one of them. The analyzer reports the stale duplicate
        with an `etcdctl del` remediation hint rather than queueing an
        update.
        """
        processor = corrupted_setup

        # Set up corrupted data where multiple names point to same UID
        processor.etcd.data = {
            "byName": {
                "one-img-456": "~123",
                "one-img-789": "~123"  # Duplicate reference to ~123
            },
            "byUid": {
                "~123": "one-img-456"
            }
        }

        # Run analysis
        processor.analyze_kv_by_name()

        # The duplicate byName entry is reported for manual cleanup and no
        # spurious update record is created.
        out = capsys.readouterr().out
        assert "etcdctl del /byName/one-img-789" in out
        assert "one-img-789" not in processor.update_data


class TestStorPoolCorruption:
    """Test scenarios with corrupted StorPool data"""

    def test_invalid_volume_tags(self, corrupted_setup):
        """Test handling of StorPool volumes with invalid tags"""
        processor = corrupted_setup

        # Set up StorPool data with invalid tags
        processor.sp.data = {
            "one-img-456": {
                "globalId": "123",
                "name": "one-img-456",
                "tags": {
                    "type": "INVALID_TYPE",  # Invalid type
                    "nvm": "abc",  # Should be numeric
                    "diskid": "not_a_number"  # Should be numeric
                },
                "snapshot": False,
                "sp_api_http_host": "localhost"
            }
        }

        # Set up corresponding ONE data
        processor.one.vm_disks = {
            "one-img-456": {
                "vm_id": 123,
                "disk_id": 0,
                "disktype": DiskType.PERSISTENT,
                "legacy": "one-img-456",
                "snapshot": False,
                "spname": "one-img-456",
                "name": "a persistent image: one-img-456"
            }
        }

        # Run analysis
        processor.analyze_storpool()

        # Verify that update was triggered to fix tags
        assert "one-img-456" in processor.update_data
        assert "Update" in processor.update_data["one-img-456"]["action"]
        assert "tags" in processor.update_data["one-img-456"]["data"]

    def test_snapshot_volume_mismatch(self, corrupted_setup, capsys):
        """Test handling of StorPool entries with wrong snapshot status

        A StorPool entry exists but is missing from the KV byName mapping.
        `analyze_one_images` flags it as an issue marked for migration.
        """
        processor = corrupted_setup

        # Set up StorPool data with wrong snapshot status
        processor.sp.data = {
            "one-img-456": {
                "globalId": "123",
                "name": "one-img-456",
                "tags": {"type": "PERS"},
                "snapshot": True,  # Should be False for this type
                "sp_api_http_host": "localhost"
            }
        }

        # Set up corresponding ONE data
        processor.one.ds_images = {
            "one-img-456": {
                "image_id": 456,
                "disktype": DiskType.PERSISTENT,
                "name": "a persistent image: one-img-456",
                "imagetype": ImageType.OS,
                "vms": 0,
                "snapshot": False,
                "snapshots": {}
            }
        }

        # Run analysis
        processor.analyze_one_images()

        # The image is reported as an issue and flagged for migration.
        out = capsys.readouterr().out
        assert "[Issue]" in out
        assert "one-img-456" in out
        assert "<TO_MIGRATE>" in out


class TestOpenNebulaCorruption:
    """Test scenarios with corrupted OpenNebula data"""

    def test_invalid_disk_references(self, corrupted_setup):
        """Test handling of a byUid entry resolvable in ONE but absent
        in StorPool.

        `analyze_kv_by_uid` finds the name in OpenNebula (by legacy lookup)
        but the corresponding volume is missing from StorPool, which is an
        unhandled inconsistency and must raise `UnhandledCase`.
        """
        processor = corrupted_setup

        # byUid references a name that exists in ONE but not in StorPool
        processor.etcd.data = {
            "byName": {},
            "byUid": {"~999": "one-img-456"}
        }

        # ONE knows about the disk ...
        processor.one.vm_disks = {
            "one-img-456": {
                "vm_id": 123,
                "disk_id": 0,
                "image_id": None,
                "disktype": DiskType.PERSISTENT,
                "legacy": "one-img-456",
                "spname": "one-img-456"
            }
        }

        # ... but StorPool does not (sp.data is empty)
        processor.sp.data = {}

        # Run analysis
        with pytest.raises(UnhandledCase):
            processor.analyze_kv_by_uid()

    def test_inconsistent_snapshot_data(self, corrupted_setup, capsys):
        """Test handling of an image snapshot that is missing from KV and
        StorPool.

        `analyze_one_images` walks the image snapshots and reports the
        orphaned snapshot as not present in KV / not found in StorPool.
        """
        processor = corrupted_setup
        # raise verbosity so the per-snapshot debug output is emitted
        processor.args.verbose = 2

        # Set up ONE data with a snapshot absent from KV and StorPool
        processor.one.ds_images = {
            "one-img-456": {
                "image_id": 456,
                "disktype": DiskType.PERSISTENT,
                "imagetype": ImageType.OS,
                "name": "a persistent image: one-img-456",
                "vms": 0,
                "snapshot": False,
                "snapshots": {
                    "one-snap-456-0": {
                        "snap": "0",
                        "snapshot": False  # Inconsistent - should be True
                    }
                }
            }
        }

        # Run analysis
        processor.analyze_one_images()

        # The orphaned snapshot is reported but no update record is created
        # (snapshot remediation is not auto-queued from this path).
        out = capsys.readouterr().out
        assert "one-snap-456-0" in out
        assert "not in KV" in out
        assert "one-snap-456-0" not in processor.update_data


@pytest.mark.skip(
    reason="Cross-component name inconsistency detection not yet implemented"
)
def test_cross_component_corruption(corrupted_setup):
    """Test handling of corruption across multiple components

    TODO: Implement detection of inconsistencies where spname doesn't match
    the volume key name. The test sets up a scenario where the volume is
    keyed as "one-img-456" but has spname="different-name", which should
    be detected and marked for cleanup.
    """
    processor = corrupted_setup

    # Set up inconsistent data across components
    processor.etcd.data = {
        "byName": {"one-img-456": "~123"},
        "byUid": {"~123": "one-img-456"}
    }

    processor.sp.data = {
        "~123": {
            "globalId": "123",
            "name": "one-img-456",
            "tags": {"type": "PERS"},
            "snapshot": False
        }
    }

    processor.one.vm_disks = {
        "one-img-456": {
            "vm_id": 123,
            "disk_id": 0,
            "image_id": 789,  # Inconsistent with StorPool data
            "disktype": DiskType.PERSISTENT,
            "spname": "different-name"  # Inconsistent name
        }
    }

    # Run full analysis
    processor.analyze_kv_by_name()
    processor.analyze_kv_by_uid()
    processor.analyze_vm_disks()

    # Verify that updates were triggered to fix inconsistencies
    assert "one-img-456" in processor.update_data
    assert len(processor.update_data["one-img-456"]["action"]) > 0


@pytest.mark.skip(reason="Malformed data detection not yet implemented")
@pytest.mark.parametrize("corrupt_data", [
    {
        "name": "invalid_utf8_in_etcd",
        "etcd_data": {
            "byName": {"one-img-456": b"~123\xff\xff"},  # Invalid UTF-8
            "byUid": {"~123": "one-img-456"}
        }
    },
    {
        "name": "null_bytes_in_names",
        "etcd_data": {
            "byName": {"one-img-456\x00": "~123"},  # Null bytes in name
            "byUid": {"~123": "one-img-456"}
        }
    },
    {
        "name": "control_chars_in_tags",
        "sp_data": {
            "one-img-456": {
                "tags": {"type": "PERS\n\r\t"}  # Control characters in tags
            }
        }
    }
])
def test_malformed_data(corrupted_setup, corrupt_data):
    """Test handling of malformed data

    TODO: Implement malformed data detection in DataProcessing
    - Invalid UTF-8 sequences should be detected and cleaned up
    - Null bytes in names should be detected and cleaned up
    - Control characters in tags should be detected and cleaned up
    """
    processor = corrupted_setup

    # Apply corrupted data
    if "etcd_data" in corrupt_data:
        processor.etcd.data = corrupt_data["etcd_data"]
    if "sp_data" in corrupt_data:
        processor.sp.data = corrupt_data["sp_data"]

    # Run analysis and verify it handles corruption gracefully
    processor.analyze_kv_by_name()
    processor.analyze_kv_by_uid()

    # Verify that corrupted entries are marked for cleanup
    assert len(processor.update_data) > 0
