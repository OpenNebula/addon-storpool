# StorPool Storage Driver

## Description

The [StorPool](https://storpool.com/) datastore driver enables OpenNebula to use a StorPool storage system for storing disk images.

## Development

To contribute bug patches or new features, you can use the GitHub Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

More info:

* [How to Contribute](http://opennebula.io/contribute/)
* Support: [OpenNebula user forum](https://forum.opennebula.io/c/support)
* Development: [OpenNebula developers forum](https://forum.opennebula.io/c/development)
* Issues Tracking: GitHub issues (https://github.com/OpenNebula/addon-storpool/issues)

## Authors

* Leader: Anton Todorov (a.todorov@storpool.com)

## Compatibility

Details could be found in [Support Life Cycles for OpenNebula Environments](https://kb.storpool.com/storpool_integrations/OpenNebula/support_lifecycle.html) at the StorPool Knowledge Base.

## Requirements

### OpenNebula Front-end

* Working OpenNebula CLI interface with `oneadmin` account authorized to OpenNebula's core with UID=0
* Network access to the StorPool API management interface
* StorPool CLI installed
* Python3 installed

### OpenNebula Node

* StorPool initiator driver (storpool_block)
* If the node is used as Bridge Node - the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* If it is Bridge Node only - it must be configured as host in OpenNebula but configured to not run VMs.
* The Bridge node must have qemu-img available - used by the addon during imports to convert various source image formats to StorPool backed RAW images.

Same requirements are applied for nodes that are used as Bridge nodes.

### StorPool cluster

A working StorPool cluster is mandatory.

## Features

Standard OpenNebula datastore operations:

* essential Datastore MAD(DATASTORE_MAD) and Transfer Manager MAD(TM_MAD) functionality (see limitations)
* (optional) SYSTEM datastore volatile disks as StorPool block devices (see limitations)
* SYSTEM datastore on shared filesystem or ssh when TM_MAD=storpool is used
* SYSTEM datastore context image as a StorPool block device (see limitations)
* support migration from one SYSTEM datastore to another if both are using `storpool` TM_MAD

### Extras

* delayed termination of non-persistent images: When a VM is terminated the corresponding StorPool volume is stored as a snapshot that is deleted permanently after predefined time period (default 48 hours)
* support setting StorPool VolumeCare tags on VMs
* support setting StorPool QoS Class tags on VMs
* support different StorPool clusters as separate datastores
* support StorPool MultiCluster (technology preview)
* support multiple OpenNebula instances(controllers) in a single StorPool cluster
* import of VmWare (VMDK) images
* import of Hyper-V (VHDX) images
* partial SYSTEM datastore support (see limitations)
* (optional) set limit on the number of VM disk snapshots (per disk limits)
* (optional) helper tool to migrate CONTEXT ISO image to StorPool backed volume (require SYSTEM_DS `TM_MAD=storpool`)
* (optional) send volume snapshot to a remote StorPool cluster on image delete
* (optional) alternate local kvm/deploy script replacement that allows [tweaks](docs/deploy_tweaks.md) to the domain XML of the VMs with helper tools to enable iothreads, ioeventfd, fix virtio-scsi _nqueues_ to match the number of VCPUs, set cpu-model, etc
* (optional) support VM checkpoint file stored directly on a StorPool backed block device (see [Limitations](#Limitations))
* (optional) replace the "VM snapshot" interface scripts to do atomic disk snapshots on StorPool with option to set a limit on the number of snapshots per VM (see limitations)
* (optional) replace the <devices/video> element in the domain XML
* (optional) support for [UEFI Normal/Secure boot](docs/uefi_boot.md) with persistent UEFI NVRAM stored on StorPool backed block device
* (optional) support CDROM hotplug
* (optional) use cpu tune parameters instead/or in addition/ of cpu shares


## Limitations

1. OpenNebula temporary keep the VM checkpoint file on the Host and then (optionally) transfer it to the storage. An workaround was added on the base of OpenNebula/one#3272.
1. When SYSTEM datastore integration is enabled the reported free/used/total space of the Datastore is the space on StorPool. (On the host filesystem there are mostly symlinks and small files that do not require much disk space).
1. VM snapshotting is not possible because it is handled internally by libvirt which does not support RAW disks. It is possible to reconfigure the 'VM snapshot' interface of OpenNebula to do atomic disk snapshots in a single StorPool transaction when only StorPool backed datastores are used.
1. Only FULL opennebula backups are supported.
1. Persistent Images with SHAREABLE attribute are not supported.
1. Persistent Images with IMMUTABLE attribute are not supported.
1. Tested only with KVM hypervisor and Alma Linux 8/Ubuntu 24.04. Should work on other Linux OS.
1. The UEFI auto configuration is not supported

## Known issues

Check [docs/known_issues.md](docs/known_issues.md) for details.

## Installation

The installation instructions are for OpenNebula 6.4+.

If you are upgrading addon-storpool please read the [Upgrade notes](#upgrade-notes) first!

### Pre-install

#### front-end dependencies

```bash
# CentOS 7 front-end
yum -y install --enablerepo=epel jq xmlstarlet nmap-ncat pigz tar xmllint python36-lxml
```

```bash
# AlmaLinux 8 front-end
dnf -y install --enablerepo=epel jq xmlstarlet nmap-ncat pigz tar libxml2 python3-lxml
```

```bash
# Ubuntu 22.04/24.04 front-end
apt -y install tar jq xmlstarlet netcat pigz python3-lxml libxml2-utils
```

#### node dependencies

 :grey_exclamation:*use when adding new hosts too*:grey_exclamation:

```bash
# CentOS 7 node-kvm
yum -y install --enablerepo=epel jq pigz python36-lxml xmlstarlet tar
```

```bash
# AlmaLinux 8 node-kvm
dnf -y install --enablerepo=epel jq pigz python3-lxml xmlstarlet tar
```

```bash
# Ubuntu 22.04/24.04 node-kvm
apt -y install jq xmlstarlet pigz python3-lxml libxml2-utils tar
```

### Get the addon from github

```bash
cd ~
git clone https://github.com/OpenNebula/addon-storpool
```

### automated installation

The automated installation is best suitable for new deployments. The install script will try to do an upgrade if it detects that addon-storpool is already installed but it is possible to have errors due to non expected changes

If oned and sunstone services are on different servers it is possible to install only part of the integration:

 * set environment variable AUTOCONF=1 to enable the automatic configuration of driver defaults in the opennebula configuration

* Run the install script as 'root' user and check for any reported errors or warnings

```bash
cd addon-storpool
bash install.sh 2>&1 | tee install.log
```

### manual installation

The following commands are related to latest Stable version of OpenNebula.

#### oned related pieces

* Copy the DATASTORE_MAD driver files.

```bash
cp -a ~/addon-storpool/datastore/storpool /var/lib/one/remotes/datastore/

# copy xpath_multi.py
cp ~/addon-storpool/datastore/xpath_multi.py  /var/lib/one/remotes/datastore/
```

* Copy the TM_MAD driver files

```bash
cp -a ~/addon-storpool/tm/storpool /var/lib/one/remotes/tm/
```

* Copy the VM_MAD driver files

```bash
cp -a ~/addon-storpool/vmm/kvm/snapshot_* /var/lib/one/remotes/vmm/kvm/
```

* Prepare the fix for the volatile disks (needs to be enabled in _/etc/one/oned.conf_)

```bash
# copy the helper for deploy-tweaks
cp -a ~/addon-storpool/vmm/kvm/deploy-tweaks* /var/lib/one/remotes/vmm/kvm/
mkdir -p /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
cd /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
cp ../deploy-tweaks.d.example/volatile2dev.py .

# the local attach_disk script
cp -a ~/addon-storpool/vmm/kvm/attach_disk.storpool /var/lib/one/remotes/vmm/kvm/

# the tmsave/tmrestore scripts
cp -L ~/addon-storpool/vmm/kvm/tm* /var/lib/one/remotes/vmm/kvm/
```

* copy _reserved.sh_ helper tool to _/var/lib/one/remotes/_

```bash
cp -a ~/addon-storpool/misc/reserved.sh /var/lib/one/remotes/
```

* copy _storpool_probe.sh_ tool to _/var/lib/one/remotes/im/kvm-probes.d/host/system/_

```bash
cp -a ~/addon-storpool/misc/storpool_probe.sh /var/lib/one/remotes/im/kvm-probes.d/host/system/
```

* fix ownership of the files in _/var/lib/one/remotes/_

```bash
chown -R oneadmin.oneadmin /var/lib/one/remotes/vmm/kvm
```

* Create tmpfiles configuration to create /var/cache/addon-storpool-monitor

```bash
cp -v addon-storpool/misc/etc/tmpfiles.d/addon-storpool-monitor.conf /etc/tmpfiles.d/
systemd-tmpfiles --create
```

* Create a systemd timer for stats polling (alter the file paths if needed)

```bash
cp -v addon-storpool/misc/systemd/system/monitor_helper-sync* /etc/systemd/system/

systemctl daemon-reload

systemctl enable --now monitor_helper-sync.timer
```

### addon-storpool configuration

The global configuration of addon-storpool is in `/var/lib/one/remotes/addon-storpoolrc` file.

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

* When `storpool` backed SYSTEM datastore is used, edit `/etc/one/oned.conf` and update the ARGUMENTS of the `VM_MAD` for `KVM` to enable the deploy-tweaks script.

```
VM_MAD = [
    NAME           = "kvm",
    SUNSTONE_NAME  = "KVM",
    EXECUTABLE     = "one_vmm_exec",
    ARGUMENTS      = "-l deploy=deploy-tweaks -t 15 -r 0 -p kvm",
    ...
```
  Optionally add _attach_disk_, _tmsave_ and _tmrestore_:

```
VM_MAD = [
    NAME           = "kvm",
    SUNSTONE_NAME  = "KVM",
    EXECUTABLE     = "one_vmm_exec",
    ARGUMENTS      = "-l deploy=deploy-tweaks,attach_disk=attach_disk.storpool,save=tmsave,restore=tmrestore -t 15 -r 0 -p kvm",
    ...
```

* Edit `/etc/one/oned.conf` and append `TM_MAD_CONF` definition for StorPool

```
TM_MAD_CONF = [ NAME = "storpool", LN_TARGET = "NONE", CLONE_TARGET = "SELF", SHARED = "yes", DS_MIGRATE = "yes", DRIVER = "raw", ALLOW_ORPHANS = "yes", TM_MAD_SYSTEM = "" ]
```

* Edit `/etc/one/oned.conf` and append `DS_MAD_CONF` definition for StorPool

```
DS_MAD_CONF = [ NAME = "storpool", REQUIRED_ATTRS = "DISK_TYPE", PERSISTENT_ONLY = "NO", MARKETPLACE_ACTIONS = "export" ]
```

* Edit `/etc/one/oned.conf` and append the following _VM_RESTRICTED_ATTR_

```bash
cat >>/etc/one/oned.conf <<_EOF_
VM_RESTRICTED_ATTR = "VMSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "DISKSNAPSHOT_LIMIT"
VM_RESTRICTED_ATTR = "VC_POLICY"
VM_RESTRICTED_ATTR = "SP_QOSCLASS"
_EOF_
```

* Enable live disk snapshots support for StorPool by adding `kvm-storpool` to `LIVE_DISK_SNAPSHOTS` variable in `/etc/one/vmm_exec/vmm_execrc`

```
LIVE_DISK_SNAPSHOTS="kvm-qcow2 kvm-ceph kvm-storpool"
```

* `RAFT_LEADER_IP`

The driver will try to autodetect the leader IP address from oned configuration but if it fail set it manually in addon-storpoolrc

```bash
echo "RAFT_LEADER_IP=1.2.3.4" >> /var/lib/one/remotes/addon-storpoolrc
```

* If you plan to do live disk snapshots with _fsfreeze_ via _qemu-guest-agent_ but `SCRIPTS_REMOTE_DIR` is not the default one (if it is changed in `/etc/one/oned.conf`), define `SCRIPTS_REMOTE_DIR` in the drivers configuration.

### Post-install

* Restart `opennebula` service

```bash
systemctl restart opennebula
```
* As oneadmin user (re)sync the remote scripts to the hosts

```bash
su - oneadmin -c 'onehost sync --force'
```

* Add _oneadmin_ user to the _mysyslog_ group if available

```bash
grep -q mysyslog /etc/group && usermod -a -G mysyslog oneadmin
```

## OpenNebula Configuration

Make sure that the OpenNebula shell tools are working without additional arguments. When OpenNebula endpoint differ from default one eider create `~oneadmin/.one/one_endpoint` file or set `ONE_XMLRPC` in `addon-storpoolrc`.

### Configuring hosts

StorPool uses resource separation utilizing the cgroup subsystem. The reserved resources should be updated in the 'Overcommitment' section on each host. There is a helper script that report the values that should be set on each host. The script should be available after a host is added to OpenNebula.

```bash
# for each host do as oneadmin user
ssh hostN /var/tmp/one/reserved.sh >reserved.tmpl
onehost update 'hostN' --append reserved.tmpl
```

or, execute this scriptlet

```bash
su - oneadmin
while read -ru 4 hst; do echo "$hst"; ssh "$hst" /var/tmp/one/reserved.sh | tee "$hst.template"; onehost update "$hst" --append "$hst.template"; done 4< <(onehost list -x | xmlstarlet sel -t -m .//HOST -v NAME -n)
```

_Please note that the 'Overcommitment' change has no effect when NUMA configuration is used for the VMs_

### Configuring the System Datastore

addon-storpool driver is doing its best to support transfer manager (TM_MAD) backend of type _shared_, _ssh_, or _storpool_ (*recommended*) for the SYSTEM datastore. When only StorPool Storage is used the SYSTEM datastore will hold only symbolic links to the StorPool block devices, so it will not take much space. See more details on the [Open Cloud Storage Setup](https://docs.opennebula.io/6.0/open_cluster_deployment/storage_setup/).

* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But the default behavior for SYSTEM datastores is to use `ssh`. If a SYSTEM datastore is on shared filesystem then *SP_SYSTEM=shared* should be set in the datastore configuration

### Configuring the Datastore

Some configuration attributes must be set to enable a datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory for IMAGE datastores] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: Nodes to use for image datastore operations. String (1)


1. Quoted, space separated list of server hostnames which are members of the StorPool cluster. If it is left empty or removed the front-end must have working _storpool_block_ service (must have access to the StorPool cluster) as all disk preparations will be done locally.

After a datastore is created in OpenNebula a StorPool template must be created to represent the datastore in StorPool. The name of the template should be *one-ds-${DATASTORE_ID}* where *${DATASTORE_ID}* is the *ID* of the OpenNebula's Datastore. Please refer the *StorPool's User Guide* for details how to configure a StorPool template.

* When there are multiple OpenNebula instances using same StorPool cluster a custom prefix should be set for each opennebula instance in the _addon-storpoolrc_ configuration file

The following example illustrates the creation of a StorPool datastore. The datastore will use hosts _node1, node2 and node3_ for importing and creating images.

#### Image datastore through *Sunstone*

Sunstone -> Storage -> Datastores -> Add [+]

* Name: StorPool IMAGE
* Storage Backend: Custom
   Drivers (Datastore): Custom -> Custom DS_MAD: storpool
   Drivers (Transfer): Custom -> Custom TM_MAD: storpool
* Datastore Type: Images
* Disk type -> Block
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
storpool template one-ds-100 replication 3 placeHead hdd placeAll hdd placeTail ssd
```

#### System datastore through *Sunstone*

Sunstone -> Datastores -> Add [+]

* Name: StorPool SYSTEM
* Storage Backend: Custom
   Drivers (Transfer): Custom -> Custom TM_MAD: storpool
* Datastore Type: System
* Host Bridge List: node1 node2 node3

#### System datastore through *onedatastore*

```bash
# create datastore configuration file
$ cat >/tmp/ds.conf <<_EOF_
NAME = "StorPool SYSTEM"
TM_MAD = "storpool"
TYPE = "SYSTEM_DS"
BRIDGE_LIST = "node1 node2 node3"
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
storpool template ${ONE_PX}-ds-${DATASTORE_ID} replication 3 placeHead hdd placeAll hdd placeTail ssd
```

#### Advanced addon configuration

Please follow the [advanced configuration](docs/advanced_configuration.md) guide to enable the extras that are not covered by the basic configuration.

#### Configuration tips

Please follow the  [configuration tips](docs/configuration_tips.md) for suggestions how to optionally reconfigure OpenNebula.

## Upgrade notes

* The suggested upgrade procedure is as follow

    1. Stop all opennebula services
    2. Upgrade the opennebula packages. But do not reconfigure anything yet
    3. Upgrade the addon (checkout/clone latest from github and run _AUTOCONF=1 bash install.sh_)
    4. Follow the addon configuration chapter in README.md to (re)configure the driver
    5. Continue (re)configuring OpenNebula following the upstream docs

* After upgrade please run misc/tagVolumes.sh to update/apply the common tags for volumes/snapshots

* Remove old _cron_ configuration files `/etc/cron.d/vc-policy`, `/etc/cron.d/addon-storpool`

* Run the following code to update the StorPool volume tags

```bash
source /var/lib/one/remotes/addon-storpoolrc && while read -r -u 4 volume; do storpool volume "${volume}" update tag nloc=${ONE_PX:-one} tag virt=one; done 4< <(storpool -B -j volume list | jq -r --arg onepx "${ONE_PX:-one}" '.data[]|select(.name|startswith($onepx))|.name')
```

## StorPool naming convention

Please follow the [naming convention](docs/naming_convention.md) for details on how the OpenNebula's datastores and images are mapped to the StorPool Templates, Volumes and Snapshots.

## Known issues

* In release 19.03.2 the volume names of the attached CDROM images was changed. A separate volume with a unique name is created for each attachment. This could lead to errors when using restore with the alternate VM snapshot interface enabled. The workaround is to manually create/or rename/ a snapshot of the desired CDROM volume following the new naming convention. The migration to the new CDROM's volume naming convention is integrated so there is no manual operations needed.

## More information

[Tips](docs/tips.md)
