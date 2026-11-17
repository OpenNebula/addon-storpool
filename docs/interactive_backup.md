# Interactive backups (OneBEX)

Interactive backups let a third-party backup application (Veeam) read the
disks of a VM through the OneBEX service of OpenNebula. The addon provides the
StorPool side: a snapshot of each disk and an exporter that serves it from the
hypervisor.

**Technology Preview.** Interactive backups of StorPool disks depend on an
OpenNebula change that is merged upstream but is not in an OpenNebula release
yet: commit 4ef465ca16, "Support interactive backups for third party storage
drivers". The feature is expected to work from the first OpenNebula release
that includes that change. Releases without it (7.4.1 and older) do not run an
interactive backup of a StorPool disk; normal backups are not affected.

Restores through `onebex://` into a StorPool image datastore work from
OpenNebula 7.4.

## Setup

1. `TM_MAD_CONF` of the `storpool` driver in `/etc/one/oned.conf` carries
   `INTERACTIVE_BACKUP = "yes"` (`AUTOCONF=1 bash install.sh` adds it; see
   [Installation](installation.md)). OpenNebula releases without the feature
   ignore the attribute.
2. `install.sh` installs the exporter `onebex/exporters/storpool.rb` when
   `/var/lib/one/remotes/onebex/exporters` exists; `onehost sync --force`
   copies it to the hypervisors.
3. The backup application needs a backup datastore with
   `DS_MAD=interactive`, set up as the OpenNebula documentation describes.
4. TCP port 13014 on the hypervisors must be reachable from the backup
   proxies and from nothing else: the OneBEX service on that port does not
   authenticate.

## How it works

OpenNebula runs an interactive backup when the VM has
`BACKUP_CONFIG=[INTERACTIVE="YES"]`. The addon then:

1. takes a StorPool snapshot of every disk of the VM and attaches it
   read-only to the VM host;
2. reports the size of the backup as the sum of the virtual sizes of the
   disks;
3. serves each snapshot on TCP 13014 of the VM host through the StorPool
   exporter, as one extent covering the whole disk;
4. detaches and deletes the snapshots when the backup application
   finalizes or cancels the backup.

## Limitations

* Full backups only. StorPool has no changed-block interface, so every
  interactive backup reads the whole disk; `MODE=INCREMENT` is refused.
* The size OpenNebula records is the virtual size of the disks, every
  backup, however much of a disk is written.
* A VM with non-StorPool disks is refused (`BACKUP_SKIP_OTHER_DISKS` is not
  honoured), otherwise the backup application would record a partial VM.
* The vTPM state is not exported. A restored VM has no TPM state.
* `LAST_BRIDGE` is ignored: the datastore driver, the cancel and the backup
  application all address the VM host.
* The backup snapshot stays attached to the hypervisor for the whole
  transfer and grows with the guest writes.
* A backup snapshot that could not be detached or deleted after the backup
  stays on the cluster and keeps growing. `kvchk` reports it as hanging when
  it is older than `--hanging-min-age` (3600 s by default) and the VM has
  left the BACKUP state or has a later backup snapshot.
* A restore through `onebex://` is staged in `/var/tmp` on the front-end
  (the raw upload and its qcow2 conversion) before the image is imported.
