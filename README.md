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

This add-on is compatible with OpenNebula 4.10, 4.12 and StorPool 15.02+.

## Requirements

### OpenNebula Front-end

* Password-less SSH access from the front-end `oneadmin` user to the `node` instances.
* StorPool API access and token

### OpenNebula Node

* The OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* StorPool initiator driver (storpool_block)
* StorPool CLI, API access and token

### StorPool cluster

A working StorPool cluster is required.

## Limitations

1. tested only with the KVM hypervisor
1. no support for VM snapshot because it is handled internally by libvirt
1. imported images are thick provisioned


## Installation

* Install python bindings for StorPool
```bash
pip install storpool
```
* Clone the addon-storpool
```bash
cd /usr/src
git clone https://github.com/OpenNebula/addon-storpool
```
* Run the install script and chek for any reported errors or warnings
```bash
bash addon-storpool/install.sh
```
* Restart `opennebula` and `opennebula-sunstone` services

## Configuration

### Configuring the System Datastore

This addon enables full support of transfer manager (TM_MAD) backend of type shared, ssh, or storpol for the system datastore. The system datastore will hold only the symbolic links to the StorPool block devices, so it will not take much space. See more details on the [System Datastore Guide](http://docs.opennebula.org/4.10/administration/storage/system_ds.html).

If TM_MAD is storpool it is possible to have both shared and ssh datastores, configured per cluster. To achieve this two attributes should be set:

* DATASTORE_LOCATION in cluster configuration should be set
* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But if the given datastore is not shared *SP_SYSTEM=ssh* should be set in datastore configuration


### Configuring the Image Datastore

Some configuration attributes must be set to enable an image datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: [mandatory] Nodes to use for image datastore operations. String (1)
* **SP_REPLICATION**: [mandatory] The StorPool replication level for the datastore. Number (2)
* **SP_PLACEALL**: [mandatory] The name of StorPool placement group of disks where to store data. String (3)
* **SP_PLACETAIL**: [optional] The name of StorPool placement group of disks from where to read data. String (4)
* **SP_API_HTTP_HOST**: [optional] The ip of the StorPool API. IP address, defaults to 127.0.0.1 (5)
* **SP_API_HTTP_PORT**: [optional] The port StorPool API listen on. Number, defaults to 81 (6)
* **SP_AUTH_TOKEN**: [optional] StorPool API authentication token. String (7)
* **SP_SYSTEM**: [optional] Used when StorPool datastore is used as SYSTEM_DS. Global datastore configuration for storpol TM_MAD is with *SHARED=yes* set. If the datastore is not on shared filesystem this parameter should be set to *SP_SYSTEM=ssh* to copy non-storpool files from one node to another.

1. Quoted, space separated list of server hostnames which are members of the StorPool cluster.
1. The replication level defines how many separate copies to keep for each data block. Supported values are: `1`, `2` and `3`.
1. The PlaceAll placement group is defined in StorPool as list of drives where to store the data.
1. The PlaceTail placement group is defined in StorPool as list of drives. used in StorPool hybrid setup. If the setup is not of hybrid type leave blank or same as **SP_PLACEALL**
1. It must match **SP_API_HTTP_HOST** in storpool.conf. Useful when StorPool is not installed on the front end.
1. It must match **SP_API_HTTP_PORT** in storpool.conf. Useful when StorPool is not installed on the front end.
1. It must match **SP_AUTH_TOKEN** in storpool.conf. Useful when StorPool is not installed on the front end.

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
