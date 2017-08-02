### VM checkpoint

When the SYSTEM datastore is on storpool (TM_MAD=storpool), to enable save/restore of the checkpoint file to a storpool volume.
* Edit/create the addon-storpool global configuration file /var/lib/one/remotes/addon-storpoolrc and define/set the following variable
```
SP_CHECKPOINT=yes
```
* To use the save/restore functionality for stop/resume only
```
SP_CHECKPOINT=nomigrate
```
* When qemu-kvm-ev is installed enable the direct save/restore to StorPool backed block device
```
SP_CHECKPOINT_BD=1
```

### (option) Reconfigure the 'VM snapshot' scripts to do atomic disk snapshots. Append the following string to the VM_MAD ARGUMENTS:
```
-l snapshotcreate=snapshot_create-storpool,snapshotrevert=snapshot_revert-storpool,snapshotdelete=snapshot_delete-storpool
```
* Edit `/etc/one/oned.conf` and change KEEP_SNAPSHOTS=YES in the VM_MAD section
```
VM_MAD = [
    ...
    KEEP_SNAPSHOTS = "yes",
    ...
]
```
When there are more than one disk per VM it is recommended to do fsfreese/fsthaw while the disks are snapshotted. Enable in addon-storpoolrc:
```
VMSNAPSHOT_FSFREEZE_MULTIDISKS=1
```
There is alternative option which require the StorPool feature to do atomic grouped snapshots available in StorPool revision 16.01.877+. In this case it is acceptable to do snapshots without fsfreeze/fsthaw. To enable the feature set in addon-storpoolrc:
```
VMSNAPSHOT_ATOMIC=1
```

#### VM snapshot limits

To enable VM snaphost limits:
```
VMSNAPSHOT_ENABLE_LIMIT=1
```

The snaphost limits could be set as global in addon-storpoolrc:
```
VMSNAPSHOT_LIMIT=10
DISKSNAPSHOT_LIMIT=15
```
It is possible to override the global defined values in the SYSTEM datastore configuration.

Also, it is possible to override them per VM defining the variables in the VM's USER_TEMPLATE (the attributes at the bottom in the Sunstone's "VM Info" tab). In this case it is possible (and recommended ) to restrict the variables to be managed by the members of 'oneadmin' group by setting in /etc/one/oned.conf:
```
cat >>/etc/one/oned.conf <<EOF
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
EOF

# and restart oned to refresh it's configuration
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

### Additional configuration when there is datastore on another(non default) storpool cluster:
Include `SP_API_HTTP_HOST` `SP_API_HTTP_PORT` and `SP_AUTH_TOKEN` as additional attributes to the Datstores.

There are rare cases when the driver could not determine the StorPool node ID:
Set the SP_OURID attribute in the HOST configuration.

### Advanced configuration variables

#### StorPool template management

* **SP_REPLICATION**: [mandatory] The StorPool replication level for the datastore. Number (1)
* **SP_PLACEALL**: [mandatory] The name of StorPool placement group of disks where to store data. String (2)
* **SP_PLACETAIL**: [optional] The name of StorPool placement group of disks from where to read data. String (3)
* **SP_PLACEHEAD**: [optional] The name of StorPool placement group of disks for last data replica. String (4)
* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS. Global datastore configuration for storpol TM_MAD is with *SHARED=yes* set. If the datastore is not on shared filesystem this parameter should be set to *SP_SYSTEM=ssh* to copy non-storpool files from one node to another.
* **SP_API_HTTP_HOST**: [optional] The IP address of the StorPool API to use for this datastore. IP address.
* **SP_API_HTTP_PORT**: [optional] The port of the StorPool API to use for this datastore. Number.
* **SP_AUTH_TOKEN**: [optional] The AUTH tocken for of the StorPool API to use for this datastore. String.
* **SP_BW**: [optional] The BW limit per volume on the DATASTORE.
* **SP_IOPS**: [optional] The IOPS limit per volume on the DATASTORE. Number.

1. The replication level defines how many separate copies to keep for each data block. Supported values are: `1`, `2` and `3`.
1. The PlaceAll placement group is defined in StorPool as list of drives where to store the data.
1. The PlaceTail placement group is defined in StorPool as list of drives. Used in StorPool hybrid setup. If the setup is not of hybrid type leave blank or same as **SP_PLACEALL**
1. The PlaceHead placement group is defined in StorPool as list of drives. Used in StorPool hybrid setups with one HDD replica and two SSD replicas of the data.

#### *SNAPSHOT_LIMIT configuration

* **DISKSNAPSHOT_LIMIT**: [optional] disk snapshots limit per VM disk. Number. (SYSTEM_DS)
* **VMSNAPSHOT_LIMIT**: [optional] VM snapshots limit. Number. (SYSTEM_DS)
