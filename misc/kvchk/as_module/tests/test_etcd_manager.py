import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.managers.etcd_manager import EtcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.exceptions import KvByNameError, KvByUidError  # type: ignore[import-untyped] # noqa: E501


@pytest.fixture
def mock_args():
    """Create mock args for testing"""
    args = Mock()
    args.verbose = 0
    args.dry_run = False
    args.execute = False
    args.dummy_etcd = 0
    return args


@pytest.fixture
def sample_etcd_data():
    """Sample etcd data for testing"""
    return {
        "byName": {
            "ans-sys-26-1": "~fir.b.jm",
            "ans-img-48": "~fir.b.e7",
            "test-volume": "~test.uid.123"
        },
        "byUid": {
            "~fir.b.jm": "ans-sys-26-1",
            "~fir.b.e7": "ans-img-48",
            "~test.uid.123": "test-volume"
        }
    }


@pytest.fixture
def etcd_manager_with_mock_data(mock_args, sample_etcd_data):
    """Create EtcdManager with mocked data loading"""
    with patch.object(EtcdManager, '_load_data'):
        manager = EtcdManager(mock_args)
        manager.data = sample_etcd_data
        return manager


@pytest.fixture
def dummy_etcd_manager(mock_args):
    """Create EtcdManager in dummy mode (no etcd loading)"""
    mock_args.dummy_etcd = 1
    manager = EtcdManager(mock_args)
    # Reset data to empty state for dummy mode
    manager.data = {"byName": {}, "byUid": {}}
    return manager


class TestEtcdManagerInit:
    """Test EtcdManager initialization"""

    @patch('etcd3.client')
    @patch.object(EtcdManager, '_load_data')
    def test_init_normal_mode(self, mock_load_data, mock_etcd_client,
                              mock_args):
        """Test initialization in normal mode calls _load_data"""
        mock_args.dummy_etcd = 0

        manager = EtcdManager(mock_args)

        mock_load_data.assert_called_once()
        assert manager.args == mock_args

    def test_init_dummy_mode(self, mock_args):
        """Test initialization in dummy mode skips _load_data"""
        mock_args.dummy_etcd = 1

        with patch.object(EtcdManager, '_load_data') as mock_load_data:
            manager = EtcdManager(mock_args)

            mock_load_data.assert_not_called()
            assert manager.args == mock_args


class TestEtcdManagerLoadData:
    """Test _load_data method"""

    @patch('etcd3.client')
    def test_load_data_success(self, mock_etcd_client, mock_args):
        """Test successful data loading from etcd"""
        # Mock etcd client and responses
        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd

        # Mock etcd key-value pairs
        mock_metadata1 = Mock()
        mock_metadata1.key = b'/byName/ans-sys-26-1'
        mock_metadata2 = Mock()
        mock_metadata2.key = b'/byUid/~fir.b.jm'
        mock_metadata3 = Mock()
        mock_metadata3.key = b'/other/key'  # Should be skipped

        mock_etcd.get_all.return_value = [
            (b'~fir.b.jm', mock_metadata1),
            (b'ans-sys-26-1', mock_metadata2),
            (b'some-value', mock_metadata3),
        ]

        # Create manager and load data
        mock_args.dummy_etcd = 0
        manager = EtcdManager(mock_args)

        # Verify data was loaded correctly
        assert manager.data["byName"]["ans-sys-26-1"] == "~fir.b.jm"
        assert manager.data["byUid"]["~fir.b.jm"] == "ans-sys-26-1"
        assert "other" not in manager.data

    @patch('etcd3.client')
    def test_load_data_with_duplicates(self, mock_etcd_client, mock_args):
        """Test data loading with duplicate keys"""
        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd

        # Mock duplicate keys
        mock_metadata1 = Mock()
        mock_metadata1.key = b'/byName/test-vol'
        mock_metadata2 = Mock()
        mock_metadata2.key = b'/byName/test-vol'  # Duplicate

        mock_etcd.get_all.return_value = [
            (b'~uid1', mock_metadata1),
            (b'~uid2', mock_metadata2),  # This should overwrite the first
        ]

        mock_args.dummy_etcd = 0
        mock_args.verbose = 1  # Enable debug output

        manager = EtcdManager(mock_args)

        # The second value should overwrite the first
        assert manager.data["byName"]["test-vol"] == "~uid2"


class TestEtcdManagerValidation:
    """Test validate_kv method"""

    def test_validate_kv_success(self, etcd_manager_with_mock_data):
        """Test successful KV validation"""
        manager = etcd_manager_with_mock_data

        result = manager.validate_kv("fir.b.jm", "ans-sys-26-1")

        assert result is True

    def test_validate_kv_uid_error(self, etcd_manager_with_mock_data):
        """Test KV validation with missing UID"""
        manager = etcd_manager_with_mock_data

        with pytest.raises(KvByUidError) as exc_info:
            manager.validate_kv("nonexistent.uid", "ans-sys-26-1")

        assert "nonexistent.uid ans-sys-26-1" in str(exc_info.value)

    def test_validate_kv_name_error(self, etcd_manager_with_mock_data):
        """Test KV validation with UID exists but name mismatch"""
        manager = etcd_manager_with_mock_data

        # Modify data to create name mismatch scenario
        manager.data["byUid"]["~fir.b.jm"] = "wrong-name"

        with pytest.raises(KvByUidError) as exc_info:
            manager.validate_kv("fir.b.jm", "ans-sys-26-1")

        assert "fir.b.jm ans-sys-26-1" in str(exc_info.value)

    def test_validate_kv_missing_reverse_mapping(
        self, etcd_manager_with_mock_data,
    ):
        """Test KV validation when reverse mapping is missing"""
        manager = etcd_manager_with_mock_data

        # Remove the reverse mapping
        del manager.data["byName"]["ans-sys-26-1"]

        with pytest.raises(KvByNameError) as exc_info:
            manager.validate_kv("fir.b.jm", "ans-sys-26-1")

        assert "fir.b.jm ans-sys-26-1" in str(exc_info.value)


class TestEtcdManagerKvData:
    """Test kv_data method"""

    def test_kv_data_normal_mode(
        self, etcd_manager_with_mock_data, sample_etcd_data
    ):
        """Test kv_data returns data in normal mode"""
        manager = etcd_manager_with_mock_data

        result = manager.kv_data()

        assert result == sample_etcd_data

    def test_kv_data_dummy_mode(self, dummy_etcd_manager):
        """Test kv_data in dummy mode"""
        manager = dummy_etcd_manager
        manager.args.verbose = 1  # Enable debug output

        result = manager.kv_data()

        assert result == {"byName": {}, "byUid": {}}


class TestEtcdManagerWriteKvData:
    """Test write_kv_data method"""

    @patch('etcd3.client')
    def test_write_kv_data_execute_mode(
        self, mock_etcd_client, etcd_manager_with_mock_data
    ):
        """Test write_kv_data in execute mode"""
        manager = etcd_manager_with_mock_data
        manager.args.execute = True
        manager.args.dry_run = False

        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd
        mock_etcd.put.return_value = (True, 1)  # Mock successful put

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        manager.write_kv_data(action_data)

        # Verify etcd.put was called twice (byName and byUid)
        assert mock_etcd.put.call_count == 2

        # Verify the calls were made with correct key-value pairs
        calls = mock_etcd.put.call_args_list
        assert calls[0][0] == ("/byName/test-volume", "~test.uid.456")
        assert calls[1][0] == ("/byUid/~test.uid.456", "test-volume")

    @patch('etcd3.client')
    def test_write_kv_data_dry_run_mode(
        self, mock_etcd_client, etcd_manager_with_mock_data
    ):
        """Test write_kv_data in dry run mode"""
        manager = etcd_manager_with_mock_data
        manager.args.execute = True
        manager.args.dry_run = True
        manager.args.verbose = 1  # Enable debug output

        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        manager.write_kv_data(action_data)

        # Verify etcd.put was not called in dry run mode
        mock_etcd.put.assert_not_called()

    @patch('etcd3.client')
    def test_write_kv_data_uid_with_tilde(
        self, mock_etcd_client, etcd_manager_with_mock_data
    ):
        """Test write_kv_data with UID that already has tilde"""
        manager = etcd_manager_with_mock_data
        manager.args.execute = True
        manager.args.dry_run = False

        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd
        mock_etcd.put.return_value = (True, 1)

        action_data = {
            "spname": "test-volume",
            "uid": "~already.has.tilde"
        }

        manager.write_kv_data(action_data)

        # Verify the UID is used as-is (not double-prefixed)
        calls = mock_etcd.put.call_args_list
        assert calls[0][0] == ("/byName/test-volume", "~already.has.tilde")
        assert calls[1][0] == ("/byUid/~already.has.tilde", "test-volume")

    def test_write_kv_data_execute_false(self, etcd_manager_with_mock_data):
        """Test write_kv_data when execute is False"""
        manager = etcd_manager_with_mock_data
        manager.args.execute = False

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        with patch('etcd3.client') as mock_etcd_client:
            manager.write_kv_data(action_data)

            # Verify etcd client is created but put is not called
            mock_etcd_client.assert_called_once()
            mock_etcd_client.return_value.put.assert_not_called()

    @patch('etcd3.client')
    def test_write_kv_data_exception_handling(
        self, mock_etcd_client, etcd_manager_with_mock_data
    ):
        """Test write_kv_data exception handling"""
        manager = etcd_manager_with_mock_data
        manager.args.execute = True
        manager.args.dry_run = False

        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd
        mock_etcd.put.side_effect = Exception("Connection failed")

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        with pytest.raises(Exception) as exc_info:
            manager.write_kv_data(action_data)

        assert "Connection failed" in str(exc_info.value)


class TestEtcdManagerAction:
    """Test action method"""

    def test_action_kvupdate(self, etcd_manager_with_mock_data):
        """Test action method with kvupdate action"""
        manager = etcd_manager_with_mock_data

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        with patch.object(manager, 'write_kv_data') as mock_write:
            manager.action(action_data, "kvupdate")

            mock_write.assert_called_once_with(action_data)

    def test_action_kv(self, etcd_manager_with_mock_data):
        """Test action method with kv action"""
        manager = etcd_manager_with_mock_data

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        with patch.object(manager, 'write_kv_data') as mock_write:
            manager.action(action_data, "kv")

            mock_write.assert_called_once_with(action_data)

    def test_action_unknown(self, etcd_manager_with_mock_data):
        """Test action method with unknown action"""
        manager = etcd_manager_with_mock_data
        manager.args.verbose = 1  # Enable debug output

        action_data = {
            "spname": "test-volume",
            "uid": "test.uid.456"
        }

        with patch.object(manager, 'write_kv_data') as mock_write:
            manager.action(action_data, "unknown_action")

            # write_kv_data should not be called for unknown actions
            mock_write.assert_not_called()


class TestEtcdManagerIntegration:
    """Integration tests for EtcdManager"""

    @patch('etcd3.client')
    def test_full_workflow(self, mock_etcd_client, mock_args):
        """Test a complete workflow from loading to validation to writing"""
        # Setup mock etcd client
        mock_etcd = Mock()
        mock_etcd_client.return_value = mock_etcd

        # Mock initial data loading
        mock_metadata1 = Mock()
        mock_metadata1.key = b'/byName/existing-vol'
        mock_metadata2 = Mock()
        mock_metadata2.key = b'/byUid/~existing.uid'

        mock_etcd.get_all.return_value = [
            (b'~existing.uid', mock_metadata1),
            (b'existing-vol', mock_metadata2),
        ]

        mock_etcd.put.return_value = (True, 1)

        # Create manager
        mock_args.dummy_etcd = 0
        mock_args.execute = True
        mock_args.dry_run = False
        manager = EtcdManager(mock_args)

        # Test validation of existing data
        assert manager.validate_kv("existing.uid", "existing-vol") is True

        # Test getting data
        data = manager.kv_data()
        assert "existing-vol" in data["byName"]
        assert "~existing.uid" in data["byUid"]

        # Test writing new data
        new_action_data = {
            "spname": "new-volume",
            "uid": "new.uid.123"
        }
        manager.action(new_action_data, "kv")

        # Verify etcd.put was called for the new data
        assert mock_etcd.put.call_count == 2
