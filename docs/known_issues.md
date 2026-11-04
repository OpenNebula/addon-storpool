# Known issues

## Recover -> delete-recreate fails on undeployed VM

The driver does a sanity check that the to-be-cloned volume is not available. But the `tm/delete` action is not called by OpenNebula when a VM is in "UNDEPLOYED" state.

Workaround: Re-run the delete-recreate request. It will pass because the VM is in `PROLOG_FAILURE` and OpenNebula will call the `tm/delete` script to do the cleanup before calling `tm/clone`.

## Interactive (OneBEX) backups

* Full backups only. StorPool has no changed-block interface, so every interactive backup reads the whole disk; `MODE=INCREMENT` is refused.
* `BACKUP_SKIP_OTHER_DISKS` is not honoured: a VM with non-StorPool disks is refused, otherwise the backup application would record a partial VM.
* The vTPM state is not exported, as with the upstream interactive drivers. A restored VM has no TPM state.
* `LAST_BRIDGE` is ignored: the datastore driver, the cancel and the backup application all address the VM host.
* The backup snapshot stays attached read-only to the hypervisor for the whole transfer and grows with the guest writes. The hypervisor serves the data on TCP 13014 without authentication, so the port must be firewalled to the backup proxies.
* A backup snapshot that postbackup failed to detach or delete stays on the cluster and keeps growing. `kvchk` reports it as hanging once the VM has left the BACKUP state and the snapshot is older than `--hanging-min-age` (3600 s by default); it is never re-pointed at the live disk.
* A restore through `onebex://` is staged in `/var/tmp` on the front-end (the raw upload and its qcow2 conversion) before the image is imported.
* OpenNebula 7.4 and older never back up a StorPool disk this way: the 7.4 API refuses the request (`Disk does not support interactive backup`), 7.2 and older drop `INTERACTIVE` from `BACKUP_CONFIG`, the 7.4 OneBEX server loads only its own exporters, and `INTERACTIVE_BACKUP` in `TM_MAD_CONF` is ignored. Normal backups are unchanged. Backups through the backup application need an oned with commit 4ef465ca16.
* OpenNebula 7.4 already restores through `onebex://` into a StorPool image datastore (its downloader and writer exist and the oVirt API emulator does not check the target `TM_MAD`); verified on 7.4.1.
