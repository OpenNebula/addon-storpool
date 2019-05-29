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
* essencial Datastore MAD(DATASTORE_MAD) and Transfer Manager MAD(TM_MAD) functionality (see limitations)
* SYSTEM datastore on shared filesystem or ssh when TM_MAD=storpool is used
* SYSTEM datastore volatile disks as StorPool block devices (see limitations)
* SYSTEM datastore context image as a StorPool block device
* support migration from one to another SYSTEM datastore if both are with `storpool` TM_MAD

### Extras
* all disk images are thin provisioned RAW block devices
* support different StorPool clusters as separate datastores
* import of VmWare (VMDK) images
* import of Hyper-V (VHDX) images
* alternate kvm/deploy script that alows tweaks to the domain XML of the VMs
* (optional) replace "VM snapshot" interface to do atomic disk snapshots on StorPool (see limitations)
* (optional) set limit on the number of "VM snaphots"
* (optional) set limit on the number of disk snapshots (per disk)
* (optional) support VM checkpoint file directly on StorPool backed block device (see limitations)
* (optional) helper tool to enable iothreads, ioeventfd, fix nqueues to match the number of VCPUs, set cpu-model by altering libvirt's domain XML
* (optional) helper tool to migrate CONTEXT iso image to StorPool backed volume (require SYSTEM_DS `TM_MAD=storpool`)

## Limitations

1. Tested only with KVM hypervisor
1. No support for VM snapshot because it is handled internally by libvirt. There is an option to use the 'VM snapshot' interface to do disk snapshots when only StorPool backed datastores are used.
1. Image export is disabled until issue OpenNebula/one#1159 is resolved
1. When SYSTEM datastore integration is enabled the reported free/used/total space is the space on StorPool. (On the host filesystem there are mostly symlinks and small files that do not require much disk space)
1. OpenNebula define the volatile disks as files in the domain XML. Latest libvirt do check and forbid live migrate without the `--unsafe` flag set. The workaround is to replace the deploy script with a tweaked one.
1. The option to use VM checkpoint file directly on a StorPool backed block device requires `qemu-kvm-ev` and StorPool CLI with access to the StorPool's management API installed on the hypervisor nodes.
1. The extra features are tested/confirmed working on CentOS.

## Installation

The installation instructions are for OpenNebula 5.8+.

For OpenNebula 5.6.x please use the following [installation instructions](docs/install-5.6.0.md)
For OpenNebula 5.4.x please use the following [installation instructions](docs/install-5.4.0.md)

If you are upgrading the addon please read the [Upgrade notes](#upgrade-notes) first!

### Pre-install

#### front-end dependencies

```bash
# on the front-end
yum -y install --enablerepo=epel patch git jq lz4 npm
```

#### node dependencies

 :grey_exclamation:*use when adding new hosts too*:grey_exclamation:

```bash
yum -y install --enablerepo=epel jq lz4 python-lxml
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

* Prepare the fix for the volatile disks (needs to be enabled in _/etc/one/oned.conf_)
```bash
# copy the helper for deploy-local
cp -a ~/addon-storpool/vmm/kvm/deploy-tweaks* /var/lib/one/remotes/vmm/kvm/
mkdir -p /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
cp -v /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d{.example,}/volatile2dev.py

# patch attach_disk
cd /var/lib/one/remotes/vmm/kvm
patch -p1 < ~/addon-storpool/patches/vmm/5.6.0/attach_disk.patch
```

* Patch IM_MAD/kvm-probes.d/monitor_ds.sh
OpenNebula collect datastore space only for integrated drivers. This patch enable reporting of datastore space from StorPool.
```bash
pushd /var/lib/one
patch -p0 <~/addon-storpool/patches/im/5.2/00-monitor_ds.patch
popd
```

* Patch TM_MAD/shared/monitor
OpenNebula collect disk stats for integrated drivers. This patch enable disks stats reporting for addon drivers.
```bash
pushd /var/lib/one
patch --backup -p0 <~/addon-storpool/patches/tm/5.0/00-shared-monitor.patch
popd
```

* Patch TM_MAD/ssh/monitor_ds
OpenNebula collect disk stats for integrated drivers. This patch enable disks stats reporting for addon drivers.
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
# First do a backup of the sunstone/public folder
cp -a /usr/lib/one/sunstone/public{,-bak-$(date +%s)}

pushd /usr/lib/one/sunstone/public

# patch the sunstone interface to update the Datastore Wizard to support StorPool
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.1/datastores-tab.patch
# patch the sunstone interface to enable VM snapshots deletion when VM is powered off
patch -b -V numbered -N -p0 <~/addon-storpool/patches/sunstone/5.4.1/vms-tab.patch

# rebuild the interface
./build.sh -d
export PATH=$PATH:$PWD/node_modules/.bin
./build.sh

popd

# Don't forget to delete the created backup after configmig that sunstone works
# rm -fr /usr/lib/one/sunstone/public-bak-*
```

### addon configuration
The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.


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

* Edit `/etc/one/oned.conf` and update the ARGUMENTS of the `VM_MAD` for `KVM` to enable the deploy-tweaks script

```
VM_MAD = [
    NAME           = "kvm",
    SUNSTONE_NAME  = "KVM",
    EXECUTABLE     = "one_vmm_exec",
    ARGUMENTS      = "-t 15 -r 0 kvm -l deploy=deploy-tweaks",
    ...
```

* Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` definition for StorPool
```
TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes", TM_MAD_SYSTEM = "ssh,shared", LN_TARGET_SSH = "NONE", CLONE_TARGET_SSH = "SELF", DISK_TYPE_SSH = "BLOCK", LN_TARGET_SHARED = "NONE", CLONE_TARGET_SHARED = "SELF", DISK_TYPE_SHARED = "BLOCK" ]
```

With OpenNebula 5.8+ The IMAGE datastore backed by StorPool must have TM_MAD for the SYSTEM datastore whitelisted. `storpool`, `ssh` and `shared` are white listed by default.


* Edit `/etc/one/oned.conf` and append DS_MAD_CONF definition for StorPool
```
DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "" ]
```

* Edit `/etc/one/oned.conf` and append the following _VM_RESTRICTED_ATTR_
```bash
cat >>/etc/one/oned.conf <<EOF
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "T_CPU_THREADS"
VM_RESTRICTED_ATTR = "T_CPU_SOCKETS"
VM_RESTRICTED_ATTR = "T_CPU_FEATURES"
VM_RESTRICTED_ATTR = "T_CPU_MODE"
VM_RESTRICTED_ATTR = "T_CPU_MODEL"
VM_RESTRICTED_ATTR = "T_CPU_VENDOR"
VM_RESTRICTED_ATTR = "T_CPU_CHECK"
VM_RESTRICTED_ATTR = "T_CPU_MATCH"
VM_RESTRICTED_ATTR = "T_VF_MACS"
VM_RESTRICTED_ATTR = "T_CPUTUNE_SHARES"
VM_RESTRICTED_ATTR = "T_CPUTUNE_MUL"

EOF
```

* Enable live disk snapshots support for StorPool by adding `kvm-storpool` to `LIVE_DISK_SNAPSHOTS` variable in `/etc/one/vmm_exec/vmm_execrc`
```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
```

* RAFT_LEADER_IP

The addon will try to autodetect the leader IP address from oned configuration but if it fail set it manually in addon-storpoolrc
```bash
echo "RAFT_LEADER_IP=1.2.3.4" >> /var/lib/one/remotes/addon-storpoolrc
```

* If you plan to do live disk snapshots with fsfreeze via qemu-guest-agent but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the addon global configuration.

### Post-install
* Restart `opennebula` and `opennebula-sunstone` services
```bash
service opennebula restart
service opennebula-sunstone restart
```
* As oneadmin user (re)sync the remote scripts
```bash
su - oneadmin -c 'onehost sync --force'
```

* Check that Sunstone works and the _New Datastore Wizard_ is showing StorPool in the _Storage backend_. Remove the backup of sunstone/public folder.
```bash
rm -fr /usr/lib/one/sunstone/public-bak-*
```

## Configuration

Make sure that the OpenNebula shell tools are working without additional argumets. When OpenNebula endpoint differ from default one eider create `~oneadmin/.one/one_endpoint` file or set `ONE_XMLRPC` in `addon-storpoolrc`.


### Configuring hosts

StorPool uses resource separation utilizing the cgroup subsystem. The reserved resources should be updated in the 'Overcommitment' section on each host (RESERVED_CPU and RESERVED_MEM in pre ONE-5.4). There is a hepler script that report the values that should be set on each host. The script should be available after a host is added to OpenNebula.

```bash
# for each host do as oneadmin user
ssh hostN /var/tmp/one/reserved.sh >reserved.tmpl
onehost update 'hostN' --append reserved.tmpl
```

### Configuring the System Datastore

This addon enables full support of transfer manager (TM_MAD) backend of type shared, ssh, or storpool (*recommended*) for the system datastore. The system datastore will hold only the symbolic links to the StorPool block devices, so it will not take much space. See more details on the [Open Cloud Storage Setup](http://docs.opennebula.org/5.6/deployment/open_cloud_storage_setup/).

If TM_MAD is storpool it is possible to have both shared and ssh datastores, configured per cluster. To achieve this two attributes should be set:

* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But the default behavior for SYSTEM datastores is to use `ssh`. If a SYSTEM datastore is on shared filesystem then *SP_SYSTEM=shared* should be set in the datastore configuration

### Configuring the Datastore

Some configuration attributes must be set to enable a datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory for IMAGE datastores] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: Nodes to use for image datastore operations. String (1)


1. Quoted, space separated list of server hostnames which are members of the StorPool cluster. If it is left empty or removed the front-end must have working storpool_block service (must have access to the storpool cluster) as all disk preparations will be done locally.

After datastore is created in OpenNebula a StorPool template must be created to represent the datastore in StorPool. The name of the template must be *one-ds-<DATASTORE_ID>* where *<DATASTORE_ID>* is the *ID* of the OpenNebula's Datastore. Please refer the *StorPool's User Guide* for details how to configure a StorPool template.

The following example illustrates the creation of a StorPool datastore. The datastore will use hosts node1, node2 and node3 for importing and creating images.

#### Image datastore through *Sunstone*

Sunstone -> Storage -> Datastores -> Add [+]

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

Create a StorPool template for the datastore with ID 100:

```bash
storpool template one-ds-100 replication 3 placeAll hdd placeTail ssd
```

#### System datastore through *Sunstone*

Sunstone -> Datastores -> Add [+]

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

Create a StorPool template for the datastore with ID 101:

```bash
storpool template one-ds-101 replication 3 placeAll hdd placeTail ssd
```

#### Advanced addon configuration

Please follow the [advanced configuration](docs/advanced_configuration.md) guide to enable the extras that are not covered by the basic configuration.

#### Configuration tips

Please follow the  [configuration tips](docs/configuration_tips.md) for suggestions how to optionally reconfigure OpenNebula.

## Upgrade notes

* It is highly recommended to install `qemu-kvm-ev` package from `centos-release-kvm-ev` reposytory.

* The suggested upgrade procedure is as follow

    1. Stop all opennebula services
    2. Upgrade the opennebula packages. But do not reconfigure anything yet
    3. Upgrade the addon (checkout/clone latest from github and run install.sh)
    4. Follow the addon configuration chapter in README.md to (re)configure the extras
    5. Continue (re)configuring OpenNebula following the upstream docs

* With OpenNebula 5.8+ The IMAGE datastore backed by StorPool must have TM_MAD for the SYSTEM datastore whitelisted.


Please follow the upgrade notes for the OpenNebula version you are using.

* [OpenNebula 5.2.x or older](docs/upgrade_notes-5.2.1.md)

## StorPool naming convention

Please follow the [naming convention](docs/naming_convention.md) for details the OpenNebula's datastores and images are mapped to StorPool.

## Known issues

* In relase 19.03.2 the naming of the attached CDROM images was changed. A separate volume with a unique name is created for each attachment. This could lead to errors when using restore with the alternate VM snapshot interface enabled. The workaround is to manually create/or rename/ a snapshot of the desired CDROM volume following the new naming convention. The migration to the new CDROM's volume naming convention is integrated so there is no manual operations needed.

* Recent version of libvirt has more strict checks of the domain xml and do not aloow live migration when there are file backed VM disks that are not on shared filesystem. The definition of the volatile disks that OpenNebula create are with hard-coded type 'file' that conflict with libvirt. There is a fix for this in addon-storpool 19.04.3+ but it will not alter the currenlty running VM's. A workaround is to patch _vmm/kvm/migrate_ and add a check that enable `--unsafe` option if all disks are with disabled cache (`cache="none"`).
Add the following line just before the line that do the VM migration:

```bash
(virsh --connect $LIBVIRT_URI dumpxml $deploy_id 2>/dev/null || echo '<a><disk device="disk"><driver cache="writeback"/></disk></a>') | xmllint --xpath '(//disk[@device="disk"]/driver[not(@cache="none")])' - >/dev/null 2>&1 || MIGRATE_OPTIONS+=" --unsafe"

```
