# StorPool Storage Driver

## Description

The [StorPool](https://storpool.com/) datastore driver enables OpenNebula to use a StorPool storage system for storing disk images.

## Development

To contribute bug patches or new features, you can use the github Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

More info:

* [How to Contribute](http://opennebula.org/addons/contribute/)
* Support: [OpenNebula user forum](https://forum.opennebula.org/c/support)
* Development: [OpenNebula developers forum](https://forum.opennebula.org/c/development)
* Issues Tracking: GitHub issues (https://github.com/OpenNebula/addon-storpool/issues)

## Authors

* Leader: Anton Todorov (a.todorov@storpool.com)

## Compatibility

This add-on is compatible with OpenNebula 4.10+ and StorPool 15.02+.
The additional extras requires latest stable versions of OpenNebula and StorPool.

## Requirements

### OpenNebula Front-end

* Password-less SSH access from the front-end `oneadmin` user to the `node` instances.
* StorPool CLI installed, authorization token and access to the StorPool API network
* (Optional) member of the StorPool cluster with working StorPool initiator driver(storpool_block). In this case the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.

### OpenNebula Node (or Bridge Node)

* StorPool initiator driver (storpool_block)
* StorPool CLI installed, authorization token and access to the StorPool API network
* If the node is used as Bridge Node - the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* If it is only Bridge Node - it must be configured as Host in open nebula but configured to not run VMs.
* The Bridge node must have qemu-img available - used by the addon during imports to convert various source image formats to StorPool baclked RAW images.

### StorPool cluster

A working StorPool cluster is required.

## Features
Support standard OpenNebula datastore operations:
* support for datstore configuration via CLI and sunstone
* support all Datastore MAD(DATASTORE_MAD) and Transfer Manager MAD(TM_MAD) functionality
* support SYSTEM datastore on shared filesystem or ssh when TM_MAD=storpool is used
* support SYSTEM datastore volatile disk and context images as StorPool block devices
* support migration from one to another SYSTEM datastore if both are with `storpool` TM_MAD
* support TRIM/discard in the VM when virtio-scsi driver is in use (require `DEVICE_PREFIX=sd`)
* support VM checkpoint file to be archived on StorPool backed block device (see extras)

### Extras
* support two different modes of disk usage reporting - LVM style and StorPool style
* support managing datastores on different StorPool clusters
* support migrate-live when TM_MAD='ssh' is used for SYSTEM datastore
* support limit (per disk) on the number of disk snapshots
* support import of VmWare (VMDK) and Hyper-V (VHDX) images in addition to default (QCOW2) format
* all disk images are thin provisioned RAW block devices
* (optional) Replace "VM snapshot" interface to do atomic disk snapshots on StorPool (see limitations)
* (optional) Option to set limit on the number of "VM snaphots"
* (optional) support VM checkpoint file to be written and red directly from StorPool backed block device (see limitations)
* (optional) Improved storage security: no storage management access from the hypervisors is needed so if rogue user manage to escape from the VM to the host the impact on the storage will be reduced at most to the locally attached disks(see limitations)
* (optional) helper tool to enable virtio-blk-data-plane for virtio-blk (require `DEVICE_PREFIX=vd`)
* (optional) helper tool to migrate CONTEXT iso image to StorPool backed volume (require SYSTEM_DS `TM_MAD=storpool`)

## Limitations

1. Tested only with KVM hypervisor
1. No support for VM snapshot because it is handled internally by libvirt. There is an option to use the management interface to do disk snapshots when only StorPool bacled datastores are used.
1. When SYSTEM datastore integration is enabled the reported free/used/total space is the space on StorPool. The system filesystem monitoring could be possible by enabling the default SYSTEM DS in the cluster for monitoring purposes only.
1. The extra to use VM checkpoint file directly on StorPool backed block device requires qemu-kvm-ev and StorPool CLI with access to the StorPool's management API installed in the hypervisor nodes. 
1. The extra features are tested/confirmed working on CentOS. Please notify the author for any success/failure when used on another OS.

## Installation

### Pre-install

#### front-end dependencies

```bash
# on the front-end
yum -y install --enablerepo=epel patch git jq lz4 npm
npm install bower -g
npm install grunt-cli -g
```

#### node dependencies

```bash
yum -y install --enablerepo=epel lz4 jq python-lxml
```

### Get the addon from github
```bash
cd ~
git clone https://github.com/OpenNebula/addon-storpool
```

### automated installation
The automated installation is best suitable for new deployments. The install script will try to do an upgrade if it detects that addon-storpool is already installed but it is possible to have errors due to non expected changes

* Run the install script as 'root' user and check for any reported errors or warnings
```bash
bash ~/addon-storpool/install.sh
```
If oned and sunstone services are on different servers it is possible to install only part of the integration:
 * set environment variable SKIP_SUNSTONE=1 to skip the sunstone integration
 * set environment variable SKIP_ONED=1 to skip the oned integration

### manual installation

The following commands are related to latest OpenNebula version.

#### oned related pieces

* Copy storpool's DATASTORE_MAD driver
```bash
cp -a ~/addon-storpool/datastore/storpool /var/lib/one/remotes/datastore/

# copy xpath_multi.py to datastore/storpool/
cp ~/addon-storpool/datastore/xpath_multi.py  /var/lib/one/remotes/datastore/storpool/

# fix files ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/datastore/storpool

```

* Copy storpool's TM_MAD driver
```bash
cp -a ~/addon-storpool/tm/storpool /var/lib/one/remotes/tm/

#fix files ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/tm/storpool
```
* Copy storpool's VM_MAD driver addon scripts (option)
```bash
cp -a ~/addon-storpool/vmm/kvm/snapshot_* /var/lib/one/remotes/vmm/kvm/

#fix files ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/vmm/kvm
```

* Patch IM_MAD/kvm-probes.d/monitor_ds.sh
```bash
pushd /var/lib/one
patch -p0 <~/addon-storpool/patches/im/5.2/00-monitor_ds.patch
popd
```

* Patch TM_MAD/shared/monitor
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/tm/5.0/00-shared-monitor.patch
popd
```

* Patch TM_MAD/ssh/monitor_ds
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/tm/5.0/00-ssh-monitor_ds.patch
popd
```

* Create cron job for stats polling (fix the paths if needed)
```bash
cat >>/etc/cron.d/addon-storpool <<_EOF_
# StorPool
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=oneadmin
*/4 * * * * oneadmin /var/lib/one/remotes/datastore/storpool/monitor_helper-sync 2>&1 >/tmp/monitor_helper_sync.err
_EOF_
```
If upgrading delete the old style cron tasks
```bash
crontab -u oneadmin -l | grep -v monitor_helper-sync | crontab -u oneadmin -
crontab -u root -l | grep -v "storpool -j " | crontab -u root -
```

#### sunstone related pieces

* Patch and rebuild the sunstone interface
```bash
pushd /usr/lib/one/sunstone/public
# patch the sunstone interface
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.0/datastores-tab.patch

# rebuild the interface
npm install
bower --allow-root install
grunt sass
grunt requirejs
popd
```

### addon configuration
The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.

*  If you plan to do live disk snapshots with fsfreeze via qemu-guest-agent but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the addon global configuration.

* To change disk space usage reporting to be as LVM is reporting it, define `SP_SPACE_USED_LVMWAY` variable to anything

* Add the `oneadmin` user to group `disk` on all nodes
```bash
usermod -a -G disk oneadmin
```
* Edit `/etc/one/oned.conf` and add `storpool` to the `TM_MAD` arguments
```
TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,dev,storpool"
]
```
* Edit `/etc/one/oned.conf` and add `storpool` to the `DATASTORE_MAD` arguments

```
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,dev,storpool  -s shared,ssh,ceph,fs_lvm,qcow2,storpool"
]
```

* Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` definition for StorPool
```
TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes" ]
```

* Edit `/etc/one/oned.conf` and append DS_MAD_CONF definition for StorPool
```
DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "" ]
```

To enable live disk snapshots support for storpool
* Add `kvm-storpool` to `LIVE_DISK_SNAPSHOTS` in `/etc/one/vmm_exec/vmm_execrc`
```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
```

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

* (option) Reconfigure the 'VM snapshot' scripts to do atomic disk snapshots. Append the following string to the VM_MAD ARGUMENTS:
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

#### space usage monitoring configuration
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

Additional configuration when there is datastore on another(non default) storpool cluster:
Include `SP_API_HTTP_HOST` `SP_API_HTTP_PORT` and `SP_AUTH_TOKEN` as additional attributes to the Datstores.

There are rare cases when the driver could not determine the StorPool node ID:
Set the SP_OURID attribute in the HOST configuration.


### Post-install
* Restart `opennebula` and `opennebula-sunstone` services
```bash
service opennebula restart
service opennebula-sunstone restart
```
* As oneadmin user sync the remote scripts
```bash
su - oneadmin -c 'onehost sync --force'
```

## Upgrade

Follow the installation procedure. If something can not be upgraded automatically a note is printed with hints what should be done manually. Take care of such notes and follow them.

## Configuration

### Configuring the System Datastore

This addon enables full support of transfer manager (TM_MAD) backend of type shared, ssh, or storpool for the system datastore. The system datastore will hold only the symbolic links to the StorPool block devices, so it will not take much space. See more details on the [System Datastore Guide](http://docs.opennebula.org/4.10/administration/storage/system_ds.html).

If TM_MAD is storpool it is possible to have both shared and ssh datastores, configured per cluster. To achieve this two attributes should be set:

* DATASTORE_LOCATION in cluster configuration should be set (pre OpenNebula 5.x+)
* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But if the given datastore is not shared *SP_SYSTEM=ssh* should be set in the datastore configuration

It is possible to manage different set of hosts working with different StorPool clusters from a single front-end. In this case the separation of the resources in Clusters is mandatory. I this case it is highly advised to set the StorPool API details(`SP_API_HTTP_HOST`, `SP_AUTH_TOKEN` and optionally `SP_API_HTTP_PORT`) in each StorPool enabled datastore.

### Configuring the Datastore

Some configuration attributes must be set to enable an datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: [optional] Nodes to use for image datastore operations. String (1)
* **SP_REPLICATION**: [mandatory] The StorPool replication level for the datastore. Number (2)
* **SP_PLACEALL**: [mandatory] The name of StorPool placement group of disks where to store data. String (3)
* **SP_PLACETAIL**: [optional] The name of StorPool placement group of disks from where to read data. String (4)
* **SP_PLACEHEAD**: [optional] The name of StorPool placement group of disks for last data replica. String (5)
* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS. Global datastore configuration for storpol TM_MAD is with *SHARED=yes* set. If the datastore is not on shared filesystem this parameter should be set to *SP_SYSTEM=ssh* to copy non-storpool files from one node to another.
* **SP_API_HTTP_HOST**: [optional] The IP address of the StorPool API to use for this datastore. IP address.
* **SP_API_HTTP_PORT**: [optional] The port of the StorPool API to use for this datastore. Number.
* **SP_AUTH_TOKEN**: [optional] The AUTH tocken for of the StorPool API to use for this datastore. String.
* **SP_BW**: [optional] The BW limit per volume on the DATASTORE.
* **SP_IOPS**: [optional] The IOPS limit per volume on the DATASTORE. Number.
* **DISKSNAPSHOT_LIMIT**: [optional] disk snapshots limit per VM disk. Number. (SYSTEM_DS)
* **VMSNAPSHOT_LIMIT**: [optional] VM snapshots limit. Number. (SYSTEM_DS)

1. Quoted, space separated list of server hostnames which are members of the StorPool cluster. If it is left empty the front-end must have working storpool_block service (must have access to the storpool cluster) as all disk preparations will be done locally.
1. The replication level defines how many separate copies to keep for each data block. Supported values are: `1`, `2` and `3`.
1. The PlaceAll placement group is defined in StorPool as list of drives where to store the data.
1. The PlaceTail placement group is defined in StorPool as list of drives. Used in StorPool hybrid setup. If the setup is not of hybrid type leave blank or same as **SP_PLACEALL**
1. The PlaceHead placement group is defined in StorPool as list of drives. Used in StorPool hybrid setups with one HDD replica and two SSD replicas of the data.

The following example illustrates the creation of a StorPool datastore of hybrid type with 3 replicas. In this case the datastore will use hosts node1, node2 and node3 for imports and creating images.

#### Image datastore through Sunstone

Sunstone -> Infrastructure -> Datastores -> Add [+]

* Name: StorPool
* Presets: StorPool
* Type: Images
* Host Bridge List: node1 node2 node3
* StorPool Replication: 3
* StorPool PlaceAll: hdd
* StorPool PlaceTail: ssd

#### Image datastore through onedatastore

```bash
# create datastore configuration file
$ cat >/tmp/ds.conf <<EOF
NAME = "StorPool"
DS_MAD = "storpool"
TM_MAD = "storpool"
TYPE = "IMAGE_DS"
DISK_TYPE = "block"
BRIDGE_LIST = "node1 node2 node3"
SP_REPLICATION = 3
SP_PLACEALL = "hdd"
SP_PLACETAIL = "ssd"
EOF

# Create datastore
$ onedatastore create /tmp/ds.conf

# Verify datastore is created
$ onedatastore list

  ID NAME                SIZE AVAIL CLUSTER      IMAGES TYPE DS       TM
   0 system             98.3G 93%   -                 0 sys  -        shared
   1 default            98.3G 93%   -                 0 img  fs       shared
   2 files              98.3G 93%   -                 0 fil  fs       ssh
 100 StorPool            2.4T 99%   -                 0 img  storpool storpool
```

#### System datastore through Sunstone

Sunstone -> Infrastructure -> Datastores -> Add [+]

* Name: StorPoolSys
* Presets: StorPool
* Type: System
* Host Bridge List: node1 node2 node3
* StorPool Replication: 3
* StorPool PlaceAll: hdd
* StorPool PlaceTail: ssd
* StorPool system: ssh

#### System datastore through onedatastore

```bash
# create datastore configuration file
$ cat >/tmp/ds.conf <<_EOF_
NAME = "StorPoolSys"
TM_MAD = "storpool"
TYPE = "SYSTEM_DS"
SP_REPLICATION = 3
SP_PLACEALL = "hdd"
SP_PLACETAIL = "ssd"
SP_SYSTEM = "ssh"
_EOF_

# Create datastore
$ onedatastore create /tmp/ds.conf

# Verify datastore is created
$ onedatastore list

  ID NAME                SIZE AVAIL CLUSTER      IMAGES TYPE DS       TM
   0 system             98.3G 93%   -                 0 sys  -        shared
   1 default            98.3G 93%   -                 0 img  fs       shared
   2 files              98.3G 93%   -                 0 fil  fs       ssh
 100 StorPool            2.4T 99%   -                 0 img  storpool storpool
 101 StorPoolSys           0M -     -                 0 sys  -        storpool
 ```

Note that by default OpenNebula assumes that the Datastore is accessible by all hypervisors and all bridges. If you need to configure datastores for just a subset of the hosts check the [Cluster guide](http://docs.opennebula.org/5.4/operation/host_cluster_management/cluster_guide.html).

### Usage

Once configured, the StorPool image datastore can be used as a backend for disk images.

Non-persistent images are StorPool volumes. When a non-persistent image is used for a VM the driver clone the volume and attaches the cloned volume to the VM. When the VM is destroyed, the cloned volume is deleted.

When the StorPool driver is enabled for the SYSTEM datastore the context ISO image and the volatile disks are placed on StorPool volumes. In this case hypervisor's filesystem only VM configuration XML and the RAM dumps during migrate, suspend etc are stored. (the RAM dumps are on StorPool too when SP_CPECKPOINT* is enabled)

