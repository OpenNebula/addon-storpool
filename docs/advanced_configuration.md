### Advanced configuration variables

#### StorPool backed SYSTEM datastore on shared filesystem

* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS.

Global datastore configuration for storpool TM_MAD is with *SHARED=yes* set. The default configuration of the addon is to copy the VM files over _ssh_. If the datastore is on a shared filesystem this parameter should be set to *SP_SYSTEM=shared*.


#### Managing datastore on another StorPool cluster

It is possible to use the OpenNebula's Cluster configuration to manage hosts that are members of different StorPool clusters. Set the StorPool API credentials in the datastore template:

* **SP_AUTH_TOKEN**: The AUTH token for of the StorPool API to use for this datastore. String.
* **SP_API_HTTP_HOST**: The IP address of the StorPool API to use for this datastore. IP address.
* **SP_API_HTTP_PORT**: [optional] The port of the StorPool API to use for this datastore. Number.

There are rare cases when the driver could not determine the StorPool node ID. To resolve this issue set in the OpenNebula's **Host** template the SP_OURID variable.

* **SP_OURID**: The node id in the StorPool's configuration. Number.


#### VM checkpoint file on a StorPool volume

Require _qemu-kvm-ev_ installed on the hypervisors. (Please follow OpenNebula's [Nodes Platform notes](http://docs.opennebula.org/5.4/intro_release_notes/release_notes/platform_notes.html#nodes-platform-notes) for installation instructions.)

* reconfigure opennebula to use local actions for save and restore

```
VM_MAD = [
   ...
   ARGUMENTS = "... -l ...save=tmsave,restore=tmrestore"
]
```

* set SP_CHECKPOINT_BD=1 to enable the direct save/restore to StorPool backed block device
```
ONE_LOCATION=/var/lib/one
echo "SP_CHECKPOINT_BD=1" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

#### Disk snapshot limits

It is possible to limit the number of snapshots per disk. When the limit is reached the addon will return an error which will be logged in the VM log and the _ERROR_ variable will be set in the VM's Info tab with relevant error message.

There are three levels of configuration possible.

#### Global in $ONE_LOCATION/remotes/addon-storpoolrc

The snapshot limits could be set as global in addon-storpoolrc:
```
ONE_LOCATION=/var/lib/one
echo "DISKSNAPSHOT_LIMIT=15" >> $ONE_LOCATION/remotes/addon-storpoolrc
```

##### Per SYSTEM datastore

Set DISKSNAPSHOT_LIMIT variable in the SYSTEM's datastore template with he desired limit. The limit will be enforced on all VM's that are provisioned on the given SYSTEM datastore.

##### Per VM

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

To enable VM snapshot limits:
```
VMSNAPSHOT_ENABLE_LIMIT=1
```

The snapshot limits could be set as global in addon-storpoolrc:
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

### Send volume snapshot to a remote StorPool cluster when deleting a volume

```
REMOTE_BACKUP_DELETE=<remote_location>:<optional_argumets>
```
There is an option to send last snapshot to a remote StorPool cluster when deleting a disk image. The configuration is as follow:
 * `remote_location` - the name of the remote StorPool cluster to send volume snapshot to
 * `optional_argumets` - extra arguments

For example, to send volume snapshot to a remote cluster with name _clusterB_ and tag the volumes with tag _del=y_ set 

```
REMOTE_BACKUP_DELETE="clusterB:tag del=y"
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
#DEBUG_MONITOR_SYNC=1
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

See  [Deploy tweaks](deploy_tweaks.md)


## Delayed delete of VM disks

When a VM is terminated or non-persistent image is detached from a given VM the corresponding StorPool volume is Deleted. To prevent from accidental volume delete (wrong detach/termination) there is an option to rename to volume to an "anonymous" snapshot and mark for deletion by StorPool after a given time. 

```bash
# For example to set the delay to 12 hours
echo 'DELAY_DELETE="12h"' >> /var/lib/one/remotes/addon-storpoolrc
# and propagate the changes
su - oneadmin -c "onehost sync --force"
```

