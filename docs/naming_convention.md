# StorPool naming convention

Here you can find how OpenNebula datastores and images are mapped to StorPool Templates, Volumes, and Snapshots.

## Addon version

The addon uses the `YY.MM.R` versioning schema, where `YY` is the year of the release, `MM` is the month of the release, and `R` is the revision in the month.

## Datastore templates

Each datastore in OpenNebula has a StorPool template with the following format:
```bash
${ONE_PX}-ds-${DATASTORE_ID}
```

## Images

Images in OpenNebula are mapped to unnamed StorPool snapshots. For convenience and debugging purposes, tags are provided.

```
img=${ONE_PX}-img-${IMAGE_ID}
nloc=${ONE_PX}
virt=one
```

Please note that it is possible to have multiple volumes or snapshots with the same tags. The ones used by the OpenNebula driver are stored as key/value in the etcd service.

#### PERSISTENT images

When a persistent image is assigned to a VM, the StorPool snapshot is converted to a volume with the following tags:
```bash
img=${ONE_PX}-img-${IMAGE_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=PERS
nloc=${ONE_PX}
virt=one
```

Note: when detached, the volume is converted to a new StorPool snapshot with the "default" tags:
```
img=${ONE_PX}-img-${IMAGE_ID}
nloc=${ONE_PX}
virt=one
```

### Non-PERSISTENT images

The non-persistent images attached to a VM are StorPool volumes that are clones of an image (StorPool snapshot) registered in the IMAGE datastore with the following tags:

```bash
img=${ONE_PX}-img-${IMAGE_ID}-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=NPERS
nloc=${ONE_PX}
virt=one
```

### CDROM images

The images of type CDROM are created like the non-persistent images - cloned volumes with additional StorPool tag `type=CDROM`:
```bash
img=${ONE_PX}-img-${IMAGE_ID}-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=CDROM
nloc=${ONE_PX}
virt=one
```

### VOLATILE images

The volatile images are registered in the StorPool-backed SYSTEM datastore as a StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=VOL
*fs=${CREATED_FILESYSTEM}
nloc=${ONE_PX}
virt=one
```

Note: The `fs` tag is optional and shows the filesystem formatted when requested by OpenNebula.

### CONTEXTUALIZATION images

Each contextualization image registered in a StorPool-backed SYSTEM datastore is mapped to a StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=CNTXT
nloc=${ONE_PX}
virt=one
```

### CHECKPOINT images

When the addon is configured in `qemu-kvm-ev`-backed flavor (`SP_CHECKPOINT_BD=1`), the VM's checkpoint file is a StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-rawcheckpoint
nvm=${VM_ID}
type=CHKPNT
nloc=${ONE_PX}
virt=one
```

### Staging images

In the process of importing an image to a StorPool-backed IMAGE datastore, the source is stored temporarily on a StorPool volume whose name is suffixed with the md5sum of its name:
```bash
img=${ONE_PX}-img-${IMAGE_ID}-${MD5SUM}
nloc=${ONE_PX}
virt=one
```

## Snapshots

The snapshots are unnamed StorPool snapshots. The name used by the driver is stored as key/value in the etcd service and is repeated in the tags.

### Disk snapshot

Registered in etcd as `${VM_VOLUME_NAME}-snap${SNAP_ID}` with tags:
```bash
img=${VM_VOLUME_NAME}
snap=snap${SNAP_ID}
nvm=${VM_ID}
nloc=${ONE_PX}
virt=one
```

The image snapshots created with `oneimage snapshot-*` use the same `${IMAGE_VOLUME_NAME}-snap${SNAP_ID}` naming.

### VM snapshot

Registered in etcd as `${VM_VOLUME_NAME}-ONESNAP-${VM_SNAPSHOT_ID}-${TIMESTAMP}` with tags:
```bash
img=${VM_VOLUME_NAME}
snap=ONESNAP-${VM_SNAPSHOT_ID}-${TIMESTAMP}
nvm=${VM_ID}
nloc=${ONE_PX}
virt=one
```

### Reverting to a snapshot

A disk or VM snapshot revert uses the StorPool `VolumeRevert` API call. The volume gets a new `globalId` on each revert, while the id it was created with is kept in `preservedGlobalId`. The addon keeps addressing the volume by the original id in etcd and in the datastore symlinks. Both ids are resolved by the StorPool API, `storpool volume list` and `/dev/storpool-byid/`, so when correlating the output of `storpool volume list` with the etcd entries or the symlinks either id can be matched.

## NVRAM

The UEFI variables of a VM with `T_OS_NVRAM = "storpool:template=..."`
(see `uefi_boot.md`). A StorPool volume in the template of the system
datastore (`${ONE_PX}-ds-${SYSTEM_DS_ID}`), with the exact size of the
`OVMF_VARS` template file, registered in the KV store as
`byName/${ONE_PX}-sys-${VM_ID}-NVRAM` -> `~globalId` and addressed by globalId
afterwards, with tags:
```bash
img=${ONE_PX}-sys-${VM_ID}-NVRAM
nvm=${VM_ID}
type=NVRAM
nloc=${ONE_PX}
virt=one
vc-policy=${VC_POLICY}   # when the VM has a VC_POLICY
qc=${SP_QOSCLASS}        # when a QoS class is resolved for the VM
```
It has no `diskid` tag. It is listed in the `oneVmVolumes` maps with an empty
`DISK_ID`, so VM snapshots (`${ONE_PX}-sys-${VM_ID}-NVRAM-ONESNAP-<id>-<ts>`),
migration and terminate handle it like a VM disk; backups skip it.
