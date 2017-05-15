## OpenNebula configuration tips

### Recommended configuration

#### /etc/one/oned.conf

##### DEFAULT_DEVICE_PREFIX

*virtio-scsi* is slightly slower than *virtio-blk* but is preferred because of it's support of TRIM/discard.

This variable could be overridden by the IMAGE or VM template definition! Please take attention when defining the VM templates!

(default)

```DEFAULT_DEVICE_PREFIX = "hd"```

(suggested)

```DEFAULT_DEVICE_PREFIX = "sd"```


#### /etc/one/vmm_exec/vmm_exec_kvm.conf

Note that these are the default values and could be overridden in the IMAGE and VM templates!

##### Activate the qemu guest agent socket in libvirt

The addon could use fstrim/fsthaw to create consistent snapshots/backups. The option enables the host side of the setup. The `qemu-guest-agent` must be running inside the VM.

(default)

```FEATURES = [ PAE = "no", ACPI = "yes", APIC = "no", HYPERV = "no", GUEST_AGENT = "no" ]```

(suggested)

```FEATURES = [ PAE = "no", ACPI = "yes", APIC = "no", HYPERV = "no", GUEST_AGENT = "yes" ]```


##### Change defaults for IO and discard

Add defaults for `io` and `discard`.

(default)

```DISK     = [ driver = "raw" , cache = "none"]```

(suggested)

```DISK     = [ driver = "raw" , cache = "none" , io = "native" , discard = "unmap" ]```


#### /var/lib/one/remotes/vmm/kvm/kvmrc

##### DEFAULT_ATTACH_CACHE

Uncomment to enable.

(default)

```#DEFAULT_ATTACH_CACHE=none```

(suggested)

```DEFAULT_ATTACH_CACHE=none```

##### DEFAULT_ATTACH_DISCARD

Uncomment to enable

(default)

```#DEFAULT_ATTACH_DISCARD=unmap```

(suggested)

```DEFAULT_ATTACH_DISCARD=unmap```

### Extras

**!!! Warning !!!**
*These features are changing the defalt behavior of OpenNebula and should be used only when the StorPool addon is used for both SYSTEM and IMAGE datastores.*


#### VM snapshots

*The feature is working only with recent version of StorPool. Please contact StorPool Support for details.*

The StorPool addon can re purpose the OpenNebula's interface for VM snapshots to do atomic snapshots on all VM disks at once. In addition there is an option to enable FSFREEZE before snapshotting and FSTHAW after the snapshots are taken always or when there are more than one VM disk image available(besides the contextualization iso).

To enable the feature do the following changes.

##### /etc/one/oned.conf

###### edit the `VM_MAD` configuration for `kvm` and change the `ARGUMENTS` line as follow

```
    ARGUMENTS      = "-t 15 -r 0 kvm -l snapshotcreate=snapshot_create-storpool,snapshotrevert=snapshot_revert-storpool,snapshotdelete=snapshot_delete-storpool",
```

 ###### edit the `VM_MAD` configuration for `kvm` and change `KEEP_SNAPSHOTS` to 'yes'

```
    KEEP_SNAPSHOTS = "yes",
```

##### /var/lib/one/remotes/addon-storpoolrc

###### Add `VMSNAPSHOT_OVERRIDE` and `VMSNAPSHOT_ATOMIC` configuration variables

```VMSNAPSHOT_OVERRIDE=1```

```VMSNAPSHOT_ATOMIC=1```


###### (optional) do fsfreeze/fsthaw only when there are more than one attached VM disk
The following require working communication with the qemu-guest-agent process running inside the VM!!!

```
BACKUP_FSFREEZE_MULTIDISKS=1
```

###### (optional) or to always do fsfreeze/fsthaw set

```
BACKUP_FSFREEZE=1
```

### Using StorPool SYSTEM datastore when there are other SYSTEM datastores available

#### Using scheduler filters

To tell the OpenNebula's scheduler to deploy the VMs only on StorPool backed SYSTEM datastores set
`SCHED_DS_REQUIREMENTS` in the VM template

```
SCHED_DS_REQUIREMENTS="TM_MAD=storpool"
```

Using sunstone it is located in "Update VM template" -> "Scheduling" -> "Placement" -> "Datastore Requirements".
Set the "Expression" to ```TM_MAD=storpool```

#### Using Cluster definition

Define an OpenNebula cluster selecting only StorPool backed SYSTEM and IMAGE datastores. Keep in mind that in this case the images used in the VM templates must be on the datastore selected in the cluster!

