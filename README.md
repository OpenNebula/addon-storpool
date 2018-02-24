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

* Working OpenNebula CLI interface with `oneadmin` account authorized to OpenNebula's core with UID=0
* Password-less SSH access from the front-end `oneadmin` user to the `node` instances.
* StorPool CLI installed, authorization token and access to the StorPool API network
* (Optional) member of the StorPool cluster with working StorPool initiator driver(storpool_block). In this case the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.

### OpenNebula Node (or Bridge Node)

* StorPool initiator driver (storpool_block)
* StorPool CLI installed, authorization token and access to the StorPool API network
* If the node is used as Bridge Node - the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* If it is only Bridge Node - it must be configured as Host in open nebula but configured to not run VMs.
* The Bridge node must have qemu-img available - used by the addon during imports to convert various source image formats to StorPool backed RAW images.
* (Recommended) Installed `qemu-kvm-ev` package from `centos-release-qemu-ev` reposytory

### StorPool cluster

A working StorPool cluster is mandatory.

## Features
Support standard OpenNebula datastore operations:
* datstore configuration via CLI and sunstone
* all Datastore MAD(DATASTORE_MAD) and Transfer Manager MAD(TM_MAD) functionality
* SYSTEM datastore on shared filesystem or ssh when TM_MAD=storpool is used
* SYSTEM datastore volatile disk and context images as StorPool block devices
* support migration from one to another SYSTEM datastore if both are with `storpool` TM_MAD
* TRIM/discard in the VM when virtio-scsi driver is in use (require `DEVICE_PREFIX=sd`)

### Extras
* all disk images are thin provisioned RAW block devices
* two different modes of disk usage reporting - LVM style and StorPool style
* different StorPool clusters as separate datastores
* migrate-live when TM_MAD='ssh' is used for SYSTEM datastore(native StorPool driver is recommended)
* limit the number of disk snapshots (per disk)
* import of VmWare (VMDK) images
* import of Hyper-V (VHDX) images
* (optional) replace "VM snapshot" interface to do atomic disk snapshots on StorPool (see limitations)
* (optional) set limit on the number of "VM snaphots"
* (optional) support VM checkpoint file directly on StorPool backed block device (see limitations)
* (optional) improved storage security: no storage management access from the hypervisors is needed so if rogue user manage to escape from the VM to the host the impact on the storage will be reduced at most to the locally attached disks(see limitations)
* (optional) helper tool to enable virtio-blk-data-plane for virtio-blk (require `DEVICE_PREFIX=vd`)
* (optional) helper tool to migrate CONTEXT iso image to StorPool backed volume (require SYSTEM_DS `TM_MAD=storpool`)

## Limitations

1. Tested only with KVM hypervisor
1. No support for VM snapshot because it is handled internally by libvirt. There is an option to use the 'VM snapshot' interface to do disk snapshots when only StorPool backed datastores are used.
1. When SYSTEM datastore integration is enabled the reported free/used/total space is the space on StorPool.
1. The extra to use VM checkpoint file directly on StorPool backed block device requires qemu-kvm-ev and StorPool CLI with access to the StorPool's management API installed on the hypervisor nodes.
1. The extra features are tested/confirmed working on CentOS. Please notify the author for any success/failure when used on another OS.

## Installation

If you are upgrading the addon please read the [Upgrade notes](#upgrade-notes) first!

### Pre-install

#### front-end dependencies

```bash
# on the front-end
yum -y install --enablerepo=epel patch git jq lz4 npm
npm install bower -g
npm install grunt-cli -g
```

#### node dependencies

 :grey_exclamation:*use when adding new hosts too*:grey_exclamation:

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

* Copy storpool's DATASTORE_MAD driver files
```bash
cp -a ~/addon-storpool/datastore/storpool /var/lib/one/remotes/datastore/

# copy xpath_multi.py
cp ~/addon-storpool/datastore/xpath_multi.py  /var/lib/one/remotes/datastore/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/datastore/storpool /var/lib/one/remotes/datastore/xpath_multi.py

```

* Copy storpool's TM_MAD driver files
```bash
cp -a ~/addon-storpool/tm/storpool /var/lib/one/remotes/tm/

# fix ownership
chown -R oneadmin.oneadmin /var/lib/one/remotes/tm/storpool
```

* Copy storpool's VM_MAD driver files
```bash
cp -a ~/addon-storpool/vmm/kvm/snapshot_* /var/lib/one/remotes/vmm/kvm/

# fix ownership
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

* Create cron job for stats polling (fix the file paths if needed)
```bash
cat >>/etc/cron.d/addon-storpool <<_EOF_
# StorPool
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=oneadmin
*/4 * * * * oneadmin /var/lib/one/remotes/datastore/storpool/monitor_helper-sync 2>&1 >/tmp/monitor_helper_sync.err
_EOF_
```

If upgrading, please delete the old style cron tasks
```bash
crontab -u oneadmin -l | grep -v monitor_helper-sync | crontab -u oneadmin -
crontab -u root -l | grep -v "storpool -j " | crontab -u root -
```

#### sunstone related pieces

* Patch and rebuild the sunstone interface
```bash
pushd /usr/lib/one/sunstone/public
# patch the sunstone interface
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.1/datastores-tab.patch

# rebuild the interface
npm install
bower --allow-root install
grunt sass
grunt requirejs
popd
```

### addon configuration
The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.

* If you plan to do live disk snapshots with fsfreeze via qemu-guest-agent but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the addon global configuration.

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

* Edit `/etc/one/oned.conf` and append the following _VM_RESTRICTED_ATTR_
```bash
cat >>/etc/one/oned.conf <<EOF
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
EOF
```

* Enable live disk snapshots support for storpool by adding `kvm-storpool` to `LIVE_DISK_SNAPSHOTS` variable in `/etc/one/vmm_exec/vmm_execrc`
```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
```

* RAFT_LEADER_IP (OpenNebula 5.4+)

The addon will try to autodetect the leader IP address from oned confioguration but if it fail set it manually in addon-storpoolrc
```bash
echo "RAFT_LEADER_IP=1.2.3.4" >> /var/lib/one/remotes/addon-storpoolrc
```

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

## Configuration

### Configuring hosts

StorPool uses resource separation utilizing the cgroup subsystem. The reserved resources should be updated in the 'Overcommitment' section on each host (RESERVED_CPU and RESERVED_MEM in pre ONE-5.4). There is a hepler script that report the values that should be set on each host. The script should be available after a host is added to OpenNebula.

```bash
# for each host do
ssh hostN /var/tmp/one/reserved.sh >reserved.tmpl
onehost update 'hostN' --append reserved.tmpl
```

### Configuring the System Datastore

This addon enables full support of transfer manager (TM_MAD) backend of type shared, ssh, or storpool for the system datastore. The system datastore will hold only the symbolic links to the StorPool block devices, so it will not take much space. See more details on the [Open Cloud Storage Setup](http://docs.opennebula.org/5.4/deployment/open_cloud_storage_setup/).

If TM_MAD is storpool it is possible to have both shared and ssh datastores, configured per cluster. To achieve this two attributes should be set:

* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But if the default behavior for SYSTEM datastores is to use `ssh`. If a SYSTEM datastore is on shared filesystem then *SP_SYSTEM=shared* should be set in the datastore configuration
* DATASTORE_LOCATION in cluster configuration should be set (pre OpenNebula 5.x+)

### Configuring the Datastore

Some configuration attributes must be set to enable an datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory for IMAGE datastores] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: Nodes to use for image datastore operations. String (1)


1. Quoted, space separated list of server hostnames which are members of the StorPool cluster. If it is left empty the front-end must have working storpool_block service (must have access to the storpool cluster) as all disk preparations will be done locally.

The following example illustrates the creation of a StorPool datastore of hybrid type with 3 replicas. In this case the datastore will use hosts node1, node2 and node3 for imports and creating images.

#### Image datastore through *Sunstone*

Sunstone -> Infrastructure -> Datastores -> Add [+]

* Name: StorPool IMAGE
* Presets: StorPool
* Type: Images
* Host Bridge List: node1 node2 node3

#### Image datastore through *onedatastore*

```bash
# create datastore configuration file
$ cat >/tmp/imageds.tmpl <<EOF
NAME = "StorPool IMAGE"
DS_MAD = "storpool"
TM_MAD = "storpool"
TYPE = "IMAGE_DS"
DISK_TYPE = "block"
BRIDGE_LIST = "node1 node2 node3"
EOF

# Create datastore
$ onedatastore create /tmp/imageds.tmpl

# Verify datastore is created
$ onedatastore list

  ID NAME                SIZE AVAIL CLUSTER      IMAGES TYPE DS       TM
   0 system             98.3G 93%   -                 0 sys  -        ssh
   1 default            98.3G 93%   -                 0 img  fs       ssh
   2 files              98.3G 93%   -                 0 fil  fs       ssh
 100 StorPool            2.4T 99%   -                 0 img  storpool storpool
```

#### System datastore through *Sunstone*

Sunstone -> Infrastructure -> Datastores -> Add [+]

* Name: StorPool SYSTEM
* Presets: StorPool
* Type: System
* Host Bridge List: node1 node2 node3

#### System datastore through *onedatastore*

```bash
# create datastore configuration file
$ cat >/tmp/ds.conf <<_EOF_
NAME = "StorPool SYSTEM"
TM_MAD = "storpool"
TYPE = "SYSTEM_DS"
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

#### Advanced addon confguration

Please follow the [advanced confguration](docs/advanced_configuration.md) guide to enable the extras that are not covered by the basic configuration.

#### Configuration tips

Please follow the  [cofiguration tips](docs/configuration_tips.md) for suggestions how to optionally reconfigure OpenNebula.

## Upgrade notes

* It is highly recommended to install qemu-kvm-ev package from centos-release-kvm-ev reposytory.

* The suggested upgrade procedure is as follow

    1. Stop all opennebula services
    2. Upgrade the opennebula packages. But do not reconfigure anything yet
    3. Upgrade the addon (checkout/clone latest from github and run install.sh)
    4. Follow the addon configuration chapter in README.md to (re)configure the extras
    5. Continue (re)configuring OpenNebula following the upstream docs

Please follow the notes for the OpenNebula version you are using.

* [OpenNebula 5.2.x or older](docs/upgrade_notes-5.2.1.md)

## StorPool naming convention

Please follow the [naming convention](docs/naming_convention.md) for details how the OpenNebula datastores, and images are mapped to StorPool.
