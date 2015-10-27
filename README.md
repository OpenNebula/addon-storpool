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

This add-on is compatible with OpenNebula 4.10, 4.12, 4.14 and StorPool 15.02+.

## Requirements

### OpenNebula Front-end

* Password-less SSH access from the front-end `oneadmin` user to the `node` instances.
* StorPool CLI, API access and token

### OpenNebula Node

* The OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* StorPool initiator driver (storpool_block)
* StorPool CLI, API access and token

### StorPool cluster

A working StorPool cluster is required.

## Features
* support for datstore configuration via sunstone
* support all Datastore MAD(DATASTORE_MAD) and Transfer Manager MAD(TM_MAD) functionality
* extend migrate-live when ssh TM_MAD is used for SYSTEM datastore
* support SYSTEM datastore volatile disks and context image as StorPool block devices (see limitations)
* imported images from the markeplace are thin provisioned (require StorPool 15.03+)

## Limitations

1. tested only with the KVM hypervisor
1. no support for VM snapshot because it is handled internally by libvirt
1. reported free/used/total space when used for SUSTEM datastore is not propper because the volatile disks and the context image are expected to be files instead of a block device. Extra external monitoring of space usage should be implemented.


## Installation

### Pre-install

* Install required dependencies
```bash
# patch
yum -y install patch git jq
# node, bower, grunt
yum -y install npm
npm install bower -g
npm install grunt-cli -g
```

* Clone the addon-storpool
```bash
git clone https://github.com/OpenNebula/addon-storpool
```

### automated installation
The automated instllation is best suitable for new installations. The install script will try to do an upgrade if it detects that addon-storpool is already installed but this feature is not tested well

* Run the install script and chek for any reported errors or warnings
```bash
bash ~/addon-storpool/install.sh
```
If oned and sunstone services are on different servers it is possible to install only part of the integration:
 * set environment variable SKIP_SUNSTONE=1 to skip the sunstone integration
 * set environment variable SKIP_ONED=1 to skip the oned integration

### manual installation

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
* Fix ssh TM_MAD driver
(When upgrading from previous version remove old code between the header comments and `exit 0` line)
```bash
# create pre/post migrate hook folders
mkdir -p /var/lib/one/remotes/tm/ssh/{pre,post}migrate.d

pushd /var/lib/one/remotes/tm/ssh/premigrate.d
ln -s ../../storpool/premigrate premigrate-storpool
popd

pushd /var/lib/one/remotes/tm/ssh/postmigrate.d
ln -s ../../storpool/postmigrate postmigrate-storpool
popd

#edit /var/lib/one/remotes/tm/ssh/premigrate
# change shebang from #!/bin/sh to #!/bin/bash
sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' /var/lib/one/remotes/tm/ssh/premigrate

# add code to call scripts from ./premigrate.d
# [ -d "${0}.d" ] && for hook in "${0}.d"/* ; do source "$hook"; done
sed -i -e 's|^exit 0|[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done\nexit 0|' /var/lib/one/remotes/tm/ssh/premigrate

#edit /var/lib/one/remotes/tm/ssh/postmigrate
# change shebang from #!/bin/sh to #!/bin/bash
sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' /var/lib/one/remotes/tm/ssh/postmigrate

# add code to call scripts from ./postmigrate.d
# [ -d "${0}.d" ] && for hook in "${0}.d"/* ; do source "$hook"; done
sed -i -e 's|^exit 0|[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done\nexit 0|' /var/lib/one/remotes/tm/ssh/postmigrate
```
* Fix shared TM_MAD driver
(When upgrading from previous version remove old code between the header comments and `exit 0` line)
```bash
# create pre/post migrate hook folders
mkdir -p /var/lib/one/remotes/tm/shared/{pre,post}migrate.d

pushd /var/lib/one/remotes/tm/shared/premigrate.d
ln -s ../../storpool/premigrate premigrate-storpool
popd

pushd /var/lib/one/remotes/tm/shared/postmigrate.d
ln -s ../../storpool/postmigrate postmigrate-storpool
popd

#edit /var/lib/one/remotes/tm/ssh/premigrate
# change shebang from #!/bin/sh to #!/bin/bash
sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' /var/lib/one/remotes/tm/shared/premigrate

# add code to call scripts from ./premigrate.d
# [ -d "${0}.d" ] && for hook in "${0}.d"/* ; do source "$hook"; done
sed -i -e 's|^exit 0|[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done\nexit 0|' /var/lib/one/remotes/tm/shared/premigrate

#edit /var/lib/one/remotes/tm/shared/postmigrate
# change shebang from #!/bin/sh to #!/bin/bash
sed -i -e 's|^#!/bin/sh$|#!/bin/bash|' /var/lib/one/remotes/tm/shared/postmigrate

# add code to call scripts from ./postmigrate.d
# [ -d "${0}.d" ] && for hook in "${0}.d"/* ; do source "$hook"; done
sed -i -e 's|^exit 0|[ -d \"\${0}.d\" ] \&\& for hook in \"\${0}.d\"/* ; do source \"\$hook\"; done\nexit 0|' /var/lib/one/remotes/tm/shared/postmigrate
```
* Patch IM_MAD/kvm-probes.d/monitor_ds.sh
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/im/4.14/00-monitor_ds.patch
popd
```
* Patch VMM_MAD/kvm/poll
```bash
pushd /var/lib/one
patch -p0 <~/addon-storpool/patches/vmm/4.14/01-kvm_poll.patch
popd
```
* Copy misc/poll_disk_info to /usr/bin
```bash
cp ~/addon-storpool/vmm/kvm/poll_disk_info /var/lib/one/remotes/vmm/kvm/
```
* Copy FT hook
```bash
cp ~/addon-storpool/hooks/ft/sp_host_error.rb /var/lib/one/remotes/hooks/ft/
```

#### sunstone related pieces

* Patch and rebuild sunstone interface
```bash
pushd /usr/lib/one/sunstone/public
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/4.14/00-datastores-tab.js.patch
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/4.14/01-disk-tab.hbs.patch

# rebuild
npm install
bower --allow-root install
grunt sass
grunt requirejs

popd
```

### addon configuration
* Add the `oneadmin` user to group `disk` on all nodes
```bash
usermod -a -G disk oneadmin
```
* Edit `/etc/one/oned.conf` and add storpool to `TM_MAD` arguments
```
TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,dev,storpool"
]
```
* Edit `/etc/one/oned.conf` and add storpool to `DATASTORE_MAD` arguments
```
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,dev,storpool"
]
```
* Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` for storpool
```
TM_MAD_CONF = [
    name = "storpool", ln_target = "NONE", clone_target = "SELF", shared = "yes"
]
```
To enable live disk snapshots support for storpool
* Edit `/etc/one/kvm_exec/kvm_execrc` and add `kvm-storpool` to `LIVE_DISK_SNAPSHOTS`
```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-storpool"
```
* Edit `/etc/one/oned.conf` and add `-i` argument to `VM_MAD`
```
VM_MAD = [
    name       = "kvm",
    executable = "one_vmm_exec",
    arguments  = "-i -t 15 -r 1 kvm",
    default    = "vmm_exec/vmm_exec_kvm.conf",
    type       = "kvm" ]
```
To enable the StorPool compatible Fault Tolerance `HOST_HOOK`
* Edit `/etc/one/oned.conf` and define `HOST_HOOK` as follow
```
HOST_HOOK = [
    name      = "error",
    on        = "ERROR",
    command   = "ft/sp_host_error.rb",
    arguments = "$ID -p 2",
    remote    = "no" ]
```

The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.
* Define `SCRIPTS_REMOTE_DIR` if it is changed in `/etc/one/oned.conf` if you plan to do live disk snapshots with fsfreeze via qemu-guest-agent
* To chage disk space usage reporting to be as LVM is reporting it define `SP_SPACE_USED_LVMWAY` variable to anything

### Post-install
* Restart `opennebula` and `opennebula-sunstone` services
```bash
service opennebula restart
service opennebuka-sunstone restart
```



## Upgrade

Follow the installation procedure. If something can not be upgraded automatically a note is printed with hints what should be done manually. Take care of such notes and follow them.

## Configuration

### Configuring the System Datastore

This addon enables full support of transfer manager (TM_MAD) backend of type shared, ssh, or storpol for the system datastore. The system datastore will hold only the symbolic links to the StorPool block devices, so it will not take much space. See more details on the [System Datastore Guide](http://docs.opennebula.org/4.10/administration/storage/system_ds.html).

If TM_MAD is storpool it is possible to have both shared and ssh datastores, configured per cluster. To achieve this two attributes should be set:

* DATASTORE_LOCATION in cluster configuration should be set
* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But if the given datastore is not shared *SP_SYSTEM=ssh* should be set in datastore configuration


### Configuring the Datastore

Some configuration attributes must be set to enable an datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: [mandatory] Nodes to use for image datastore operations. String (1)
* **SP_REPLICATION**: [mandatory] The StorPool replication level for the datastore. Number (2)
* **SP_PLACEALL**: [mandatory] The name of StorPool placement group of disks where to store data. String (3)
* **SP_PLACETAIL**: [optional] The name of StorPool placement group of disks from where to read data. String (4)
* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS. Global datastore configuration for storpol TM_MAD is with *SHARED=yes* set. If the datastore is not on shared filesystem this parameter should be set to *SP_SYSTEM=ssh* to copy non-storpool files from one node to another.

1. Quoted, space separated list of server hostnames which are members of the StorPool cluster.
1. The replication level defines how many separate copies to keep for each data block. Supported values are: `1`, `2` and `3`.
1. The PlaceAll placement group is defined in StorPool as list of drives where to store the data.
1. The PlaceTail placement group is defined in StorPool as list of drives. used in StorPool hybrid setup. If the setup is not of hybrid type leave blank or same as **SP_PLACEALL**

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
$ cat >/tmp/ds.conf <<EOF
NAME = "StorPoolSys"
TM_MAD = "storpool"
TYPE = "SYSTEM_DS"
SP_REPLICATION = 3
SP_PLACEALL = "hdd"
SP_PLACETAIL = "ssd"
SP_SYSTEM = "ssh"
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
 101 StorPoolSys           0M -     -                 0 sys  -        storpool
 ```

Note that by default OpenNebula assumes that the Datastore is accessible by all hypervisors and all bridges. If you need to configure datastores for just a subset of the hosts check the [Cluster guide](http://opennebula.org/documentation:rel4.4:cluster_guide).

### Usage

Once configured, the StorPool image datastore can be used as a backend for disk images.

Non-persistent images are StorPool volumes. When you use a non-persistent image for a VM the driver creates a new temporary volume and attaches the new volume to the VM. When the VM is destroyed, the temporary volume is deleted.

When the StorPool driver is enabled for System datastore the context ISO image and the volatile disks are placed on StorPool volumes. In this case on the disk is kept only VM configuration XML and the RAM dumps during migrate, suspend etc.
