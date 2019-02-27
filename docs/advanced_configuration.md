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

#### Enable iothreads and Windows performance optimisation

There is a helper script that add separate iothread for VM disks IO processing. In addition it is enabling some Hyperv enlightments on Windows VMs

Edit _~oneadmin/remotes/vmm/kvm/deploy_ and add _"$(dirname $0)/vmTweakHypervEnlightenments.py" "$domain"_ just after _cat >$domain_ line. The edited file should look like this:

```bash
mkdir -p `dirname $domain`
cat > $domain

"$(dirname $0)/vmTweakHypervEnlightenments.py" "$domain"

data=`virsh --connect $LIBVIRT_URI create $domain`
```

The scripts add a iothread and assign all virtio-blk disks and virio-scsi controllers to the thread:

```xml
<domain>
  ...
  <devices>
    ...
    <disk type="block" device="disk">
      <source dev="/var/lib/one//datastores/103/68/disk.1"/>
      <target dev="vda"/>
      <driver name="qemu" type="raw" cache="none" io="native" discard="unmap" iothread="1"/>
    </disk>
    ...
    <controller model="virtio-scsi" type="scsi">
      <driver iothread="1"/>
    </controller>
    ...
  </devices>
  ...
  <iothreads>1</iothreads>
  ...
<</domain>>

```

When the _HYPERV_ feature is enabled in the _OS & CPU_ / _Features_ entry the tweaking tool will add a _clock_ entry in the domain XML

```xml
<domain>
...
  <clock offset="utc">
    <timer name="hypervclock" present="yes"/>
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
    <timer name="hypervclock" present="yes"/>
  </clock>
</domain>
```

In Sunstone -> Templates -> VMs -> Update -> OS Booting -> Features -> HYPERV = YES
