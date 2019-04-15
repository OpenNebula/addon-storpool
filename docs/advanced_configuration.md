### Advanced configuration variables

#### StorPool template management

##### StorPool template management via datastore variables

The template management is disabled by default (recommended). To enable set `AUTO_TEMPLATE=1` in storpool-addonrc file.
```
ONE_LOCATION=/var/lib/one
echo "AUTO_TEMPLATE=1" >>$ONE_LOCATION/remotes/addon-storpoolrc
```

The following variables should be set on all StorPool backed datastores:

* **SP_REPLICATION**: [mandatory] The StorPool replication level for the datastore. Number (1)
* **SP_PLACEALL**: [mandatory] The name of StorPool placement group of disks where to store data. String (2)
* **SP_PLACETAIL**: [optional] The name of StorPool placement group of disks from where to read data. String (3)
* **SP_PLACEHEAD**: [optional] The name of StorPool placement group of disks for last data replica. String (4)
* **SP_BW**: [optional] The BW limit per volume on the DATASTORE.
* **SP_IOPS**: [optional] The IOPS limit per volume on the DATASTORE. Number.


1. The replication level defines how many separate copies to keep for each data block. Supported values are: `1`, `2` and `3`.
1. The PlaceAll placement group is defined in StorPool as list of drives where to store the data.
1. The PlaceTail placement group is defined in StorPool as list of drives. Used in StorPool hybrid setup. If the setup is not of hybrid type leave blank or same as **SP_PLACEALL**
1. The PlaceHead placement group is defined in StorPool as list of drives. Used in StorPool hybrid setups with one HDD replica and two SSD replicas of the data.

When adding a new datastore the reported size will appear after a refresh cycle of the cached StorPool data. Default is every 4th minute set in `/etc/cron.d/addon-storpoolrc`.

> :exclamation: The implemented management of StorPool templates is not deleting StorPool templates! After deleting a datastore in OpenNebula the corresponding template in StorPool should be deleted manually.

##### StorPool volume template management

Set `NO_VOLUME_TEMPLATE=1` in storpool-addonrc to not enforce the datastore template on the StorPool volumes. The newly created images and the contextualization ISO images still will have datastore template enforced.

#### StorPool backed SYSTEM datastore on shared filesystem

* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS.

Global datastore configuration for storpol TM_MAD is with *SHARED=yes* set. The default confiuration of the addon is to copy the VM files over _ssh_. If the datastore is on a shared filesystem this parameter should be set to *SP_SYSTEM=shared*.


#### Managing datastore on another StorPool cluster

It is possible to useing the OpenNebula's Cluster configuration to manage hosts that are members of different StorPool clusters. Set the StorPool API credentials in the datastore template:

* **SP_AUTH_TOKEN**: The AUTH tocken for of the StorPool API to use for this datastore. String.
* **SP_API_HTTP_HOST**: The IP address of the StorPool API to use for this datastore. IP address.
* **SP_API_HTTP_PORT**: [optional] The port of the StorPool API to use for this datastore. Number.

There are rare cases when the driver could not determine the StorPool node ID. To resolve this issue set in the OpenNebula's **Host** template the SP_OURID variable.

* **SP_OURID**: The node id in the StorPool's configuration. Number.


### VM checkpoint file on StorPool volume

_This feature require access to the StorPool's management API and CLI installed on the hypervisors._

There are two options supported, depending on the installed `qemu-kvm` version.


#### Save directly on a StorPool volume

Require _qemu-kvm-ev_ installed on the hypervisors. (Please follow OpenNebula's [Nodes Platform notes](http://docs.opennebula.org/5.4/intro_release_notes/release_notes/platform_notes.html#nodes-platform-notes) for installation instructions.)

* set SP_CHECKPOINT_BD=1 to enable the direct save/restore to StorPool backed block device
```
ONE_LOCATION=/var/lib/one
echo "SP_CHECKPOINT_BD=1" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

#### archive/restore on a StorPool volume

Set Edit/create the addon-storpool global configuration file /var/lib/one/remotes/addon-storpoolrc and define/set the following variable
```
ONE_LOCATION=/var/lib/one
echo "SP_CHECKPOINT=yes" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

* To use the save/restore functionality for stop/resume only
```
ONE_LOCATION=/var/lib/one
echo "SP_CHECKPOINT=nomigrates" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

#### Disk snapshot limits

It is possible to limit the number of snapshots per disk. When the limit is reached the addon will return an error which will be logged in the VM log and the _ERROR_ variable will be set in the VM's Info tab with relevant error message.

There are three levels of configuration possible.

#### Global in $ONE_LOCATION/remotes/addon-storpoolrc
The snaphost limits could be set as global in addon-storpoolrc:
```
ONE_LOCATION=/var/lib/one
echo "DISKSNAPSHOT_LIMIT=15" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

#### Per SYSTEM datastore

Set DISKSNAPSHOT_LIMIT variable in the SYSTEM's datastore template with he desired limit. The limit will be enforced on all VM's that are provisioned on the given SYSTEM datastore.

#### Per VM

> :exclamation: Only the members of the `oneadmin` group could alter the variable.

Open the VM's Info tab and add to the Attributes
```
DISKSNAPSHOT_LIMIT=15
```

### Re-configure the 'VM snapshot' to do atomic disk snapshots

* Append the following string to the VM_MAD's _ARGUMENTS_:
```
-l snapshotcreate=snapshot_create-storpool,snapshotrevert=snapshot_revert-storpool,snapshotdelete=snapshot_delete-storpool
```

* Edit `/etc/one/oned.conf` and set KEEP_SNAPSHOTS=YES in the VM_MAD section
```
VM_MAD = [
    ...
    KEEP_SNAPSHOTS = "yes",
    ...
]
```
It is possible to do fsfreeze/fsthaw while the VM disks are snapshotted.
```
ONE_LOCATION=/var/lib/one
echo "VMSNAPSHOT_FSFREEZE=1" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

#### VM snapshot limits

To enable VM snaphost limits:
```
VMSNAPSHOT_ENABLE_LIMIT=1
```

The snaphost limits could be set as global in addon-storpoolrc:
```
VMSNAPSHOT_LIMIT=10
```

It is possible to override the global defined values in the SYSTEM datastore configuration.

Also, it is possible to override them per VM defining the variables in the VM's USER_TEMPLATE (the attributes at the bottom in the Sunstone's "VM Info" tab). In this case it is possible (and recommended ) to restrict the variables to be managed by the members of 'oneadmin' group by setting in /etc/one/oned.conf:
```
cat >>/etc/one/oned.conf <<EOF
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
EOF

# restart oned to refresh the configuration
systemctl restart opennebula
```

### space usage monitoring configuration
In OpenNebula there are three probes for datastore related monitoring. The IMAGE datastore is monitored from the front end, the SYSTEM datastore and the VM disks(and their snapshots) are monitored from the hosts. As this addon support no direct access to the StorPool API from the hosts we should provide the needed data to the related probes. This is done by the monitor_helper-sync script which is run via cron job on the front-end. The script is collecting the needed data and propagating(if needed) to the hosts for use. Here is the default configuration:

```
# path to the json files on the hosts
# (must be writable by the oneadmin user)
SP_JSON_PATH="/tmp/"

# Path to the json files on the front-end
# (must be writable by the oneadmin user)
SP_FE_JSON_PATH="/tmp/monitor"

# datastores stats JSON and the command that generate them
SP_TEMPLATE_STATUS_JSON="storpool_template_status.json"
SP_TEMPLATE_STATUS_RUN="storpool -j template status"

# VM disks stats JSON and the command that generate them
SP_VOLUME_SPACE_JSON="storpool_volume_usedSpace.json"
SP_VOLUME_SPACE_RUN="storpool -j volume usedSpace"

# VM disks snapshots stats JSON and the command that generate them
SP_SNAPSHOT_SPACE_JSON="storpool_snapshot_space.json"
SP_SNAPSHOT_SPACE_RUN="storpool -j snapshot space"

# Copy(scp) the JSON files to the remote hosts
MONITOR_SYNC_REMOTE="YES"

# Do template propagate. When there is change in the template attributes
# propagate the change to all current volumes based on the template
SP_TEMPLATE_PROPAGATE="YES"

# Uncomment to enable debugging
#MONITOR_SYNC_DEBUG=1
```

For the case when there is shared filesystem between the one-fe and the HV nodes there is no need to copy the JSON files. In this case the `SP_JSON_PATH` variable must be altered to point to a shared folder and set `MONITOR_SYNC_REMOTE=NO`. The configuration change can be completed in `/var/lib/one/remotes/addon-storpoolrc` or `/var/lib/one/remotes/monitor_helper-syncrc` configuration files
_Note: the shared filesystem must be mounted on same system path on all nodes as on the one-fe!_

For example the shared file system in mounted on `/sharedfs`:
```bash
cat >>/var/lib/one/remotes/monitor_helper-syncrc <<EOF
# datastores stats on the sharedfs
export SP_JSON_PATH="/sharedfs"

# disabled remote sync
export MONITOR_SYNC_REMOTE="NO"

EOF
```

#### Multiverse - use multiple OpenNebula instances on single StorPool cluster

For each OpenNebula instance set a different string in the `ONE_PX` variable.

It is possible to change the default volume tagging by setting `VM_TAG` variable.


## VM's domain XML tweaking

OpenNebula is providing generic domain XML configuration that have a room for a lot of improvements.

The following configuration will change OpenNebula's KVM VM_MAD to use local deployment script instead of the default.

Note:
> This configuration replaces the VM tweaking scripts on the host that was done with `vmTweak*` scripts included in `kvm/deploy`.
> The original `kvm/deploy` file must be recovered to its original state.

To enable the alternative deployment script edit _/etc/one/oned.conf_ and configure the KVM's VM_MAD as follow:

```bash
    ...
    ARGUMENTS      = "-t 15 -r 0 kvm -p -l deploy=deploy-tweaks",
    ...
```

On each VM deploy the deploy-tweaks script will pass the VM's domain XML and the VM's metadata XML (collected from OpenNebula) to all executable files located in _/var/lib/one/remotes/vmm/kvm/deploy-tweaks.d_.
The VM's metadata is used by some of the scripts to look for configuration variables in the _USER_TEMPLATE_.

There are example scripts located in _/var/lib/one/remotes/vmm/kvm/deploy-tweaks.d.example_ that alter the domain XML as follow.

### iothreads.py

The script will define an [iothread](https://libvirt.org/formatdomain.html#elementsIOThreadsAllocation) and assign it to all virtio-blk disks and vitio-scsi controllers.

```xml
<domain>
  <iothreads>1</iothreads>
  <devices>
    <disk device="disk" type="block">
      <source dev="/var/lib/one//datastores/0/42/disk.2" />
      <target dev="vda" />
      <driver cache="none" discard="unmap" io="native" iothread="1" name="qemu" type="raw" />
    </disk>
    <controller index="0" model="virtio-scsi" type="scsi">
      <driver iothread="1" />
    </controller>
  </devices>
</domain>
```

### scsi-queues.py

The script set the virtio-scsi nqueues number to match the cont of VM's VCPUs

```xml
<domain>
  <vcpu>4</vcpu>
  <devices>
    <controller index="0" model="virtio-scsi" type="scsi">
      <driver queues="4" />
    </controller>
  </devices>
</domain>
```

### vfhostdev2interface.py

OpenNebula provides generic PCI passthrough definition using _hostdev_. But
when it is used for NIC VF passthrough it leave the VM's kernel to assign
random MAC address (on each boot). Replacing the definition with _interface_ it
is possible to define the MAC addresses via configuration variable in
_USER_TEMPLATE_. The T_VF_MACS configuration variable accept comma separated
list of MAC addresses to be asigned to the VF pass-through NICs. For example to
set MACs on two PCI passthrough VF interfaces, define the addresses in the
T_VF_MACS variable and (re)start the VM:

```
T_VF_MACS=02:00:11:ab:cd:01,02:00:11:ab:cd:02
```

The following section of the domain XML

```xml
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
      <address  domain='0x0000' bus='0xd8' slot='0x00' function='0x5'/>
    </source>
    <address type='pci' domain='0x0000' bus='0x01' slot='0x01' function='0'/>
  </hostdev>
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
      <address  domain='0x0000' bus='0xd8' slot='0x00' function='0x6'/>
    </source>
    <address type='pci' domain='0x0000' bus='0x01' slot='0x02' function='0'/>
  </hostdev>
```

will be converted to

```xml
  <interface managed="yes" type="hostdev">
    <driver name="vfio" />
    <mac address="02:00:11:ab:cd:01" />
    <source>
      <address bus="0xd8" domain="0x0000" function="0x5" slot="0x00" type="pci" />
    </source>
    <address bus="0x01" domain="0x0000" function="0" slot="0x01" type="pci" />
  </interface>
  <interface managed="yes" type="hostdev">
    <driver name="vfio" />
    <mac address="02:00:11:ab:cd:02" />
    <source>
      <address bus="0xd8" domain="0x0000" function="0x6" slot="0x00" type="pci" />
    </source>
    <address bus="0x01" domain="0x0000" function="0" slot="0x02" type="pci" />
  </interface>
```

### hyperv-clock.py

The script add additional tunes to the _clock_ entry when the _hyperv_ feature is enabled in the domain XML.

> Sunstone -> Templates -> VMs -> Update -> OS Booting -> Features -> HYPERV = YES

```xml
<domain>
  <clock offset="utc">
    <timer name="hypervclock" present="yes"/>
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
  </clock>
</domain>
```

### cpu.py

The script create/tweak the _cpu_ element of the domain XML. The following variables are commonly used


#### T_CPU_SOCKETS and T_CPU_THREADS

Set the number of sockets and vCPU threads of the CPU topology.
For example the following configuration represent VM with 8 VCPUs, in single socket with 2 threads:

```
VCPU = 8
USER_TEMPLATE/T_CPU_SOCKETS = 1
USER_TEMPLATE/T_CPU_THREADS = 2
```

```xml
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
    <numa>
      <cell id='0' cpus='0-7' memory='33554432' unit='KiB'/>
    </numa>
  </cpu>
```

#### Other

The following variables were made available for use in some corner cases.

> For advanced use only! A special care should be taken when mixing the variables as some of the options are not compatible when combined.

T_CPU_FEATURES

T_CPU_MODEL

T_CPU_VENDOR

T_CPU_CHECK

T_CPU_MATCH

T_CPU_MODE

### volatile2dev.py

The script will reconfigure the volatile disks from file to device when the VM disk's TM_MAD is _storpool_

```xml
    <disk type='file' device='disk'>
        <source file='/var/lib/one//datastores/0/4/disk.2'/>
        <target dev='sdb'/>
        <driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>
        <address type='drive' controller='0' bus='0' target='1' unit='0'/>
    </disk>
```
to

```xml
    <disk device="disk" type="block">
        <source dev="/var/lib/one//datastores/0/4/disk.2" />
        <target dev="sdb" />
        <driver cache="none" discard="unmap" io="native" name="qemu" type="raw" />
        <address bus="0" controller="0" target="1" type="drive" unit="0" />
    </disk>
```

To do the changes when hot-attaching a volatile disk the original attach_disk script (`/var/lib/one/remotes/vmm/kvm/attach_disk`) should be pathed too:

```bash
cd /var/lib/one/remotes/vmm/kvm
patch -p1 < ~/addon-storpool/patches/vmm/5.8.0/attach_disk.patch
```

> The installation script should apply the patch too
