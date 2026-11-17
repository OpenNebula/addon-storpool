# StorPool backup datastore

A backup datastore with `DS_MAD=storpool` keeps OpenNebula backups as StorPool
snapshots instead of files. A backup is one atomic snapshot of all the VM's
disks, together with the VM's UEFI NVRAM, its vTPM state and its `vm.xml`.
The snapshots stay on the same StorPool cluster (*local mode*) or are sent to
another StorPool cluster or location (*remote mode*). Nothing is converted or
copied through the hypervisor, and a restore is a clone of the snapshot.

## Requirements

* All disks of a backed-up VM are on StorPool datastores. A VM with other
  disks is refused.
* Remote mode: the StorPool multi-site (or multi-cluster) link between the two
  clusters is set up. For deleted backups to be removed on the other side as
  well, the remote cluster must accept deferred deletions from this cluster:
  there, the bridge entry of this cluster needs a minimum deletion delay
  (`minimumDeleteDelay`) and deferred snapshot deletion must be enabled.
  Without that the remote cluster ignores the delete requests and keeps the
  copies of deleted backups. See
  [Remote deferred deletion](https://kb.storpool.com/admin-guide/multi/remote-deferred-deletion.html)
  and the [minimum deletion delay](https://kb.storpool.com/reference/cli/remote-bridge.html#minimum-deletion-delay)
  in the StorPool knowledge base.
* Remote mode restores: the cluster the VM is restored on copies the
  snapshots back onto the StorPool template of the restored volume, or onto
  its default template when the volume has none. One of them must exist on
  that cluster.
* `monitor_helper-sync` runs on the front-end (it is installed with the addon).
  The backup sizes and the datastore usage are read from its cache.
* HA front-ends: the backup datastore's `BASE_PATH` is on shared or synced
  storage (see *Front-end files*).

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

Create it with `onedatastore create <file>`. When the StorPool image
datastores carry `SP_API_HTTP_HOST`, `SP_API_HTTP_PORT`, `SP_AUTH_TOKEN` or
`SP_CLUSTER_ID`, copy them to the backup datastore; without them the driver
uses `storpool.conf` on the front-end, as for every StorPool datastore.

| attribute | meaning |
|---|---|
| `DISK_TYPE=BLOCK` | required by the `storpool` datastore driver. |
| `DATASTORE_CAPACITY_CHECK=NO` | required. The snapshots use the space of the StorPool templates of the VM disks, so the free space of the backup datastore must not accept or refuse a backup. Backup quotas still work on the backup size. |
| `SP_BACKUP_LOCATION` | empty: local mode. A StorPool location name (`devA3`), or a cluster name (`devA1-cl2`) when the location has more than one cluster: remote mode. |
| `SP_BACKUP_TIMEOUT` | seconds a backup waits for the remote transfer; `0` (default) waits until the transfer completes or the backup is cancelled. |
| `SP_BACKUP_REMOTE_DELETE` | `YES` (default): deleting a backup asks the remote cluster to delete its copy. `NO`: the copy is left on the remote cluster. |

## Back up

`onevm backup <vm> -d <backup datastore>`, or a backup job, with the VM running
or in POWEROFF. A backup of a running VM honours `FS_FREEZE` of the VM's
backup configuration.

Each backup contains:

* a snapshot of every backed-up disk;
* the UEFI NVRAM volume of a VM with `T_OS_NVRAM=storpool`;
* a small service snapshot with the VM's `vm.xml` and, when the VM has them,
  the vTPM state and the UEFI vars file.

All of them are taken in one atomic StorPool operation. In remote mode they
are sent to the target and the backup completes when the transfer does. The
front-end keeps a copy of `vm.xml` and of the service data (see *Front-end
files*).

### FULL and INCREMENT

A StorPool snapshot holds only the blocks changed since the previous one, so
both OpenNebula backup modes take the same snapshot and store and transfer
the same data (the remote transfer also skips what the target already has).
The modes differ in what OpenNebula records:

* `MODE=FULL` (the default): one backup image per backup.
* `MODE=INCREMENT`: one backup image per chain. The first backup creates the
  image with increment 0 and every later backup adds an increment to it;
  `oneimage show` lists them under `BACKUP INCREMENTS`. Every increment is a
  complete point in time: `onevm restore --increment N` and
  `oneimage restore --increment N` restore that increment, without
  `--increment` the last one.

The rules of `MODE=INCREMENT` are OpenNebula's: a VM with VM snapshots cannot
use it, an increment always goes to the datastore of its chain, and the chain
is reset (the next backup starts a new image) by `onevm backup --reset`, a
change of `MODE`, `DISK_IDS` or `BACKUP_VOLATILE`, the attach or detach of a
backed-up disk, an in-place restore and the deletion of the chain image.
`INCREMENT_MODE` (`CBT` or `SNAPSHOT`) has no meaning for StorPool disks.

### Retention

`KEEP_LAST` removes whole backups: in `FULL` mode the oldest images, in
`INCREMENT` mode the oldest increments of the chain, whose data StorPool
merges into the next kept snapshot. Deleting a backup image does the same.
In remote mode the copies on the target are deleted too, as long as the remote
cluster accepts deferred deletions (see *Requirements*); the remote cluster
keeps a copy for at least its `minimumDeleteDelay`.

## Restore

**In place** (`onevm restore <vm> <image> [--disk-id N] [--increment N]`, the
VM in POWEROFF): every restored disk is replaced by a new volume cloned from
the backup snapshot. The UEFI NVRAM and the vTPM state are restored too. In
remote mode the snapshots are first copied back from the target.

**New images** (`oneimage restore <image> -d <StorPool image datastore>
[--increment N]`): one image per disk and a VM template that carries the vTPM
state. The destination must be a StorPool image datastore. A VM created from
that template gets fresh UEFI vars.

A restored volume shares the blocks it has not rewritten with the backup
snapshot. Deleting the backup later does not affect the volume.

## Backup sizes and datastore usage

* **Backup size** (`oneimage show`, the backup quota): a `FULL` backup, and
  the first backup of an `INCREMENT` chain, is the data the VM's disks hold.
  A later increment in local mode is the data written since the previous
  backup. In remote mode every backup, increment or not, is the full data of
  the disks. The service snapshot is not counted.
* **Datastore usage** (`onedatastore show`): `USED_MB` is the space the kept
  backups take on the local cluster, or on the target cluster when
  `SP_BACKUP_LOCATION` names a cluster of the same multi-cluster; a remote
  location is not visible and the datastore shows zeros. `TOTAL_MB` and
  `FREE_MB` are the capacity of the StorPool pool the backups are kept in.

The figures come from the `monitor_helper-sync` cache, refreshed every 30
minutes by default (`SP_DEFAULT_SECONDS` in `monitor_helper-syncrc`). They
miss the writes since the last refresh, and an increment taken before the
cache has been refreshed since the previous backup is recorded as 0. A full
backup calls the StorPool API for the figures only when the cache is missing
or does not list a disk; increments, retention and the datastore monitor
never do. Which backup
schedules keep the sizes usable is in
[Backup size reporting](backup_size_reporting.md).

## Cancel and failures

`onevm backup-cancel` stops the backup and removes its snapshots, including
the copies already on a remote target (subject to the remote deletion, see
*Requirements*). A failed backup is cleaned up the same way. `kvchk` reports
anything left behind.

## Front-end files

The front-end keeps `vm.xml` (needed by `oneimage restore`) and the service
data of every backup under `<BASE_PATH>/<vm>/<epoch>/`. On HA front-ends put
`BASE_PATH` on shared or synced storage. When the files are lost,
`misc/svc_extract.sh` rebuilds them from the service snapshot of the backup.

## Configuration

Optional settings in `addon-storpoolrc`:

| variable | default | meaning |
|---|---|---|
| `BACKUP_KV_INDEX` | `1` | keep an index of the backups in the etcd KV store; `0` finds them from the StorPool snapshots only |
| `BACKUP_WAIT_SLEEP` | `3` | seconds between checks of a remote transfer |
| `BACKUP_DROP_WAIT` | `30` | seconds to wait for a remote copy to be listed before it is removed |
| `BACKUP_PULL_GRACE` | `120` | seconds to wait for a snapshot copied back from a remote target |
| `SP_BACKUP_DELETE_AFTER` | `60` | seconds the remote cluster is asked to wait before it deletes the copy of a deleted backup |

## Limitations

* VMs with non-StorPool disks are refused (`BACKUP_SKIP_OTHER_DISKS` is not
  honoured).
* The backup sizes and the datastore usage come from the `monitor_helper-sync`
  cache and miss the writes since its last refresh.
* A cancel in remote mode removes the local side at once, but a copy that was
  in flight may complete on the target before it is removed.
* A remote cluster without `minimumDeleteDelay` on the bridge entry of this
  cluster keeps the copies of deleted backups.
* The UEFI vars of a VM created by `oneimage restore` are not restored.
