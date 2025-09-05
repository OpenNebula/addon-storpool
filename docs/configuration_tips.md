# Configuration tips

The main configuration information is provided in [OpenNebula configuration](one_configuration.md).
Here you can find additional configuration details.

## Recommended configuration

### /etc/one/vmm_exec/vmm_exec_kvm.conf

Note that these are the default values and could be overridden in the IMAGE and VM templates!

#### Activate the qemu guest agent socket in libvirt

The addon could use `fstrim/fsthaw` to create consistent snapshots/backups. The option enables the host side of the setup. The `qemu-guest-agent` must be running inside the VM.

* Default:

  ```FEATURES = [ PAE = "no", ACPI = "yes", APIC = "no", HYPERV = "no", GUEST_AGENT = "no" ]```

* Suggested:

  ```FEATURES = [ PAE = "no", ACPI = "yes", APIC = "no", HYPERV = "no", GUEST_AGENT = "yes" ]```


#### Change defaults for IO and discard

Add defaults for `io` and `discard`.

* Default:

  ```DISK     = [ driver = "raw" , cache = "none"]```

* Suggested:

  ```DISK     = [ driver = "raw" , cache = "none" , io = "native" , discard = "unmap" ]```


### /var/lib/one/remotes/etc/vmm/kvm/kvmrc

Or _/var/lib/one/remotes/vmm/kvm/kvmrc_, for OpenNebula before version 5.6.

#### DEFAULT_ATTACH_CACHE

Uncomment to enable.

* Default:

  ```#DEFAULT_ATTACH_CACHE=none```

* Suggested:

  ```DEFAULT_ATTACH_CACHE=none```

#### DEFAULT_ATTACH_DISCARD

Uncomment to enable

* Default:

  ```#DEFAULT_ATTACH_DISCARD=unmap```

* Suggested:

  ```DEFAULT_ATTACH_DISCARD=unmap```

#### DEFAULT_ATTACH_IO

Uncomment and set to _native_

* Default:

  ```#DEFAULT_ATTACH_IO=```

* Suggested:

  ```DEFAULT_ATTACH_IO=native```

## Extras

**!!! Warning !!!**
*These features are changing the defalt behavior of OpenNebula and should be used when the StorPool addon is the only storage driver, and when used for both SYSTEM and IMAGE datastores!*


### VM snapshots

*The feature is working only with recent version of StorPool. Please contact StorPool Support for details.*

The StorPool addon can re-purpose the OpenNebula's interface for VM snapshots to do atomic snapshots on all VM disks at once. In addition, there is an option to enable `FSFREEZE` before snapshotting and `FSTHAW` after the snapshots are taken.

To enable the feature do the following changes.

1. In `/etc/one/oned.conf`:

    1. Edit the `VM_MAD` configuration for `kvm` and change the `ARGUMENTS` line as follows:
    
       ```
           ARGUMENTS      = "-t 15 -r 0 kvm -l snapshotcreate=snapshot_create-storpool,snapshotrevert=snapshot_revert-storpool,snapshotdelete=snapshot_delete-storpool",
       ```
    
    2. Edit the `VM_MAD` configuration for `kvm` and change `KEEP_SNAPSHOTS` to 'yes':
    
       ```
           KEEP_SNAPSHOTS = "yes",
       ```

2. In `/var/lib/one/remotes/addon-storpoolrc`:

   1. Add `VMSNAPSHOT_OVERRIDE` configuration variable:
   
      ```VMSNAPSHOT_OVERRIDE=1```
   
   2. To enable the optional `fsfreeze/fsthaw`:
   
      ```
      VMSNAPSHOT_FSFREEZE=1
      ```

Please restart the `opennebula` service to activate the changes.

## Using StorPool SYSTEM datastore when there are other SYSTEM datastores available

### Using scheduler filters

To tell the OpenNebula's scheduler to deploy the VMs only on StorPool backed SYSTEM datastores, set
`SCHED_DS_REQUIREMENTS` in the VM template:

```
SCHED_DS_REQUIREMENTS="TM_MAD=storpool"
```

Using sunstone, it is located in "Update VM template" -> "Scheduling" -> "Placement" -> "Datastore Requirements".
Set the "Expression" to ```TM_MAD=storpool```.

### Using Cluster definition

Define an OpenNebula cluster selecting only StorPool backed SYSTEM and IMAGE datastores. Keep in mind that in this case the images used in the VM templates must be on the datastore selected in the cluster!

