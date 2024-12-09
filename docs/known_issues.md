## Known issues

### Recover -> delete-recreate fails on undeployed VM

The driver do a sanity check that the to-be-cloned volume is not available. But the `tm/delete` action is not called by OpenNebula when a VM is in "UNDEPLOYED" state.

Workaround: Re-run the delete-recreate request. It will pass becacuse the VM is in PROLOG_FAILURE and OpenNebula will call the `tm/delete` script to do the cleanup before calling `tm/clone`.

