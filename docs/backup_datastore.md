# StorPool backup datastore

A backup datastore with `DS_MAD=storpool` keeps OpenNebula backups as StorPool
snapshots instead of qcow2 files: a backup is one atomic group snapshot of the
VM's disks, the NVRAM volume when the VM has one, and a small service
volume with the backup's `vm.xml` (and the vTPM state and the UEFI vars
file when the VM has them), kept on the cluster
(*local mode*) or sent to another StorPool cluster or location with the
StorPool multi-site transfer (*remote mode*). Nothing is converted or copied
through the hypervisor, and a restore is a clone of the snapshot.

## Create the datastore

```
NAME=storpool_backup
TYPE=BACKUP_DS
DS_MAD=storpool
DISK_TYPE=BLOCK
DATASTORE_CAPACITY_CHECK=NO
# remote mode: a location name, or a cluster name when the location has several clusters
#SP_BACKUP_LOCATION=devA3
#SP_BACKUP_TIMEOUT=0
#SP_BACKUP_REMOTE_DELETE=YES
```

`onedatastore create` with that template. `DISK_TYPE=BLOCK` satisfies the
shared `REQUIRED_ATTRS` of the `storpool` driver (oned stores `FILE`). When
the StorPool image datastore carries `SP_API_HTTP_HOST`, `SP_API_HTTP_PORT`,
`SP_AUTH_TOKEN` or `SP_CLUSTER_ID`, copy them to the backup datastore; without
them the drivers read `storpool.conf` on the front-end, as for every datastore.

| attribute | meaning |
|---|---|
| `SP_BACKUP_LOCATION` | empty: local mode. A StorPool location name (`devA3`), or a cluster name (`devA1-cl2`) when the location has more than one cluster, as `VolumeBackup` takes it. |
| `SP_BACKUP_TIMEOUT` | seconds the `backup` action waits for the remote transfer; `0` (default) waits until it completes or the backup is cancelled. |
| `SP_BACKUP_REMOTE_DELETE` | `YES` (default): deleting a backup asks the remote site to delete its copy (`SnapshotsRemoteUnexport` with `deleteAfter`). `NO`: the copy is only unexported. |
| `DATASTORE_CAPACITY_CHECK=NO` | required: the `monitor` reports `USED_MB=0 TOTAL_MB=0 FREE_MB=0`, the snapshots are charged on the templates of the image and system datastores (`storpool template status` is the authoritative view). Per-user backup quotas work on the image `SIZE`. |

Remote mode relies on the StorPool multi-site (or multi-cluster) link between
the two clusters, which must be set up before the datastore is used. For the
removal of backups to reach the other side, the remote cluster has to accept
deferred deletions from this cluster: there, the bridge records of this
cluster must be registered with a minimum deletion delay (`minimumDeleteDelay`)
and deferred snapshot deletion must be enabled. Without that the remote side
silently ignores the delete request and the copies of a removed backup stay on
the remote cluster. The delay set there is a floor: a copy outlives its
OpenNebula image by at least that long. See
[Remote deferred deletion](https://kb.storpool.com/admin-guide/multi/remote-deferred-deletion.html)
and the [minimum deletion delay](https://kb.storpool.com/reference/cli/remote-bridge.html#minimum-deletion-delay)
of the remote bridge in the StorPool knowledge base.

## What a backup is

`onevm backup <vm> -d <backup ds>`, live or in POWEROFF, in `FULL` or
`INCREMENT` mode (see below). The addon's `prebackup`:

1. builds a *service volume* `<ONE_PX>-sys-<vm>-SVC-<epoch>`
   holding a tar with the backup's `vm.xml` and, when the VM has them, the
   vTPM dump (`disk.tpm.0`, the `vtpm_setup backup` output as upstream makes
   it) and the file NVRAM (`OS/FIRMWARE` is a path or `UEFI`, or
   `T_OS_NVRAM` in file mode) with its path;
2. takes one `VolumesGroupSnapshot` (local mode) or `VolumesGroupBackup`
   (remote mode) of the backup set: the disks oned lists, the NVRAM volume of a
   `T_OS_NVRAM=storpool` VM and the service volume, under the `FS_FREEZE`
   bracket of the backup configuration;
3. deletes the service volume (its snapshot keeps the data).

The datastore `backup` action waits for the remote transfer in remote mode,
copies `vm.xml` and `svc.tar` under `<BASE_PATH>/<vm>/<epoch>/` and registers
the image with `SOURCE`:

```
<location|local>/<vm_id>/<epoch>/<disk_id>=<id>[/<disk_id>=<id>...][/nvram=<id>][/svc=<id>]
```

`<id>` is the local snapshot's globalId (local mode) or the `remoteId` of the
copy on the target (remote mode, listed by `SnapshotsRemoteList` on the source
cluster); `<location>` is the location name of the copy (`devA1` for a cluster
`devA1-cl2`). The image `SIZE` is the sum of the disks' sizes, `FORMAT=raw`.

`KEEP_LAST` works through the datastore `rm` action in `FULL` mode and through
`increment_flatten` in `INCREMENT` mode, both removing whole backups: local
mode detaches and deletes the snapshots; a same-location cluster target gets
the forwarded `SnapshotUnexport` + `SnapshotDelete` of each copy; a remote
location gets `SnapshotsRemoteUnexport`. **A remote site deletes the copy only
when its `remoteBridge` entry for the source cluster has `minimumDeleteDelay`
set**; otherwise the copy stays on the remote cluster after the unexport and
must be removed there (`kvchk` of the remote OpenNebula instance does not see
it).

## FULL and INCREMENT

A StorPool snapshot holds only the blocks changed since the previous one, and
a restore clones whichever snapshot is asked for, so both OpenNebula backup
modes take the same group snapshot and store and transfer the same data (the
multi-site transfer deduplicates against the copies already on the target).
The modes differ in OpenNebula's bookkeeping:

* `MODE=FULL` (the default): one backup image per backup, `KEEP_LAST`
  deletes the oldest images.
* `MODE=INCREMENT`: one backup image per chain. The first backup creates the
  image with increment 0, every later backup adds an increment to the same
  image; `oneimage show` lists them under `BACKUP INCREMENTS`, each with its
  own manifest as `SOURCE` (the image `SOURCE` is increment 0's). An
  increment is a complete point in time: `onevm restore --increment N` and
  `oneimage restore --increment N` clone that increment's snapshots, without
  `--increment` the last one's. `KEEP_LAST` runs the datastore
  `increment_flatten`, which deletes the backups of the oldest increments
  beyond `KEEP_LAST` (StorPool merges their blocks into the next kept
  snapshot) and reports the remaining chain, whose first increment becomes
  the `FULL` one. Every increment reports the sum of the disks' sizes, as a
  `FULL` backup does, so the image `SIZE` (and the datastore quota) grows by
  the VM size per increment while StorPool keeps the changed blocks only.

The rules of `MODE=INCREMENT` are OpenNebula's: a VM with VM snapshots cannot
use it; an increment always goes to the datastore of its chain (`-d` of
`onevm backup` is ignored unless `--reset`); the chain is reset, and the next
backup starts a new image, by `onevm backup --reset`, a change of `MODE`,
`DISK_IDS` or `BACKUP_VOLATILE`, the attach or detach of a backed-up disk, an
in-place restore and the deletion of the chain image; a backup is refused
while a flatten is running (`ACTIVE_FLATTEN`). `INCREMENT_MODE` (`CBT` or
`SNAPSHOT`) has no meaning for StorPool disks. Interactive (OneBEX) backups
stay `FULL` only.

## The etcd index

`prebackup` records the backup in the etcd KV store under its own prefix
`/bkName/<ONE_PX>-bak-<vm>-<epoch>[-<disk_id>]` (the per-disk snapshot ids and
one `mode=<local|remote> svc=<uid|->` record); the `backup` action and
`postbackup` read it to find the backup in progress and fall back to the
snapshot tags when it is absent. `BACKUP_KV_INDEX=0` in `addon-storpoolrc`
turns the records off (tags only). The records of a removed backup go with it;
`kvchk` reports stale ones.

Tunables of `addon-storpoolrc` besides `BACKUP_KV_INDEX`: `BACKUP_WAIT_SLEEP`
(seconds between polls of the transfer, 3), `BACKUP_DROP_WAIT` (seconds
postbackup, the sweep and `rm` wait for a copy to be listed, 30),
`BACKUP_PULL_GRACE` (seconds a pulled snapshot may stay unlisted after
`SnapshotFromRemote`, 120), `SP_BACKUP_DELETE_AFTER` (the `deleteAfter`
of the remote unexport, 60).

## Restores

**In place** (`onevm restore <vm> <image> [--disk-id N] [--increment N]`, VM in
POWEROFF): each disk gets a new volume created from the backup snapshot
(`VolumeCreate` with
`parent`), swapped in as the file-based path does; the NVRAM volume the same
way; the service tar is taken from the front-end copy (or from the service
snapshot when that is gone) and its vTPM state is written to the SWTPM volume
and the VM directory, the NVRAM file back to its path. In remote mode the
snapshot is pulled first (`SnapshotFromRemote`, on the restored volume's
template or the `MgmtConfig` default) and the pulled snapshot is deleted after
the clone.

**New images** (`oneimage restore <image> -d <storpool image ds> [--increment N]`):
one image
per disk with `PATH=SPSNAPSHOT:~<id>` (local) or `SPREMOTE:<location>:~<id>`
(remote, pulled by the image datastore `cp`) and a VM template; the vTPM state
goes into the template as `TPM_STATE`, as upstream does. The destination must
be a StorPool image datastore. The UEFI vars of a VM created this way are not
restored (a new VM gets fresh vars).

A restored volume keeps the backup snapshot as its parent and reads the blocks
it has not rewritten through it until the backup is deleted (StorPool then
merges the snapshot into its child).

## Front-end files and HA

`<BASE_PATH>/<vm>/<epoch>/` keeps `vm.xml` (needed by `oneimage restore`)
and `svc.tar`. On HA front-ends put `BASE_PATH` on shared or synced storage.
When the files are lost, `misc/svc_extract.sh` rebuilds them from the service
snapshot of a backup that has one.

## Cancel and failures

`onevm backup-cancel` sends TERM to the `prebackup` or the `backup` action;
`postbackup` then removes the snapshots of the backup in progress: local
snapshots, the transient exports and, in remote mode, the copies on the target
(a same-location cluster directly, a remote location with the unexport call,
subject to `minimumDeleteDelay` as above). The failure of any step runs the
same cleanup. `kvchk` reports what is left: kept snapshots without a backup
image (after `--hanging-min-age`), service volumes, stale `/bkName/` records.

## Templates

Snapshots keep the placement of their volumes, so nothing changes for
per-datastore templates or a default-template-only setup
(`NO_VOLUME_TEMPLATE=1`). A pull from a remote site needs a template: the
restored volume's, else the `MgmtConfig` default template of the cluster (a
`no template for the pull` error otherwise).

## Limitations

* An increment is charged the full size of the disks, not the changed blocks.
* Non-StorPool disks are refused (`BACKUP_SKIP_OTHER_DISKS` is not honoured).
* Remote mode sends every backup through the group transfer; a cancel removes
  the local side at once but a copy that was in flight may complete on the
  target before it is removed.
* A remote site without `minimumDeleteDelay` on its bridge entry keeps the
  copies of deleted backups.
* The UEFI vars file of a VM created by `oneimage restore` is not restored.
* A pulled snapshot (`SnapshotFromRemote`) is not visible through the
  `MultiCluster` API calls; the addon uses plain calls for it.
