## OpenNebula configuration tips

### Recommended configuration

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


#### /var/lib/one/remotes/etc/vmm/kvm/kvmrc

or _/var/lib/one/remotes/vmm/kvm/kvmrc_ for OpenNebula before version 5.6

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

##### DEFAULT_ATTACH_IO

Uncomment and set to _native_

(default)

```#DEFAULT_ATTACH_IO=```

(suggested)

```DEFAULT_ATTACH_IO=native```

### Extras

**!!! Warning !!!**
*These features are changing the defalt behavior of OpenNebula and should be used when the StorPool addon is the only storage driver and used for both SYSTEM and IMAGE datastores!*


#### VM snapshots

*The feature is working only with recent version of StorPool. Please contact StorPool Support for details.*

The StorPool addon can re purpose the OpenNebula's interface for VM snapshots to do atomic snapshots on all VM disks at once. In addition there is an option to enable FSFREEZE before snapshotting and FSTHAW after the snapshots are taken.

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

###### Add `VMSNAPSHOT_OVERRIDE` configuration variable

```VMSNAPSHOT_OVERRIDE=1```

###### To enable the optional fsfreeze/fsthaw

```
VMSNAPSHOT_FSFREEZE=1
```

Please restart the `opennebula` service to activate the changes.

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

