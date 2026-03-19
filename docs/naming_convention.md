# StorPool naming convention

Here you can find how the OpenNebula's datastores and images are mapped to the StorPool Templates, Volumes, and Snapshots.

## Addon version

The addon uses the `YY.MM.R` versioning schema, where `YY` is the year of the release, `MM` is the month of the release, and `R` is the revision in the month.

## Datastore templates

Each Datastore in Opennebula has a StorPool template with the following format:
```bash
${ONE_PX}-ds-${DATASTORE_ID}
```

## Images

The Images in the Image Datastore(s) are mapped to StorPool snapshot with tag:
```bash
img=${ONE_PX}-img-${IMAGE_ID}
```

#### PERSISTENT images

When a persistent Image is assigned to a VM, the StorPool snapshot is converted to a Volume and the follwing tags are added:
```bash
img=${ONE_PX}-img-${IMAGE_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
```

### Non-PERSISTENT images

The non-persistent images are clones of a image registered in the IMAGE datastore mapped to StorPool volume:
```bash
img=${ONE_PX}-img-${IMAGE_ID}-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
```

### CDROM images

The images of type CDROM are created like non-persistent images - cloned volumes with additional StorPool tag `type=CDROM`:
```bash
img=${ONE_PX}-img-${IMAGE_ID}-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=CDROM
```

### VOLATILE images

The volatile images are registered in the StorPool-backed SYSTEM datastore as a StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=[FS|SWAP]
*fs=${CREATED_FILESYSTEM}
```

### CONTEXTUALIZATION images

Each contextualization image registered in a StorPool-backed SYSTEM datastore is mapped to StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-${VMDISK_ID}
diskid=${VMDISK_ID}
nvm=${VM_ID}
type=CDROM
```

### CHECKPOINT images

When the addon is configured in `qemu-kvm-ev`-backed flavor (`SP_CHECKPOINT_BD=1`), the VM's checkpoint file is a StorPool volume:
```bash
img=${ONE_PX}-sys-${VM_ID}-rawcheckpoint
nvm=${VM_ID}
type=CHKPNT
```

### Staging images

In the process of importing of an image to a StorPool-backed IMAGE datastore, the source is stored temporary on a StorPool volume name suffixed with the md5sum of it's name:
```bash
img=${ONE_PX}-img-${IMAGE_ID}-${MD5SUM}
```

## Snapshots

### Disk snapshot

```bash
vol=${VM_VOLUME_NAME}
snap=snap${SNAP_ID}
nvm=${VM_ID}
```

### VM snapshot

```bash
vol=${VM_VOLUME_NAME}
snap=ONESNAP-${VM_SNAPSHOT_ID}-${TIMESTAMP}
nvm=${VM_ID}
```

## NVRAM

A StorPool volume with tags:
```bash
img=${ONE_PX}-sys-${VM_ID}-NVRAM
nvm=${VM_ID}
type=NVRAM
```
