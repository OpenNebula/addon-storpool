# Tips

## Creating images from StorPool snapshots

You can create an image in OpenNebula from an "external" snapshot. To do this using the Sunstone interface, follow the [OpenNebula documentation](https://docs.opennebula.io/6.8/management_and_operations/storage_management/images.html#using-sunstone-to-manage-images) and do the following:

1. In the "Image location" section select "Path/URL".
2. In the "Path" field enter location of the snapshot using the following format:

    ```
    SPSNAPSHOT:<snapshot_name_in_storpool>
    ```
Note that this can be done only by a member of the _oneadmin_ group.

Consider that when you are the owner of a VM you can import a VM snapshot as a new image. Follow the procedure above, and use the following format when entering the location in the "Path" field:

```
VMSNAP:<snapshot_name_in_storpool>
```

The difference in this case is that the driver checks the following:

* If the snapshot is known to OpenNebula.
* If the username importing the snapshot is the owner of the VM to which disk the snapshot belongs..

This way the owner of a VM could import snapshots of its VM disks.
