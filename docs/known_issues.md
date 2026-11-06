# Known issues

## Recover -> delete-recreate fails on undeployed VM

The driver does a sanity check that the to-be-cloned volume is not available. But the `tm/delete` action is not called by OpenNebula when a VM is in "UNDEPLOYED" state.

Workaround: Re-run the delete-recreate request. It will pass because the VM is in `PROLOG_FAILURE` and OpenNebula will call the `tm/delete` script to do the cleanup before calling `tm/clone`.

## StorPool backup datastore

* A remote site deletes the copy of a removed backup only when its
  `remoteBridge` entry for the source cluster carries `minimumDeleteDelay`;
  without it `SnapshotsRemoteUnexport` succeeds and the copy stays on the
  remote cluster, where the remote operator has to remove it.
* A snapshot pulled from a remote site (`SnapshotFromRemote`) is not visible
  to the `MultiCluster/...` API calls (`objectDoesNotExist`) although it is
  listed and usable through the plain calls; the restore paths use plain calls
  for it. A second pull of the same `remoteId` while the first pulled snapshot
  exists is refused (`objectExists ... already imported as <name>`); the
  addon reuses the existing one.
* The UEFI vars file of a VM created by `oneimage restore` from a backup is
  not restored.
