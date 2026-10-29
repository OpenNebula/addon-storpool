"""Tests for the StorPool cluster configuration gate - every StorPool
datastore must refer to a registered StorPool cluster and location."""
import pytest
from unittest.mock import Mock, patch
from storpool_kvchk.processors.data_processing import DataProcessing  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.etcd_manager import etcdManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.storpool_manager import spManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.one_manager import oneManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.managers.ssh_manager import SshManager  # type: ignore[import-untyped] # noqa: E501
from storpool_kvchk.models.exceptions import ClusterConfigError  # type: ignore[import-untyped] # noqa: E501

LOCAL = "localhost"
REMOTE = "10.0.0.9"

CLUSTERS = {
    LOCAL: [
        {"id": "b", "location": "devA1", "name": "devA1-cl1"},
        {"id": "n", "location": "devA1", "name": "devA1-cl2"},
        {"id": "b", "location": "devA3", "name": "devA3-cl1"},
    ],
    REMOTE: [
        {"id": "c", "location": "devB1", "name": "devB1-cl1"},
    ],
}
LOCATIONS = {
    LOCAL: [
        {"id": "fir", "name": "devA1"},
        {"id": "njyf", "name": "devA3"},
    ],
    REMOTE: [
        {"id": "zq", "name": "devB1"},
    ],
}


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
    one_manager.one_hosts = {}
    one_manager.one_datastores = {}
    one_manager.one_vms = {}
    one_manager.frontend = {}
    one_manager.vm_ids = []

    with patch('storpool_kvchk.managers.storpool_manager.SPConfig'):
        sp_manager = spManager(mock_args)
    sp_manager.data = {}
    sp_manager.host_dsid = {}
    sp_manager.clusters = dict(CLUSTERS)
    sp_manager.locations = dict(LOCATIONS)
    sp_manager.local_cluster_id = "fir.b"

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


def _ds(processor, ds_id, name, tm_mad="storpool", host=LOCAL, **tmpl):
    entry = {
        "id": ds_id,
        "name": name,
        "tm_mad": tm_mad,
        "SP_API_HTTP_HOST": None if host == LOCAL else host,
        "SP_CLUSTER_ID": None,
        "SP_REMOTE_LOCATION": None,
    }
    entry.update(tmpl)
    processor.one.one_datastores[ds_id] = entry
    processor.sp.host_dsid[ds_id] = host
    return entry


class TestAnalyzeClusters:

    def test_registered_cluster_passes(self, processor):
        _ds(processor, 0, "system", SP_CLUSTER_ID="fir.b")
        _ds(processor, 1, "default", SP_CLUSTER_ID="fir.b",
            SP_REMOTE_LOCATION="fir.b")
        processor.analyze_clusters()

    def test_non_storpool_datastores_ignored(self, processor):
        _ds(processor, 2, "files", tm_mad="local", SP_CLUSTER_ID="bogus")
        _ds(processor, 100, "backups", tm_mad="-", SP_CLUSTER_ID="x.y")
        processor.analyze_clusters()

    def test_unknown_location_stops(self, processor):
        _ds(processor, 0, "system", SP_CLUSTER_ID="fir.b")
        _ds(processor, 1, "default", SP_CLUSTER_ID="xyz.b")
        with patch.object(processor, 'err') as mock_err:
            with pytest.raises(ClusterConfigError) as excinfo:
                processor.analyze_clusters()
        assert excinfo.value.problems == 1
        assert "1 datastore(s)" in str(excinfo.value)
        mock_err.assert_called_once()
        msg = mock_err.call_args[0][0]
        assert msg.startswith("datastore 1 (default) API localhost:")
        assert "location 'xyz'" in msg

    def test_unknown_cluster_stops(self, processor):
        _ds(processor, 1, "default", SP_CLUSTER_ID="fir.q")
        with pytest.raises(ClusterConfigError):
            processor.analyze_clusters()

    def test_every_bad_datastore_reported(self, processor):
        _ds(processor, 0, "system", SP_CLUSTER_ID="njyf.n")
        _ds(processor, 1, "default", SP_CLUSTER_ID="b")
        with patch.object(processor, 'err') as mock_err:
            with pytest.raises(ClusterConfigError) as excinfo:
                processor.analyze_clusters()
        assert excinfo.value.problems == 2
        assert mock_err.call_count == 2

    def test_remote_location_takes_precedence(self, processor):
        # monitor_helper-sync resolves SP_REMOTE_LOCATION first
        _ds(processor, 1, "default", SP_CLUSTER_ID="fir.b",
            SP_REMOTE_LOCATION="bad.id")
        with pytest.raises(ClusterConfigError):
            processor.analyze_clusters()

    def test_checked_against_the_datastore_api(self, processor):
        _ds(processor, 1, "default", host=REMOTE, SP_CLUSTER_ID="zq.c")
        processor.analyze_clusters()
        # a valid local id is unknown to the remote API
        _ds(processor, 3, "remote", host=REMOTE, SP_CLUSTER_ID="fir.b")
        with pytest.raises(ClusterConfigError):
            processor.analyze_clusters()

    def test_frontend_cluster_for_default_api(self, processor):
        # no id on the datastore, default API host: the frontend's
        # storpool.conf SP_CLUSTER_ID is what the monitor records
        _ds(processor, 0, "system")
        processor.analyze_clusters()
        processor.sp.local_cluster_id = "gone.x"
        with pytest.raises(ClusterConfigError):
            processor.analyze_clusters()

    def test_no_cluster_id_on_own_api_skipped(self, processor):
        # an SP_API_HTTP_HOST override without a cluster id has
        # nothing to validate
        _ds(processor, 1, "default", host=REMOTE)
        processor.sp.local_cluster_id = "gone.x"
        processor.analyze_clusters()
