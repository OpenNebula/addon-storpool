# OpenNebula configuration

Make sure that the OpenNebula shell tools are working without additional arguments. When OpenNebula endpoint differ from default one eider create `~oneadmin/.one/one_endpoint` file or set `ONE_XMLRPC` in `addon-storpoolrc`.

## Prerequisites

The driver is installed as described in [Installation and upgrade](installation.md).

## Configuring hosts

StorPool uses resource separation utilizing the cgroup subsystem. The reserved resources should be updated in the 'Overcommitment' section on each host. There is a helper script that report the values that should be set on each host. The script should be available after a host is added to OpenNebula.

```bash
 for each host do as oneadmin user
ssh hostN /var/tmp/one/reserved.sh >reserved.tmpl
onehost update 'hostN' --append reserved.tmpl
```

or, execute this scriptlet

```bash
su - oneadmin
while read -ru 4 hst; do echo "$hst"; ssh "$hst" /var/tmp/one/reserved.sh | tee "$hst.template"; onehost update "$hst" --append "$hst.template"; done 4< <(onehost list -x | xmlstarlet sel -t -m .//HOST -v NAME -n)
```

_Please note that the 'Overcommitment' change has no effect when NUMA configuration is used for the VMs_

## Configuring the System Datastore

addon-storpool driver is doing its best to support transfer manager (TM_MAD) backend of type _shared_, _ssh_, or _storpool_ (*recommended*) for the SYSTEM datastore. When only StorPool Storage is used the SYSTEM datastore will hold only symbolic links to the StorPool block devices, so it will not take much space. See more details on the [Open Cloud Storage Setup](https://docs.opennebula.io/6.0/open_cluster_deployment/storage_setup/).

* By default the storpool TM_MAD is with enabled SHARED attribute (*SHARED=YES*). But the default behavior for SYSTEM datastores is to use `ssh`. If a SYSTEM datastore is on shared filesystem then *SP_SYSTEM=shared* should be set in the datastore configuration

## Configuring the Datastore

Some configuration attributes must be set to enable a datastore as StorPool enabled one:

* **DS_MAD**: [mandatory] The DS driver for the datastore. String, use value `storpool`
* **TM_MAD**: [mandatory] Transfer driver for the datastore. String, use value `storpool`
* **DISK_TYPE**: [mandatory for IMAGE datastores] Type for the VM disks using images from this datastore. String, use value `block`
* **BRIDGE_LIST**: Nodes to use for image datastore operations. String (1)


1. Quoted, space separated list of server hostnames which are members of the StorPool cluster. If it is left empty or removed the front-end must have working _storpool_block_ service (must have access to the StorPool cluster) as all disk preparations will be done locally.

After a datastore is created in OpenNebula a StorPool template must be created to represent the datastore in StorPool. The name of the template should be *one-ds-${DATASTORE_ID}* where *${DATASTORE_ID}* is the *ID* of the OpenNebula's Datastore. Please refer the *StorPool's User Guide* for details how to configure a StorPool template.

* When there are multiple OpenNebula instances using same StorPool cluster a custom prefix should be set for each opennebula instance in the _addon-storpoolrc_ configuration file

The following example illustrates the creation of a StorPool datastore. The datastore will use hosts _node1, node2 and node3_ for importing and creating images.

### Image datastore through *Sunstone*

Sunstone -> Storage -> Datastores -> Add [+]

* Name: StorPool IMAGE
* Storage Backend: Custom
   Drivers (Datastore): Custom -> Custom DS_MAD: storpool
   Drivers (Transfer): Custom -> Custom TM_MAD: storpool
* Datastore Type: Images
* Disk type -> Block
* Host Bridge List: node1 node2 node3

### Image datastore through *onedatastore*

```bash
 create datastore configuration file
$ cat >/tmp/imageds.tmpl <<EOF
NAME = "StorPool IMAGE"
DS_MAD = "storpool"
TM_MAD = "storpool"
TYPE = "IMAGE_DS"
DISK_TYPE = "block"
BRIDGE_LIST = "node1 node2 node3"
EOF

 Create datastore
$ onedatastore create /tmp/imageds.tmpl

 Verify datastore is created
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

### System datastore through *Sunstone*

Sunstone -> Datastores -> Add [+]

* Name: StorPool SYSTEM
* Storage Backend: Custom
   Drivers (Transfer): Custom -> Custom TM_MAD: storpool
* Datastore Type: System
* Host Bridge List: node1 node2 node3

### System datastore through *onedatastore*

```bash
 create datastore configuration file
$ cat >/tmp/ds.conf <<_EOF_
NAME = "StorPool SYSTEM"
TM_MAD = "storpool"
TYPE = "SYSTEM_DS"
BRIDGE_LIST = "node1 node2 node3"
_EOF_

 Create datastore
$ onedatastore create /tmp/ds.conf

 Verify datastore is created
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

## More information

* See the [advanced configuration](advanced_configuration.md) guide to enable the extras that are not covered by the basic configuration.
* See the  [configuration tips](configuration_tips.md) for suggestions how to optionally reconfigure OpenNebula.

