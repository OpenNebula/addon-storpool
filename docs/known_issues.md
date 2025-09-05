# Known issues

## Recover -> delete-recreate fails on undeployed VM

The driver does a sanity check that the to-be-cloned volume is not available. But the `tm/delete` action is not called by OpenNebula when a VM is in "UNDEPLOYED" state.

Workaround: Re-run the delete-recreate request. It will pass because the VM is in `PROLOG_FAILURE` and OpenNebula will call the `tm/delete` script to do the cleanup before calling `tm/clone`.

## Changed naming convention for CDROM images

In release 19.03.2 the volume names of the attached CDROM images was changed. A separate volume with a unique name is created for each attachment. This could lead to errors when using restore with the alternate VM snapshot interface enabled.

The workaround is to manually create (or rename) a snapshot of the desired CDROM volume following the new naming convention. The migration to the new CDROM's volume naming convention is integrated so there is no manual operations needed.
