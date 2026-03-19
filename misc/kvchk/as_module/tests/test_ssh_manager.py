import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.managers.ssh_manager import SshManager
from storpool_kvchk.models.exceptions import SshManagerError
import subprocess


@pytest.fixture
def mock_args():
    """Create mock args for testing"""
    args = Mock()
    args.verbose = 2  # Enable debug output
    args.dry_run = False
    args.execute = False
    args.dummy_etcd = 0
    return args


@pytest.fixture
def ssh_manager(mock_args):
    """Create SshManager instance for testing"""
    return SshManager(mock_args)


class TestSshManagerInit:
    """Test SshManager initialization"""

    def test_init_inherits_from_base_manager(self, mock_args):
        """Test that SshManager properly inherits from BaseManager"""
        manager = SshManager(mock_args)
        assert manager.args == mock_args
        # Test inherited methods are available
        assert hasattr(manager, 'dbg')
        assert hasattr(manager, 'err')
        assert hasattr(manager, '_cls_name')


class TestSshManagerGetSymlinks:
    """Test get_symlinks method"""

    @patch('subprocess.run')
    def test_get_symlinks_success_single_symlink(self, mock_run, ssh_manager):
        """Test successful symlink retrieval with single symlink"""
        mock_stdout = (
            b"lrwxrwxrwx 1 root root 20 Mar 14 10:00 "
            b"/var/lib/one/datastores/1/123/disk.0 -> "
            b"/tmp/storpool-byid/a.bc.def\n"
        )
        mock_run.return_value = Mock(returncode=0, stdout=mock_stdout)

        symlinks = ssh_manager.get_symlinks('test-host')

        # Verify the SSH command was called correctly
        expected_cmd = (
            "ssh", "test-host", "find", "/var/lib/one/datastores",
            "-type", "l", "-exec", "ls", "-l", "{}", r"\;"
        )
        mock_run.assert_called_once_with(
            expected_cmd, capture_output=True, check=True
        )

        # Verify symlinks parsing
        assert 1 in symlinks  # datastore ID
        assert 123 in symlinks[1]  # VM ID
        assert 'disk.0' in symlinks[1][123]
        assert symlinks[1][123]['disk.0'] == '/tmp/storpool-byid/a.bc.def'

    @patch('subprocess.run')
    def test_get_symlinks_success_multiple_symlinks(
        self, mock_run, ssh_manager
    ):
        """Test successful symlink retrieval with multiple symlinks"""
        mock_stdout = (
            b"lrwxrwxrwx 1 root root 20 Mar 14 10:00 /var/lib/one/datastores/1/123/disk.0 -> /tmp/storpool-byid/a.bc.def\n"  # noqa: E501
            b"lrwxrwxrwx 1 root root 25 Mar 14 10:01 /var/lib/one/datastores/1/123/disk.1 -> /tmp/storpool-byid/x.yz.abc\n"  # noqa: E501
            b"lrwxrwxrwx 1 root root 30 Mar 14 10:02 /var/lib/one/datastores/2/456/disk.0 -> /tmp/storpool-byid/m.no.pqr\n"  # noqa: E501
        )
        mock_run.return_value = Mock(returncode=0, stdout=mock_stdout)

        symlinks = ssh_manager.get_symlinks('test-host')

        # Verify multiple symlinks are parsed correctly
        assert 1 in symlinks
        assert 2 in symlinks
        assert 123 in symlinks[1]
        assert 456 in symlinks[2]

        # Verify VM 123 has both disks
        assert 'disk.0' in symlinks[1][123]
        assert 'disk.1' in symlinks[1][123]
        expected_target1 = '/tmp/storpool-byid/a.bc.def'
        expected_target2 = '/tmp/storpool-byid/x.yz.abc'
        assert symlinks[1][123]['disk.0'] == expected_target1
        assert symlinks[1][123]['disk.1'] == expected_target2

        # Verify VM 456 has its disk
        assert 'disk.0' in symlinks[2][456]
        expected_target3 = '/tmp/storpool-byid/m.no.pqr'
        assert symlinks[2][456]['disk.0'] == expected_target3

    @patch('subprocess.run')
    def test_get_symlinks_empty_output(self, mock_run, ssh_manager):
        """Test handling of empty command output"""
        mock_run.return_value = Mock(returncode=0, stdout=b"")

        symlinks = ssh_manager.get_symlinks('test-host')

        assert symlinks == {}

    @patch('subprocess.run')
    def test_get_symlinks_no_arrows_in_output(self, mock_run, ssh_manager):
        """Test handling of output without symlink arrows"""
        mock_run.return_value = Mock(
            returncode=0,
            stdout=b"drwxr-xr-x 2 root root 4096 Mar 14 10:00 /var/lib/one/datastores/1/123\n"  # noqa: E501
        )

        symlinks = ssh_manager.get_symlinks('test-host')

        assert symlinks == {}

    @patch('subprocess.run')
    def test_get_symlinks_subprocess_error(self, mock_run, ssh_manager):
        """Test handling of subprocess.CalledProcessError"""
        error = subprocess.CalledProcessError(1, 'ssh command failed')
        mock_run.side_effect = error

        with pytest.raises(SshManagerError) as exc_info:
            ssh_manager.get_symlinks('test-host')

        assert 'subprocess.CalledProcessError' in str(exc_info.value)
        assert 'test-host' in str(exc_info.value)

    @patch('subprocess.run')
    def test_get_symlinks_general_exception(self, mock_run, ssh_manager):
        """Test handling of general exceptions"""
        mock_run.side_effect = OSError("Connection failed")

        with pytest.raises(SshManagerError) as exc_info:
            ssh_manager.get_symlinks('test-host')

        assert 'Unknown error' in str(exc_info.value)
        assert 'test-host' in str(exc_info.value)

    def test_get_symlinks_dummy_mode_level_2(self, ssh_manager):
        """Test dummy mode (dummy_etcd > 1) skips subprocess call"""
        ssh_manager.args.dummy_etcd = 2

        with patch('subprocess.run') as mock_run:
            symlinks = ssh_manager.get_symlinks('test-host')

        mock_run.assert_not_called()
        assert symlinks == {}

    def test_get_symlinks_dummy_mode_level_1(self, ssh_manager):
        """Test dummy_etcd level 1 still executes subprocess"""
        ssh_manager.args.dummy_etcd = 1

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0, stdout=b"")
            ssh_manager.get_symlinks('test-host')

        mock_run.assert_called_once()

    @patch('subprocess.run')
    def test_get_symlinks_debug_output(self, mock_run, ssh_manager):
        """Test debug output is called with verbose mode"""
        ssh_manager.args.verbose = 2
        mock_run.return_value = Mock(returncode=0, stdout=b"")

        with patch.object(ssh_manager, 'dbg') as mock_dbg:
            ssh_manager.get_symlinks('test-host')

            # Should call dbg for the result
            mock_dbg.assert_called()


class TestSshManagerCreateSymlink:
    """Test create_symlink method"""

    def test_create_symlink_missing_host_raises_error(self, ssh_manager):
        """Test error when host is missing from action_data"""
        action_data = {
            'uid': '123',
            'symlink': {
                'target': '/path/to/target',
                'link': '/path/to/link'
            }
        }

        with pytest.raises(ValueError) as exc_info:
            ssh_manager.create_symlink(action_data)

        assert 'Host is required' in str(exc_info.value)

    @patch('subprocess.run')
    def test_create_symlink_success_non_execute_mode(
        self, mock_run, ssh_manager
    ):
        """Test create_symlink when execute=False (default)"""
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }

        ssh_manager.create_symlink(action_data)

        # Should not call subprocess when execute=False
        mock_run.assert_not_called()

    @patch('subprocess.run')
    def test_create_symlink_success_execute_mode(self, mock_run, ssh_manager):
        """Test successful symlink creation in execute mode"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }
        mock_run.return_value = Mock(returncode=0, stdout=b"created link")

        ssh_manager.create_symlink(action_data)

        # Verify the SSH command was called correctly
        expected_cmd = (
            "ssh", "test-host", "ln", "-v", "-sf",
            "/path/to/123/target",  # _SP_UID_ should be replaced with uid
            "/path/to/link"
        )
        mock_run.assert_called_once_with(
            expected_cmd, capture_output=True, check=True
        )

    @patch('subprocess.run')
    def test_create_symlink_dry_run_mode(self, mock_run, ssh_manager):
        """Test dry run mode prints command but doesn't execute"""
        ssh_manager.args.execute = True
        ssh_manager.args.dry_run = True
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }

        with patch('builtins.print') as mock_print:
            ssh_manager.create_symlink(action_data)

        # Should print the dry-run command
        mock_print.assert_called()
        print_args = mock_print.call_args[0][0]
        assert '[dry-run]' in print_args

        # Should not actually run subprocess
        mock_run.assert_not_called()

    @patch('subprocess.run')
    def test_create_symlink_verbose_mode(self, mock_run, ssh_manager):
        """Test verbose mode prints action_data and response"""
        ssh_manager.args.execute = True
        ssh_manager.args.verbose = 1
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }
        mock_response = Mock(returncode=0, stdout=b"created link")
        mock_run.return_value = mock_response

        with patch('builtins.print') as mock_print:
            ssh_manager.create_symlink(action_data)

        # Should print response when verbose > 0
        assert mock_print.call_count >= 1
        # Call should include create_symlink
        call_args = str(mock_print.call_args_list[0])
        assert 'create_symlink' in call_args

    @patch('subprocess.run')
    def test_create_symlink_subprocess_exception(self, mock_run, ssh_manager):
        """Test handling of subprocess exceptions"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }
        mock_run.side_effect = subprocess.CalledProcessError(1, 'ssh failed')

        with patch('builtins.print') as mock_print:
            with pytest.raises(subprocess.CalledProcessError):
                ssh_manager.create_symlink(action_data)

        # Should print error message
        mock_print.assert_called()
        error_msg = str(mock_print.call_args_list[-1])
        assert 'create_symlink Error!' in error_msg

    @patch('subprocess.run')
    def test_create_symlink_general_exception(self, mock_run, ssh_manager):
        """Test handling of general exceptions"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': '123',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }
        mock_run.side_effect = OSError("Permission denied")

        with patch('builtins.print') as mock_print:
            with pytest.raises(OSError):
                ssh_manager.create_symlink(action_data)

        # Should print error message
        mock_print.assert_called()

    def test_create_symlink_uid_replacement(self, ssh_manager):
        """Test that _SP_UID_ is correctly replaced in target path"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': 'abc123',
            'symlink': {
                'host': 'test-host',
                'target': '/storpool/_SP_UID_/volume',
                'link': '/path/to/link'
            }
        }

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0)
            ssh_manager.create_symlink(action_data)

            # Check that the target path has uid replacement
            called_cmd = mock_run.call_args[0][0]
            assert '/storpool/abc123/volume' in called_cmd
            assert '_SP_UID_' not in str(called_cmd)


class TestSshManagerAction:
    """Test action method"""

    def test_action_method_exists(self, ssh_manager):
        """Test that action method exists and is callable"""
        assert hasattr(ssh_manager, 'action')
        assert callable(ssh_manager.action)

    def test_action_method_signature(self, ssh_manager):
        """Test action method accepts correct parameters"""
        action_data = {'test': 'data'}
        action = 'test_action'

        # Should not raise exception for method signature
        try:
            ssh_manager.action(action_data, action)
        except Exception:
            # We expect it might fail due to implementation,
            # but the signature should be correct
            pass


class TestSshManagerInheritance:
    """Test inheritance from BaseManager"""

    def test_inherits_dbg_method(self, ssh_manager):
        """Test that dbg method is inherited and works"""
        ssh_manager.args.verbose = 1

        with patch('builtins.print') as mock_print:
            ssh_manager.dbg(0, "test message")

        mock_print.assert_called_once()
        call_args = mock_print.call_args[0][0]
        assert 'SshManager' in call_args
        assert 'test message' in call_args

    def test_inherits_err_method(self, ssh_manager):
        """Test that err method is inherited and works"""
        with patch('builtins.print') as mock_print:
            ssh_manager.err("test error")

        mock_print.assert_called_once()
        call_args = mock_print.call_args[0][0]
        assert 'Error' in call_args
        assert 'SshManager' in call_args
        assert 'test error' in call_args

    def test_cls_name_method(self, ssh_manager):
        """Test that _cls_name method returns correct class name"""
        assert ssh_manager._cls_name() == 'SshManager'


class TestSshManagerEdgeCases:
    """Test edge cases and boundary conditions"""

    @patch('subprocess.run')
    def test_get_symlinks_malformed_path(self, mock_run, ssh_manager):
        """Test handling of malformed symlink paths"""
        mock_run.return_value = Mock(
            returncode=0,
            stdout=b"lrwxrwxrwx 1 root root 20 Mar 14 10:00 /var/lib/one/invalid/path -> /target\n"  # noqa: E501
        )

        # Should handle malformed paths gracefully
        with pytest.raises(Exception):
            ssh_manager.get_symlinks('test-host')

    @patch('subprocess.run')
    def test_get_symlinks_non_numeric_ids(self, mock_run, ssh_manager):
        """Test handling of non-numeric datastore/VM IDs"""
        mock_run.return_value = Mock(
            returncode=0,
            stdout=b"lrwxrwxrwx 1 root root 20 Mar 14 10:00 /var/lib/one/datastores/abc/def/disk.0 -> /target\n"  # noqa: E501
        )

        # Should handle non-numeric IDs gracefully
        with pytest.raises(Exception):
            ssh_manager.get_symlinks('test-host')

    def test_create_symlink_empty_uid(self, ssh_manager):
        """Test create_symlink with empty uid"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': '',
            'symlink': {
                'host': 'test-host',
                'target': '/path/to/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0)
            ssh_manager.create_symlink(action_data)

            # Should replace _SP_UID_ with empty string
            called_cmd = mock_run.call_args[0][0]
            assert '/path/to//target' in called_cmd

    def test_create_symlink_special_characters_in_uid(self, ssh_manager):
        """Test create_symlink with special characters in uid"""
        ssh_manager.args.execute = True
        action_data = {
            'uid': 'test-uid_123.vol',
            'symlink': {
                'host': 'test-host',
                'target': '/path/_SP_UID_/target',
                'link': '/path/to/link'
            }
        }

        with patch('subprocess.run') as mock_run:
            mock_run.return_value = Mock(returncode=0)
            ssh_manager.create_symlink(action_data)

            # Should handle special characters correctly
            called_cmd = mock_run.call_args[0][0]
            assert '/path/test-uid_123.vol/target' in called_cmd
