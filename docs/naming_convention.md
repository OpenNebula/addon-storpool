## StorPool naming convention

### Datastore templates

Each Datastore in Opennebula has a StorPool template with the following format
```bash
one-ds-${DATASTORE_ID}
```

### Images

#### PERSISTENT images

Each persistent image registered in a StorPool backed IMAGE datastore is mapped to StorPool volume
```bash
one-img-${IMAGE_ID}
```

#### Non-PERSISTENT images

The non-persistent images are clones of a image registered in the IMAGE datastore mapped to StorPool volume
```bash
one-img-${IMAGE_ID}-${VM_ID}-${VMDISK_ID}
```

#### VOLATILE images

The volatile images are registered in the StorPool backed SYSTEM datastore as a StorPool volume
```bash
one-sys-${VM_ID}-${VMDISK_ID}-raw
```

#### CONTEXTUALIZATION images

Each contextualization image registered in a StorPool backed IMAGE datastore is mapped to StorPool volume
```bash
one-sys-${VM_ID}-${VMDISK_ID}-iso
```

#### CHECKPOINT images

When the addon is configured in `qemu-kvm-ev` backed flavour each checkpoint file is a StorPool volume
```bash
one-sys-${VM_ID}-rawcheckpoint
```

When the default `qemu-kvm` package is used the StorPool volume holding the archive of the checkpoint file has following name
```bash
one-sys-${VM_ID}-checkpoint
```

#### Staging images

In the process of importing of image to a StorPool backed IMAGE datastore the source is stored temporary on a StorPool volume name suffixed with the md5sum of it's name
```bash
one-img-IMAGE_ID-${MD5SUM}
```

### Snapshots

#### Disk snapshot

```bash
${VOLUME_NAME}-ONESNAP-snap${SNAP_ID}
```

#### VM snapshot

```bash
${VOLUME_NAME}-ONESNAP-${VMSNAPSHOT_ID}-${UNIX_TIMESTAMP}
```
