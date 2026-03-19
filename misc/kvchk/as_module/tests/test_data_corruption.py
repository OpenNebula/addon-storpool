import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import EtcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import StorPoolManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import OpenNebulaManager  # type: ignore[import-untyped] # noqa: E501
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

    # Mock OpenNebulaManager initialization to avoid real API calls
    with patch('storpool_kvchk.managers.one_manager.pyone'):
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0, stdout=b"")
            with patch.object(OpenNebulaManager, '_init_hosts'):
                with patch.object(OpenNebulaManager, '_init_datastores'):
                    with patch.object(OpenNebulaManager, '_init_ds_images'):
                        with patch.object(OpenNebulaManager, '_get_vm_disks'):
                            one_manager = OpenNebulaManager(
                                mock_args, ssh_manager
                            )

    # Initialize empty data structures for testing
    one_manager.vm_disks = {}
    one_manager.ds_images = {}
    one_manager.one_hosts = {}
    one_manager.one_datastores = {}

    sp_manager = StorPoolManager(mock_args)
    sp_manager.data = {}

    etcd_manager = EtcdManager(mock_args)
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

    def test_duplicate_uid_references(self, corrupted_setup):
        """Test handling of multiple byName entries pointing to same UID"""
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

        # Verify that update was triggered to fix duplicate references
        assert "one-img-789" in processor.update_data
        assert "kv" in processor.update_data["one-img-789"]["action"]


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
                "snapshot": False
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

    def test_snapshot_volume_mismatch(self, corrupted_setup):
        """Test handling of StorPool entries with wrong snapshot status"""
        processor = corrupted_setup

        # Set up StorPool data with wrong snapshot status
        processor.sp.data = {
            "one-img-456": {
                "globalId": "123",
                "name": "one-img-456",
                "tags": {"type": "PERS"},
                "snapshot": True  # Should be False for this type
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

        # Verify that update was triggered to fix snapshot status
        assert "one-img-456" in processor.update_data
        assert "Update" in processor.update_data["one-img-456"]["action"]


class TestOpenNebulaCorruption:
    """Test scenarios with corrupted OpenNebula data"""

    def test_invalid_disk_references(self, corrupted_setup):
        """Test handling of invalid disk references in OpenNebula"""
        processor = corrupted_setup

        # Set up ONE data with invalid disk references
        processor.one.vm_disks = {
            "one-img-456": {
                "vm_id": 123,
                "disk_id": 0,
                "image_id": None,  # Missing image ID
                "disktype": DiskType.PERSISTENT,  # Inconsistent with missing image # noqa: E501
                "spname": "one-img-456"
            }
        }

        # Run analysis
        with pytest.raises(UnhandledCase):
            processor.analyze_vm_disks()

    def test_inconsistent_snapshot_data(self, corrupted_setup):
        """Test handling of inconsistent snapshot data in OpenNebula"""
        processor = corrupted_setup

        # Set up ONE data with inconsistent snapshot information
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

        # Verify that update was triggered to fix snapshot inconsistency
        assert "one-snap-456-0" in processor.update_data
        assert "Update" in processor.update_data["one-snap-456-0"]["action"]


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
