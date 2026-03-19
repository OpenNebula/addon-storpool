import pytest
from unittest.mock import Mock, patch
import subprocess
import os

from storpool_kvchk.managers.one_manager import OpenNebulaManager
from storpool_kvchk.models.enums import DiskType, ImageType


@pytest.fixture
def mock_args():
    args = Mock()
    args.verbose = 0
    args.dry_run = False
    args.execute = False
    args.dummy_etcd = 0
    args.one_token = None
    args.one_px = "one"
    args.default_qosclass = "default-qos"
    return args


@pytest.fixture
def mock_ssh_manager():
    ssh_manager = Mock()
    ssh_manager.get_symlinks.return_value = {
        0: {
            123: {"disk.0": "/tmp/storpool-byid/a.bc.def"}
        }
    }
    ssh_manager.SshManagerError = Exception
    return ssh_manager


@pytest.fixture
def mock_pyone_api():
    api = Mock()

    # Mock datastorepool.info
    ds_mock = Mock()
    ds_mock.NAME = "test-ds"
    ds_mock.ID = 1
    ds_mock.STATE = 0
    ds_mock.TYPE = 0
    ds_mock.DISK_TYPE = 0
    ds_mock.TEMPLATE.get.return_value = "ds-qos"

    datastorepool_mock = Mock()
    datastorepool_mock.get_DATASTORE.return_value = [ds_mock]
    api.datastorepool.info.return_value = datastorepool_mock

    # Mock hostpool.info
    host_mock = Mock()
    host_mock.NAME = "test-host"
    host_mock.ID = 1
    host_mock.STATE = 2
    host_mock.VM_MAD = "kvm"

    hostpool_mock = Mock()
    hostpool_mock.get_HOST.return_value = [host_mock]
    api.hostpool.info.return_value = hostpool_mock

    # Mock imagepool.info
    image_mock = Mock()
    image_mock.ID = 1
    image_mock.TYPE = 0
    image_mock.PERSISTENT = 1
    image_mock.STATE = 1
    image_mock.NAME = "test-image"
    image_mock.DATASTORE_ID = 1
    image_mock.VMS.get_ID.return_value = [123]
    image_mock.TEMPLATE.get.return_value = "img-qos"

    # Mock snapshots for image
    snapshot_mock = Mock()
    snapshot_mock.ID = 1
    snapshot_mock.SIZE = 1024
    image_mock.SNAPSHOTS.SNAPSHOT = [snapshot_mock]

    imagepool_mock = Mock()
    imagepool_mock.get_IMAGE.return_value = [image_mock]
    api.imagepool.info.return_value = imagepool_mock

    # Mock vm.info
    vm_mock = Mock()
    vm_mock.ID = 123
    vm_mock.STATE = 3
    vm_mock.LCM_STATE = 3
    vm_mock.NAME = "test-vm"

    # Mock history records
    history_mock = Mock()
    history_mock.DS_ID = 1
    history_mock.HOSTNAME = "test-host"
    vm_mock.HISTORY_RECORDS.HISTORY = [history_mock]

    # Mock template
    template_mock = Mock()
    template_mock.keys.return_value = ["CONTEXT", "DISK"]
    template_mock.get.side_effect = lambda key: {
        "CONTEXT": {"DISK_ID": 1},
        "DISK": {
            "DISK_ID": 0, "IMAGE_ID": 1, "CLONE": "YES",
            "TYPE": "FILE", "DATASTORE_ID": 1
        },
        "SNAPSHOT": None
    }.get(key)
    vm_mock.TEMPLATE = template_mock

    # Mock user template
    user_template_mock = Mock()
    user_template_mock.get.return_value = None
    vm_mock.USER_TEMPLATE = user_template_mock

    # Mock snapshots
    vm_mock.SNAPSHOTS = []

    api.vm.info.return_value = vm_mock

    return api


class TestOpenNebulaManager:
    """Test OpenNebula manager functionality"""

    @patch.dict(os.environ, {"ONE_AUTH": "/tmp/test_auth"})
    @patch('builtins.open')
    @patch('os.path.exists')
    def test_get_one_token_from_file(self, mock_exists, mock_open, mock_args):
        """Test getting ONE token from file"""
        mock_exists.return_value = True
        mock_file = mock_open.return_value.__enter__.return_value
        mock_file.read.return_value = "test:token\n"

        with patch('storpool_kvchk.managers.one_manager.pyone'):
            with patch('subprocess.run'):
                manager = OpenNebulaManager.__new__(OpenNebulaManager)
                manager.args = mock_args

                token = manager.get_one_token()
                assert token == "test:token"

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_vmids_success(self, mock_run, mock_pyone, mock_args,
                                mock_ssh_manager):
        """Test successful VM IDs initialization"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n456\n789\n"

        with patch.object(OpenNebulaManager, '_init_hosts'):
            with patch.object(OpenNebulaManager, '_init_ds_images'):
                with patch.object(OpenNebulaManager, '_get_vm_disks'):
                    manager = OpenNebulaManager(mock_args, mock_ssh_manager)

        assert manager.vm_ids == [123, 456, 789]

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_vmids_command_error(self, mock_run, mock_pyone, mock_args,
                                      mock_ssh_manager):
        """Test VM IDs initialization with command error"""
        mock_run.side_effect = subprocess.CalledProcessError(1, 'cmd')

        with patch.object(OpenNebulaManager, '_init_hosts'):
            with patch.object(OpenNebulaManager, '_init_ds_images'):
                with patch.object(OpenNebulaManager, '_get_vm_disks'):
                    with pytest.raises(subprocess.CalledProcessError):
                        OpenNebulaManager(mock_args, mock_ssh_manager)

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_hosts(self, mock_run, mock_pyone, mock_args,
                        mock_ssh_manager, mock_pyone_api):
        """Test hosts initialization"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n"

        mock_pyone.OneServer.return_value = mock_pyone_api

        manager = OpenNebulaManager(mock_args, mock_ssh_manager)

        assert "test-host" in manager.one_hosts
        assert manager.one_hosts["test-host"]["name"] == "test-host"
        assert manager.one_hosts["test-host"]["id"] == 1
        assert manager.one_hosts["test-host"]["state"] == 2
        assert manager.one_hosts["test-host"]["vm_mad"] == "kvm"
        assert manager.one_hosts["test-host"]["links"] == {
            0: {
                123: {"disk.0": "/tmp/storpool-byid/a.bc.def"}
            }
        }

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_hosts_ssh_error(self, mock_run, mock_pyone, mock_args,
                                  mock_ssh_manager, mock_pyone_api):
        """Test hosts initialization with SSH error"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n"

        mock_ssh_manager.get_symlinks.side_effect = Exception("SSH Error")
        mock_pyone.OneServer.return_value = mock_pyone_api

        # Should not raise exception, just print error
        manager = OpenNebulaManager(mock_args, mock_ssh_manager)

        assert "test-host" in manager.one_hosts

    def test_prepare_vm_disk_nonpersistent(self, mock_args):
        """Test preparing non-persistent VM disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": 1,
            "clone": "YES",
            "type": "BLOCK",
            "fs": "",
            "sys_ds_id": 0,
            "img_ds_id": 1,
            "qosclass": "default-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["vm_id"] == 123
        assert v_info["disk_id"] == 0
        assert v_info["disktype"] == DiskType.NONPERSISTENT
        assert v_info["spname"] == "one-img-1-123-0"
        assert v_info["legacy"] == "one-img-1-123-0"
        assert v_info["link"] == "/var/lib/one/datastores/0/123/disk.0"

    def test_prepare_vm_disk_persistent(self, mock_args):
        """Test preparing persistent VM disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": 1,
            "clone": "NO",
            "type": "BLOCK",
            "fs": "",
            "sys_ds_id": 0,
            "img_ds_id": 1,
            "qosclass": "default-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["disktype"] == DiskType.PERSISTENT
        assert v_info["spname"] == "one-img-1"
        assert v_info["legacy"] == "one-img-1"
        assert v_info["link"] == "/var/lib/one/datastores/0/123/disk.0"

    def test_prepare_vm_disk_cdrom(self, mock_args):
        """Test preparing CDROM disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": 1,
            "clone": "YES",
            "type": "CDROM",
            "fs": "",
            "sys_ds_id": 0,
            "img_ds_id": 1,
            "qosclass": "default-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["disktype"] == DiskType.CDROM
        assert v_info["spname"] == "one-img-1-123-0"
        assert v_info["legacy"] == "one-img-1-123-0"
        assert v_info["link"] == "/var/lib/one/datastores/0/123/disk.0"

    def test_prepare_vm_disk_volatile(self, mock_args):
        """Test preparing volatile disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": None,
            "clone": None,
            "type": "fs",
            "fs": "ext4",
            "sys_ds_id": 0,
            "img_ds_id": -1,
            "qosclass": "default-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["disktype"] == DiskType.VOLATILE
        assert v_info["volatile"] == "fs"
        assert v_info["fs"] == "ext4"
        assert v_info["spname"] == "one-sys-123-0"
        assert v_info["legacy"] == "one-sys-123-0-raw"
        assert v_info["link"] == "/var/lib/one/datastores/0/123/disk.0"

    def test_get_vm_snapshots_single(self, mock_args):
        """Test getting VM snapshots - single snapshot"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.args.verbose = 10

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.TEMPLATE.keys.return_value = ["SNAPSHOT"]
        vm_mock.TEMPLATE.get.return_value = {"HYPERVISOR_ID": "snap1"}

        snaps = manager._get_vm_snapshots(vm_mock)
        assert snaps == ["snap1"]

    def test_get_vm_snapshots_multiple(self, mock_args):
        """Test getting VM snapshots - multiple snapshots"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.TEMPLATE.keys.return_value = ["SNAPSHOT"]
        vm_mock.TEMPLATE.get.return_value = [
            {"HYPERVISOR_ID": "snap1"},
            {"HYPERVISOR_ID": "snap2"}
        ]

        snaps = manager._get_vm_snapshots(vm_mock)
        assert snaps == ["snap1", "snap2"]

    def test_get_vm_snapshots_none(self, mock_args):
        """Test getting VM snapshots when none exist"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.TEMPLATE.keys.return_value = []

        snaps = manager._get_vm_snapshots(vm_mock)
        assert snaps == []

    def test_get_disk_snapshots(self, mock_args):
        """Test getting disk snapshots"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.ID = 123

        snapshot_mock = Mock()
        snapshot_mock.DISK_ID = 0
        snapshot_mock.SNAPSHOT = [Mock(ID=1), Mock(ID=2)]

        vm_mock.SNAPSHOTS = [snapshot_mock]

        disk_snaps = manager._get_disk_snapshots(vm_mock)
        assert disk_snaps == {0: [1, 2]}

    def test_get_disk_snapshots_none(self, mock_args):
        """Test getting disk snapshots when none exist"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.SNAPSHOTS = []

        disk_snaps = manager._get_disk_snapshots(vm_mock)
        assert disk_snaps == {}

    def test_process_vm_system_disks_context(self, mock_args):
        """Test processing VM system disks - context disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.side_effect = lambda key: {
            "CONTEXT": {"DISK_ID": 1}
        }.get(key)
        vm_mock.USER_TEMPLATE.get.return_value = None

        vm_disks = manager._process_vm_system_disks(
            vm_mock, 1, [], {"disk.1": "/path/to/disk"}
        )

        expected_name = "one-sys-123-1"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.CONTEXT
        assert vm_disks[expected_name]["target"] == "/path/to/disk"

    def test_process_vm_system_disks_nvram(self, mock_args):
        """Test processing VM system disks - NVRAM"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.return_value = None
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "T_OS_LOADER": "OVMF",
            "SP_QOSCLASS": None,
            "VC_POLICY": None
        }.get(key, default)

        vm_disks = manager._process_vm_system_disks(vm_mock, 1, [], {})

        expected_name = "one-sys-123-NVRAM"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.NVRAM

    def test_process_vm_system_disks_checkpoint(self, mock_args):
        """Test processing VM system disks - checkpoint"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 4  # STOPPED
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.return_value = None
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "SP_QOSCLASS": None,
            "VC_POLICY": None,
            "T_OS_LOADER": None
        }.get(key, default)

        vm_disks = manager._process_vm_system_disks(vm_mock, 1, [], {})

        expected_name = "one-sys-123-rawcheckpoint"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.CHECKPOINT

    @patch.object(OpenNebulaManager, '_prepare_vm_disk')
    @patch.object(OpenNebulaManager, '_get_disk_symlink')
    @patch.object(OpenNebulaManager, '_get_vm_disks_list')
    def test_process_vm_disks(
        self, mock_get_disks_list, mock_get_symlink, mock_prepare_disk,
        mock_args
    ):
        """Test processing VM disks"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        mock_get_disks_list.return_value = [
            {"DISK_ID": 0, "IMAGE_ID": 1, "DATASTORE_ID": 2}
        ]
        mock_prepare_disk.return_value = {
            "spname": "one-img-1-123-0",
            "legacy": "one-img-1-123-0",
            "disktype": DiskType.NONPERSISTENT,
            "vm_id": 123,
            "disk_id": 0
        }
        mock_get_symlink.return_value = "/path/to/symlink"

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "SP_QOSCLASS": "vm-qos",
            "VC_POLICY": None
        }.get(key, default)

        vm_disks = manager._process_vm_disks(
            vm_mock, ["snap1"], {0: [1]}, {"disk.0": "/path/to/symlink"}
        )

        # Check main disk
        assert "one-img-1-123-0" in vm_disks
        # Check VM snapshot
        assert "one-img-1-123-0-snap1" in vm_disks
        # Check disk snapshot
        assert "one-img-1-123-0-snap1" in vm_disks

    def test_get_disk_symlink_found(self, mock_args):
        """Test getting disk symlink when found"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        links = {"disk.0": "/path/to/symlink"}
        result = manager._get_disk_symlink(0, links)
        assert result == "/path/to/symlink"

    def test_get_disk_symlink_not_found(self, mock_args):
        """Test getting disk symlink when not found"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        links = {"disk.1": "/path/to/symlink"}
        result = manager._get_disk_symlink(0, links)
        assert result is None

    def test_get_by_legacy_direct_match(self, mock_args):
        """Test getting by legacy name - direct match"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        test_dict = {
            "test-volume": {"legacy": "test-legacy", "data": "test"}
        }

        result = manager.get_by_legacy(test_dict, "test-volume")
        assert result == {"legacy": "test-legacy", "data": "test"}

    def test_get_by_legacy_legacy_match(self, mock_args):
        """Test getting by legacy name - legacy field match"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        test_dict = {
            "test-volume": {"legacy": "test-legacy", "data": "test"}
        }

        result = manager.get_by_legacy(test_dict, "test-legacy")
        assert result == {"legacy": "test-legacy", "data": "test"}

    def test_get_by_legacy_snapshot_match(self, mock_args):
        """Test getting by legacy name - snapshot match"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        test_dict = {
            "test-volume": {
                "legacy": "test-legacy",
                "snapshots": {
                    "test-snap": {
                        "legacy": "test-snap-legacy", "data": "snap-test"
                    }
                }
            }
        }

        result = manager.get_by_legacy(test_dict, "test-snap")
        assert result == {"legacy": "test-snap-legacy", "data": "snap-test"}

    def test_get_by_legacy_not_found(self, mock_args):
        """Test getting by legacy name - not found"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        test_dict = {
            "test-volume": {"legacy": "test-legacy", "data": "test"}
        }

        result = manager.get_by_legacy(test_dict, "not-found")
        assert result is None

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_ds_images(
        self, mock_run, mock_pyone, mock_args, mock_ssh_manager, mock_pyone_api
    ):
        """Test datastore images initialization"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n"

        mock_pyone.OneServer.return_value = mock_pyone_api

        manager = OpenNebulaManager(mock_args, mock_ssh_manager)

        # Check that image was processed
        expected_name = "one-img-1"
        assert expected_name in manager.ds_images
        assert manager.ds_images[expected_name]["image_id"] == 1
        assert manager.ds_images[expected_name]["imagetype"] == ImageType(0)
        assert manager.ds_images[expected_name]["disktype"] == DiskType(1)

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    @patch.object(OpenNebulaManager, '_host_symlinks')
    @patch.object(OpenNebulaManager, '_get_vm_snapshots')
    @patch.object(OpenNebulaManager, '_get_disk_snapshots')
    @patch.object(OpenNebulaManager, '_process_vm_disks')
    @patch.object(OpenNebulaManager, '_process_vm_system_disks')
    def test_get_vm_disks(
        self, mock_system_disks, mock_process_disks, mock_disk_snaps,
        mock_vm_snaps, mock_host_symlinks, mock_run, mock_pyone,
        mock_args, mock_ssh_manager, mock_pyone_api
    ):
        """Test getting VM disks"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n"

        mock_pyone.OneServer.return_value = mock_pyone_api
        mock_host_symlinks.return_value = {}
        mock_vm_snaps.return_value = []
        mock_disk_snaps.return_value = {}
        mock_process_disks.return_value = {"disk1": {"data": "test"}}
        mock_system_disks.return_value = {"sys1": {"data": "test"}}

        manager = OpenNebulaManager(mock_args, mock_ssh_manager)
        assert manager is not None

        # Verify methods were called
        mock_host_symlinks.assert_called()
        mock_vm_snaps.assert_called()
        mock_disk_snaps.assert_called()
        mock_process_disks.assert_called()
        mock_system_disks.assert_called()


class TestQosClassSelector:
    """Test QoS class selector logic"""

    def test_qosclass_persistent_disk_qosclass(self, mock_args):
        """Test QoS class selection for persistent disk with disk QoS"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }

        result = manager._qosclass_selector(
            disktype=DiskType.PERSISTENT,
            disk_id=0,
            img_qosclass="img-qos",
            vm_qosclass="vm-qos;0:disk0-qos;1:disk1-qos",
            img_ds_id=2,
            sys_ds_id=1
        )

        assert result == "disk0-qos"

    def test_qosclass_persistent_img_qosclass(self, mock_args):
        """Test QoS class selection for persistent disk with image QoS"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }

        result = manager._qosclass_selector(
            disktype=DiskType.PERSISTENT,
            disk_id=0,
            img_qosclass="img-qos",
            vm_qosclass="vm-qos",
            img_ds_id=2,
            sys_ds_id=1
        )

        assert result == "img-qos"

    def test_qosclass_persistent_vm_qosclass(self, mock_args):
        """Test QoS class selection for persistent disk with VM QoS"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }

        result = manager._qosclass_selector(
            disktype=DiskType.PERSISTENT,
            disk_id=0,
            img_qosclass=None,
            vm_qosclass="vm-qos",
            img_ds_id=2,
            sys_ds_id=1
        )

        assert result == "vm-qos"

    def test_qosclass_volatile_priority(self, mock_args):
        """Test QoS class selection priority for volatile disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }

        result = manager._qosclass_selector(
            disktype=DiskType.VOLATILE,
            disk_id=0,
            img_qosclass=None,
            vm_qosclass="vm-qos;0:disk0-qos",
            img_ds_id=2,
            sys_ds_id=1
        )

        # For volatile, order is: disk_qosclass, vm_qosclass,
        # sys_ds_qosclass, img_ds_qosclass
        assert result == "disk0-qos"

    def test_qosclass_cdrom_vm_qosclass(self, mock_args):
        """Test QoS class selection for CDROM disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
        }

        result = manager._qosclass_selector(
            disktype=DiskType.CDROM,
            disk_id=0,
            img_qosclass=None,
            vm_qosclass="vm-qos",
            img_ds_id=None,
            sys_ds_id=1
        )

        assert result == "vm-qos"

    def test_qosclass_nvram_vm_qosclass(self, mock_args):
        """Test QoS class selection for NVRAM disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
        }

        result = manager._qosclass_selector(
            disktype=DiskType.NVRAM,
            disk_id=None,
            img_qosclass=None,
            vm_qosclass="vm-qos",
            img_ds_id=None,
            sys_ds_id=1
        )

        # For NVRAM, order is: vm_qosclass, sys_ds_qosclass
        assert result == "vm-qos"

    def test_qosclass_default_fallback(self, mock_args):
        """Test QoS class fallback to default"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}

        result = manager._qosclass_selector(
            disktype=DiskType.VOLATILE,
            disk_id=0,
            img_qosclass=None,
            vm_qosclass=None,
            img_ds_id=None,
            sys_ds_id=None
        )

        assert result == "default-qos"

    def test_qosclass_parse_perdisk_format(self, mock_args):
        """Test parsing per-disk QoS class format"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {}

        # Test with disk_id=1
        result = manager._qosclass_selector(
            disktype=DiskType.PERSISTENT,
            disk_id=1,
            img_qosclass=None,
            vm_qosclass="default-vm-qos;0:disk0-qos;1:disk1-qos;2:disk2-qos",
            img_ds_id=None,
            sys_ds_id=None
        )

        assert result == "disk1-qos"

    def test_qosclass_sys_ds_priority(self, mock_args):
        """Test QoS class priority for system datastore"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
        }

        result = manager._qosclass_selector(
            disktype=DiskType.CONTEXT,
            disk_id=1,
            img_qosclass=None,
            vm_qosclass=None,
            img_ds_id=None,
            sys_ds_id=1
        )

        assert result == "sys-ds-qos"


class TestInitDatastores:
    """Test datastore initialization"""

    @patch('storpool_kvchk.managers.one_manager.pyone')
    @patch('subprocess.run')
    def test_init_datastores(
        self, mock_run, mock_pyone, mock_args, mock_ssh_manager, mock_pyone_api
    ):
        """Test datastores initialization with QoS class"""
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = b"123\n"

        mock_pyone.OneServer.return_value = mock_pyone_api

        manager = OpenNebulaManager(mock_args, mock_ssh_manager)

        # Check that datastore was processed
        assert 1 in manager.one_datastores
        assert manager.one_datastores[1]["name"] == "test-ds"
        assert manager.one_datastores[1]["qosclass"] == "ds-qos"
        assert manager.one_datastores[1]["ZDBG"] == "_init_datastores"


class TestHostSymlinks:
    """Test host symlinks retrieval"""

    def test_host_symlinks_running_vm(self, mock_args):
        """Test getting symlinks for running VM"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_hosts = {
            "test-host": {
                "links": {
                    1: {
                        123: {"disk.0": "/tmp/storpool-byid/a.bc.def"}
                    }
                }
            }
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3  # ACTIVE
        vm_mock.LCM_STATE = 3  # RUNNING
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]

        links = manager._host_symlinks(vm_mock)

        assert links == {"disk.0": "/tmp/storpool-byid/a.bc.def"}

    def test_host_symlinks_poweroff_vm(self, mock_args):
        """Test getting symlinks for powered off VM"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_hosts = {
            "test-host": {
                "links": {
                    1: {
                        123: {"disk.0": "/tmp/storpool-byid/a.bc.def"}
                    }
                }
            }
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 8  # POWEROFF
        vm_mock.LCM_STATE = 0  # LCM_INIT
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]

        links = manager._host_symlinks(vm_mock)

        assert links == {"disk.0": "/tmp/storpool-byid/a.bc.def"}

    def test_host_symlinks_no_host_data(self, mock_args):
        """Test getting symlinks when host not in hosts data"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_hosts = {}

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.LCM_STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [
            Mock(DS_ID=1, HOSTNAME="unknown-host")
        ]

        links = manager._host_symlinks(vm_mock)

        assert links == {}

    def test_host_symlinks_wrong_vm_state(self, mock_args):
        """Test getting symlinks for VM in wrong state"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_hosts = {
            "test-host": {
                "links": {
                    1: {
                        123: {"disk.0": "/tmp/storpool-byid/a.bc.def"}
                    }
                }
            }
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 4  # STOPPED
        vm_mock.LCM_STATE = 0
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]

        links = manager._host_symlinks(vm_mock)

        assert links == {}

    def test_host_symlinks_no_links_in_host(self, mock_args):
        """Test getting symlinks when host has no links data"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_hosts = {
            "test-host": {
                "name": "test-host"
            }
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.LCM_STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]

        links = manager._host_symlinks(vm_mock)

        assert links == {}


class TestGetVMDisksList:
    """Test VM disks list retrieval"""

    def test_get_vm_disks_list_single(self, mock_args):
        """Test getting VM disks list with single disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.TEMPLATE.get.return_value = {"DISK_ID": 0, "IMAGE_ID": 1}

        disks = manager._get_vm_disks_list(vm_mock)

        assert disks == [{"DISK_ID": 0, "IMAGE_ID": 1}]

    def test_get_vm_disks_list_multiple(self, mock_args):
        """Test getting VM disks list with multiple disks"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        vm_mock = Mock()
        vm_mock.TEMPLATE.get.return_value = [
            {"DISK_ID": 0, "IMAGE_ID": 1},
            {"DISK_ID": 1, "IMAGE_ID": 2}
        ]

        disks = manager._get_vm_disks_list(vm_mock)

        assert len(disks) == 2
        assert disks[0]["DISK_ID"] == 0
        assert disks[1]["DISK_ID"] == 1


class TestPrepareVMDiskWithQoS:
    """Test VM disk preparation with QoS class"""

    def test_prepare_vm_disk_with_qosclass(self, mock_args):
        """Test preparing VM disk with QoS class"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": None,
            "clone": None,
            "type": "fs",
            "fs": "ext4",
            "sys_ds_id": 1,
            "img_ds_id": 2,
            "qosclass": "vm-qos",
            "vc-policy": "vc-policy-1"
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["vm_id"] == 123
        assert v_info["disk_id"] == 0
        assert v_info["disktype"] == DiskType.VOLATILE
        assert v_info["qosclass"] == "vm-qos"
        assert v_info["vc-policy"] == "vc-policy-1"

    def test_prepare_vm_disk_with_perdisk_qosclass(self, mock_args):
        """Test preparing VM disk with per-disk QoS class"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
        }
        manager.ds_images = {}

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": None,
            "clone": None,
            "type": "fs",
            "fs": "",
            "sys_ds_id": 1,
            "img_ds_id": -1,
            "qosclass": "vm-qos;0:disk0-specific-qos;1:disk1-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["qosclass"] == "disk0-specific-qos"

    def test_prepare_vm_disk_with_img_qosclass(self, mock_args):
        """Test preparing VM disk with image QoS class"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"},
            2: {"qosclass": "img-ds-qos"}
        }
        manager.ds_images = {
            "one-img-1": {"qosclass": "image-specific-qos"}
        }

        vdata = {
            "one_px": "one",
            "vm_id": 123,
            "disk_id": 0,
            "image_id": 1,
            "clone": "NO",
            "type": "BLOCK",
            "fs": "",
            "sys_ds_id": 1,
            "img_ds_id": 2,
            "qosclass": "vm-qos",
            "vc-policy": None
        }

        v_info = manager._prepare_vm_disk(vdata)

        assert v_info["disktype"] == DiskType.PERSISTENT
        assert v_info["qosclass"] == "image-specific-qos"


class TestProcessVMSystemDisksUpdated:
    """Test VM system disks processing with updated code"""

    def test_process_vm_system_disks_context_with_qos(self, mock_args):
        """Test processing VM context disk with QoS class"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.side_effect = lambda key: {
            "CONTEXT": {"DISK_ID": 1}
        }.get(key)
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "SP_QOSCLASS": "vm-specific-qos",
            "VC_POLICY": "vc-policy-1",
            "T_OS_LOADER": None
        }.get(key, default)

        vm_disks = manager._process_vm_system_disks(
            vm_mock, 1, [], {"disk.1": "/path/to/disk"}
        )

        expected_name = "one-sys-123-1"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.CONTEXT
        assert vm_disks[expected_name]["qosclass"] == "vm-specific-qos"
        assert vm_disks[expected_name]["vc-policy"] == "vc-policy-1"
        assert vm_disks[expected_name]["target"] == "/path/to/disk"

    def test_process_vm_system_disks_nvram_with_snapshots(self, mock_args):
        """Test processing VM NVRAM with snapshots"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.STATE = 3
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.return_value = None
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "T_OS_LOADER": "OVMF",
            "SP_QOSCLASS": "vm-qos",
            "VC_POLICY": "vc-policy-1"
        }.get(key, default)

        vm_disks = manager._process_vm_system_disks(
            vm_mock, 1, ["snap1", "snap2"], {}
        )

        expected_name = "one-sys-123-NVRAM"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.NVRAM
        # Check that snapshots don't have qosclass and vc-policy
        assert "snap1" in vm_disks
        assert "qosclass" not in vm_disks["snap1"]
        assert "vc-policy" not in vm_disks["snap1"]

    def test_process_vm_system_disks_checkpoint_with_qos(self, mock_args):
        """Test processing VM checkpoint disk"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args
        manager.one_datastores = {
            1: {"qosclass": "sys-ds-qos"}
        }

        vm_mock = Mock()
        vm_mock.ID = 456
        vm_mock.STATE = 5  # SUSPENDED
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(HOSTNAME="test-host")]
        vm_mock.TEMPLATE.get.return_value = None
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "SP_QOSCLASS": "vm-qos",
            "VC_POLICY": "vc-policy-1",
            "T_OS_LOADER": None
        }.get(key, default)

        vm_disks = manager._process_vm_system_disks(
            vm_mock, 1, [], {}
        )

        expected_name = "one-sys-456-rawcheckpoint"
        assert expected_name in vm_disks
        assert vm_disks[expected_name]["disktype"] == DiskType.CHECKPOINT
        assert vm_disks[expected_name]["vc-policy"] == "vc-policy-1"


class TestProcessVMDisksUpdated:
    """Test VM disks processing with updated code"""

    @patch.object(OpenNebulaManager, '_prepare_vm_disk')
    @patch.object(OpenNebulaManager, '_get_disk_symlink')
    @patch.object(OpenNebulaManager, '_get_vm_disks_list')
    def test_process_vm_disks_with_qos(
        self, mock_get_disks_list, mock_get_symlink, mock_prepare_disk,
        mock_args
    ):
        """Test processing VM disks with QoS class"""
        manager = OpenNebulaManager.__new__(OpenNebulaManager)
        manager.args = mock_args

        mock_get_disks_list.return_value = [
            {"DISK_ID": 0, "IMAGE_ID": 1, "DATASTORE_ID": 2}
        ]
        mock_prepare_disk.return_value = {
            "spname": "one-img-1-123-0",
            "legacy": "one-img-1-123-0",
            "disktype": DiskType.NONPERSISTENT,
            "vm_id": 123,
            "disk_id": 0,
            "qosclass": "disk-qos",
            "vc-policy": "vc-policy-1"
        }
        mock_get_symlink.return_value = "/path/to/symlink"

        vm_mock = Mock()
        vm_mock.ID = 123
        vm_mock.HISTORY_RECORDS.HISTORY = [Mock(DS_ID=1, HOSTNAME="test-host")]
        vm_mock.USER_TEMPLATE.get.side_effect = lambda key, default=None: {
            "SP_QOSCLASS": "vm-qos",
            "VC_POLICY": "vc-policy-1"
        }.get(key, default)

        vm_disks = manager._process_vm_disks(
            vm_mock, ["snap1"], {0: [1]}, {"disk.0": "/path/to/symlink"}
        )

        # Check main disk has qosclass and vc-policy
        assert "one-img-1-123-0" in vm_disks
        assert vm_disks["one-img-1-123-0"]["qosclass"] == "disk-qos"
        assert vm_disks["one-img-1-123-0"]["vc-policy"] == "vc-policy-1"

        # Check VM snapshot doesn't have qosclass and vc-policy
        assert "one-img-1-123-0-snap1" in vm_disks
        assert "qosclass" not in vm_disks["one-img-1-123-0-snap1"]
        assert "vc-policy" not in vm_disks["one-img-1-123-0-snap1"]

        # Check disk snapshot doesn't have qosclass and vc-policy
        assert "one-img-1-123-0-snap1" in vm_disks
        assert "qosclass" not in vm_disks["one-img-1-123-0-snap1"]
        assert "vc-policy" not in vm_disks["one-img-1-123-0-snap1"]
