import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.managers.storpool_manager import StorPoolManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.exceptions import UnknownApiCall  # type: ignore[import-untyped] # noqa: E501


# Module-level patches that apply to all tests
@pytest.fixture(autouse=True)
def mock_storpool_modules():
    """Auto-applied fixture that mocks StorPool modules for all tests"""

    # Create comprehensive SPConfig mock
    config_dict = {
        'SP_API_HTTP_HOST': 'localhost',
        'SP_API_HTTP_PORT': '81',
        'SP_AUTH_TOKEN': 'test-token-12345'
    }

    mock_config = Mock()
    mock_config.__getitem__ = lambda self, key: config_dict[key]
    mock_config.__contains__ = lambda self, key: key in config_dict
    # Fix the get method to handle optional parameters properly

    def mock_get(key, default=None):
        return config_dict.get(key, default)

    mock_config.get = mock_get
    mock_config.keys = lambda self: config_dict.keys()
    mock_config.values = lambda self: config_dict.values()
    mock_config.items = lambda self: config_dict.items()

    # Create comprehensive API mock with all required responses
    mock_api = Mock()

    # Mock volume data
    mock_volume = Mock()
    mock_volume.globalId = "vol-123-global-id"
    mock_volume.name = "test-volume"
    mock_volume.tags = {"type": "PERS", "kvcheck": "test"}
    mock_volume.size = 10737418240  # 10GB in bytes

    # Mock snapshot data
    mock_snapshot = Mock()
    mock_snapshot.globalId = "snap-456-global-id"
    mock_snapshot.name = "test-snapshot"
    snap_tags = {"type": "PERS", "snap": "0", "kvcheck": "test"}
    mock_snapshot.tags = snap_tags
    mock_snapshot.size = 10737418240  # 10GB in bytes

    # Mock attachment data (include missing snapshot attribute)
    mock_attachment = Mock()
    mock_attachment.volume = "test-volume"
    mock_attachment.globalId = "vol-123-global-id"
    mock_attachment.clusterId = "1"
    mock_attachment.cluster = "test-cluster"
    mock_attachment.client = "1"
    mock_attachment.rights = "rw"
    mock_attachment.snapshot = False  # This was missing in original

    # Set up API list methods
    mock_api.volumesList.return_value = [mock_volume]
    mock_api.snapshotsList.return_value = [mock_snapshot]
    mock_api.attachmentsList.return_value = [mock_attachment]
    mock_api.templatesList.return_value = []

    # Mock successful API responses
    mock_success_response = Mock()
    mock_success_response.ok = True
    mock_success_response.snapshotGlobalId = "new-snap-789-global-id"

    # Set up API action methods
    mock_api.volumeUpdate.return_value = mock_success_response
    mock_api.volumeDelete.return_value = mock_success_response
    mock_api.snapshotUpdate.return_value = mock_success_response
    mock_api.snapshotDelete.return_value = mock_success_response
    mock_api.snapshotCreate.return_value = mock_success_response

    # Apply patches for the entire test session
    with patch('storpool_kvchk.managers.storpool_manager.SPConfig',
               return_value=mock_config):
        with patch('storpool_kvchk.managers.storpool_manager.Api',
                   return_value=mock_api):
            # Store references for test access
            yield {
                'config': mock_config,
                'api': mock_api,
                'volume': mock_volume,
                'snapshot': mock_snapshot,
                'attachment': mock_attachment,
                'response': mock_success_response
            }


@pytest.fixture
def mock_args():
    """Mock command line arguments"""
    args = Mock()
    args.verbose = 0
    args.dry_run = False
    args.execute = False
    return args


@pytest.fixture
def sp_manager(mock_args, mock_storpool_modules):
    """Create StorPoolManager with mocked dependencies"""
    manager = StorPoolManager(mock_args)
    # Attach mock references for direct access in tests
    manager._mock_api = mock_storpool_modules['api']
    manager._mock_config = mock_storpool_modules['config']
    return manager


@pytest.fixture
def mock_api_error():
    """Mock StorPool ApiError for error handling tests"""
    with patch('storpool.spapi.ApiError') as mock_error:
        mock_error_instance = Mock()
        mock_error_instance.name = "TestError"
        mock_error_instance.desc = "Test error description"
        mock_error_instance.json = {"error": "test"}
        mock_error.return_value = mock_error_instance
        yield mock_error


class TestStorPoolManager:
    """Test StorPoolManager functionality"""

    def test_init_with_config(self, sp_manager):
        """Test initialization with mocked StorPool configuration"""
        assert isinstance(sp_manager.data, dict)
        assert sp_manager.args.verbose == 0
        assert sp_manager.args.dry_run is False
        assert sp_manager.args.execute is False

        # Verify API was initialized correctly
        assert hasattr(sp_manager, 'api')

    def test_load_data_populates_data_structures(self, sp_manager):
        """Test that _load_data() properly populates volumes, snapshots,
        and attachments"""
        # Verify data was loaded
        assert "test-volume" in sp_manager.data
        assert "test-snapshot" in sp_manager.data

        # Verify volume data structure
        volume_data = sp_manager.data["test-volume"]
        assert volume_data["globalId"] == "vol-123-global-id"
        assert volume_data["name"] == "test-volume"
        assert volume_data["tags"] == {"type": "PERS", "kvcheck": "test"}
        assert volume_data["size"] == 10737418240
        assert volume_data["snapshot"] is False

        # Verify snapshot data structure
        snapshot_data = sp_manager.data["test-snapshot"]
        assert snapshot_data["globalId"] == "snap-456-global-id"
        assert snapshot_data["name"] == "test-snapshot"
        tags = {"type": "PERS", "snap": "0", "kvcheck": "test"}
        assert snapshot_data["tags"] == tags
        assert snapshot_data["size"] == 10737418240
        assert snapshot_data["snapshot"] is True

        # Verify attachments were processed correctly
        assert hasattr(sp_manager, 'attachments')
        assert "test-volume" in sp_manager.attachments

        attachment = sp_manager.attachments["test-volume"]
        assert attachment["globalId"] == "vol-123-global-id"
        assert attachment["clusterId"] == "1"
        assert attachment["cluster"] == "test-cluster"
        assert attachment["client"] == [1]  # Should be converted to list
        assert attachment["rights"] == ["rw"]  # Should be converted to list
        assert attachment["volume"] == "test-volume"
        assert attachment["snapshot"] is False

    def test_api_list_methods_called(self, sp_manager):
        """Test that all required API list methods are called during init"""
        # Verify API methods were called
        sp_manager._mock_api.volumesList.assert_called()
        sp_manager._mock_api.snapshotsList.assert_called()
        sp_manager._mock_api.attachmentsList.assert_called()

    @pytest.mark.parametrize("action,snapshot,expected_cmd", [
        ("Update", False, "volumeUpdate"),
        ("Delete", False, "volumeDelete"),
        ("Update", True, "snapshotUpdate"),
        ("Delete", True, "snapshotDelete"),
    ])
    def test_action_api_calls(
        self, sp_manager, action, snapshot, expected_cmd
    ):
        """Test that action() method calls correct API methods"""
        # Set execute mode to actually make API calls
        sp_manager.args.execute = True

        action_data = {
            "uid": "test-uid-123",
            "snapshot": snapshot,
            "tags": {"type": "PERS", "kvcheck": "test"}
        }

        # Execute action
        sp_manager.action(action_data, action)

        # Verify correct API method was called with right parameters
        api_method = getattr(sp_manager._mock_api, expected_cmd)
        if action == "Update":
            # Update calls require payload with rename/tags
            expected_payload = {
                "rename": "",
                "tags": {"type": "PERS", "kvcheck": "test"}
            }
            api_method.assert_called_once_with(
                "~test-uid-123", expected_payload
            )
        else:
            # Delete calls don't require payload
            api_method.assert_called_once_with("~test-uid-123")

    def test_action_unknown_action_raises_exception(self, sp_manager):
        """Test that unknown actions raise UnknownApiCall exception"""
        sp_manager.args.execute = True

        action_data = {
            "uid": "test-uid-123",
            "snapshot": False
        }

        with pytest.raises(UnknownApiCall) as exc_info:
            sp_manager.action(action_data, "UnknownAction")

        assert "UnknownAction" in str(exc_info.value)

    def test_dry_run_mode_no_api_calls(self, sp_manager):
        """Test that dry run mode doesn't make actual API calls"""
        sp_manager.args.dry_run = True

        action_data = {
            "uid": "test-uid-123",
            "snapshot": False,
            "tags": {"type": "PERS"}
        }

        # Reset mock call counts
        sp_manager._mock_api.volumeUpdate.reset_mock()

        # Execute action in dry run mode
        sp_manager.action(action_data, "Update")

        # Verify no API calls were made
        sp_manager._mock_api.volumeUpdate.assert_not_called()

    def test_execute_false_no_api_calls(self, sp_manager):
        """Test that execute=False mode doesn't make actual API calls"""
        sp_manager.args.execute = False
        sp_manager.args.dry_run = False

        action_data = {
            "uid": "test-uid-123",
            "snapshot": False,
            "tags": {"type": "PERS"}
        }

        # Reset mock call counts
        sp_manager._mock_api.volumeUpdate.reset_mock()

        # Execute action with execute=False
        sp_manager.action(action_data, "Update")

        # Verify no API calls were made
        sp_manager._mock_api.volumeUpdate.assert_not_called()

    def test_volumefreeze_functionality(self, sp_manager):
        """Test volumefreeze method creates snapshot and deletes volume"""
        sp_manager.args.execute = True

        in_data = {
            "uid": "vol-123-global-id",
            "spname": "test-volume",
            "sptags": {"type": "PERS"},
            "tags": {"kvcheck": "test"}
        }

        # Execute volumefreeze
        sp_manager.volumefreeze(in_data, "freeze")

        # Verify snapshot creation was called
        expected_payload = {
            "name": "",
            "tags": {"type": "PERS", "kvcheck": "test"}
        }
        sp_manager._mock_api.snapshotCreate.assert_called_once_with(
            "test-volume",
            expected_payload
        )

        # Verify volume deletion was called
        sp_manager._mock_api.volumeDelete.assert_called_once_with(
            "test-volume"
        )

        # Verify in_data was updated correctly
        assert in_data["snapshot"] is True
        assert in_data["uid"] == "new-snap-789-global-id"

    def test_volumefreeze_dry_run(self, sp_manager):
        """Test volumefreeze in dry run mode"""
        sp_manager.args.dry_run = True
        sp_manager.args.execute = True

        in_data = {
            "uid": "vol-123-global-id",
            "spname": "test-volume",
            "sptags": {"type": "PERS"},
            "tags": {"kvcheck": "test"}
        }

        # Reset mock call counts
        sp_manager._mock_api.snapshotCreate.reset_mock()
        sp_manager._mock_api.volumeDelete.reset_mock()

        # Execute volumefreeze in dry run mode
        sp_manager.volumefreeze(in_data, "freeze")

        # Verify no API calls were made
        sp_manager._mock_api.snapshotCreate.assert_not_called()
        sp_manager._mock_api.volumeDelete.assert_not_called()

        # Verify in_data was updated for dry run
        assert in_data["snapshot"] is True
        assert in_data["uid"] == "new.globalid"

    def test_api_error_handling(self, sp_manager, mock_api_error):
        """Test API error handling in action methods"""
        sp_manager.args.execute = True

        # Create a proper exception instance to be raised
        error_instance = Exception("Test API Error")
        sp_manager._mock_api.volumeUpdate.side_effect = error_instance

        action_data = {
            "uid": "test-uid-123",
            "snapshot": False,
            "tags": {"type": "PERS"}
        }

        # Verify error is propagated
        with pytest.raises(Exception) as exc_info:
            sp_manager.action(action_data, "Update")

        assert "Test API Error" in str(exc_info.value)

    def test_multiple_attachments_same_volume(
        self, mock_args, mock_storpool_modules
    ):
        """Test handling of multiple attachments for the same volume"""
        # Create multiple attachments for the same volume
        mock_attachment1 = Mock()
        mock_attachment1.volume = "multi-attach-volume"
        mock_attachment1.globalId = "vol-multi-123"
        mock_attachment1.clusterId = "1"
        mock_attachment1.cluster = "cluster-1"
        mock_attachment1.client = "1"
        mock_attachment1.rights = "rw"
        mock_attachment1.snapshot = False

        mock_attachment2 = Mock()
        mock_attachment2.volume = "multi-attach-volume"
        mock_attachment2.globalId = "vol-multi-123"
        mock_attachment2.clusterId = "1"
        mock_attachment2.cluster = "cluster-1"
        mock_attachment2.client = "2"
        mock_attachment2.rights = "ro"
        mock_attachment2.snapshot = False

        # Update the existing mock to return multiple attachments
        mock_storpool_modules['api'].attachmentsList.return_value = [
            mock_attachment1, mock_attachment2
        ]
        mock_storpool_modules['api'].volumesList.return_value = []
        mock_storpool_modules['api'].snapshotsList.return_value = []

        # Create a fresh manager
        fresh_manager = StorPoolManager(mock_args)

        # Verify multiple attachments are handled correctly
        assert "multi-attach-volume" in fresh_manager.attachments
        attachment = fresh_manager.attachments["multi-attach-volume"]
        assert attachment["client"] == [1, 2]  # Both clients
        assert attachment["rights"] == ["rw", "ro"]  # Both rights

    def test_config_access_methods(self, mock_storpool_modules):
        """Test that SPConfig mock supports all expected access methods"""
        config = mock_storpool_modules['config']

        # Test dictionary-style access
        assert config["SP_API_HTTP_HOST"] == "localhost"
        assert config["SP_API_HTTP_PORT"] == "81"
        assert config["SP_AUTH_TOKEN"] == "test-token-12345"

        # Test membership testing
        assert "SP_API_HTTP_HOST" in config
        assert "NONEXISTENT_KEY" not in config

        # Test get method
        assert config.get("SP_API_HTTP_HOST") == "localhost"
        assert config.get("NONEXISTENT_KEY") is None
        assert config.get("NONEXISTENT_KEY", "default") == "default"
