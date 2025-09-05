# StorPool storage driver

[StorPool](https://storpool.com/) is a block storage software (software-defined storage solution). It runs on standard x86 servers, converting them into high-performance and highly available virtual (SAN) storage arrays. It can also run beside compute workloads in a hyper-converged manner.

The StorPool datastore driver enables OpenNebula to use a StorPool storage system for storing disk images.
The documentation of the driver is available at [StorPool's Knowledge Base](https://kb.storpool.com/storpool_integrations/OpenNebula/).

## Development

To contribute bug patches or new features, you can use the GitHub Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.

More info:

* [How to Contribute](http://opennebula.io/contribute/)
* Support: [OpenNebula user forum](https://forum.opennebula.io/c/integration/33)
* Issues Tracking: [GitHub issues](https://github.com/OpenNebula/addon-storpool/issues)

## Authors

* Leader: Anton Todorov (a.todorov@storpool.com)

## Requirements

### OpenNebula Front-end

* Working OpenNebula CLI interface with `oneadmin` account authorized to OpenNebula's core with UID=0
* Network access to the StorPool API management interface
* StorPool CLI installed
* Python3 installed

### OpenNebula Node

* StorPool initiator driver (`storpool_block`).
* If the node is used as Bridge Node - the OpenNebula admin account `oneadmin` must be member of the 'disk' system group to have access to the StorPool block device during image create/import operations.
* If it is Bridge Node only - it must be configured as host in OpenNebula, but configured to not run VMs.
* The Bridge node must have `qemu-img` available. It is used by the addon during imports to convert various source image formats to StorPool backed RAW images.

The same requirements are applied for nodes that are used as Bridge nodes.

### StorPool cluster

A working StorPool cluster is mandatory.

## Features

Standard OpenNebula datastore operations:

* Essential Datastore MAD (`DATASTORE_MAD`) and Transfer Manager MAD (`TM_MAD`) functionality (see limitations).
* (optional) SYSTEM datastore volatile disks as StorPool block devices (see limitations).
* SYSTEM datastore on shared filesystem or ssh when `TM_MAD=storpool` is used.
* SYSTEM datastore context image as a StorPool block device (see limitations).
* Support migration from one SYSTEM datastore to another if both are using `storpool` TM_MAD.

### Extras

* Delayed termination of non-persistent images: When a VM is terminated, the corresponding StorPool volume is stored as a snapshot that is deleted permanently after predefined time period (default 48 hours).
* Support for setting StorPool VolumeCare tags on VMs, see [StorPool VolumeCare](docs/volumecare.md).
* Support for setting StorPool QoS Class tags on VMs, see [StorPool QoS class configuration](docs/qosclass.md).
* Support for different StorPool clusters as separate datastores.
* Support for [StorPool MultiCluster](https://kb.storpool.com/admin_guide/multi/multicluster_intro.html) (technology preview).
* Support multiple OpenNebula instances (controllers) in a single StorPool cluster.
* Import of VmWare (VMDK) images.
* Import of Hyper-V (VHDX) images.
* Partial SYSTEM datastore support (see limitations).

Optional:

* Set limit on the number of VM disk snapshots (per disk limits).
* Helper tool to migrate CONTEXT ISO image to StorPool backed volume (require SYSTEM_DS `TM_MAD=storpool`).
* Send volume snapshot to a remote StorPool cluster on image deletion.
* Alternate local kvm/deploy script replacement, which allows [tweaks](docs/deploy_tweaks.md) to the domain XML of the VMs with helper tools to enable iothreads, ioeventfd, fix virtio-scsi _nqueues_ to match the number of VCPUs, set cpu-model, and so on.
* Support VM checkpoint file stored directly on a StorPool backed block device (see the limitations).
* Replace the "VM snapshot" interface scripts to do atomic disk snapshots on StorPool with option to set a limit on the number of snapshots per VM (see limitations).
* Replace the <devices/video> element in the domain XML.
* Support for [UEFI Normal/Secure boot](docs/uefi_boot.md) with persistent UEFI NVRAM stored on StorPool backed block device.
* Support CDROM hotplug.
* Use CPU tune parameters instead/or in addition/ of CPU shares.


## Limitations

* OpenNebula temporarily keeps the VM checkpoint file on the Host and then (optionally) transfers it to the storage. A workaround was added on the base of OpenNebula/one#3272.
* When SYSTEM datastore integration is enabled, the reported free/used/total space of the Datastore is the space on StorPool. (On the host filesystem there are mostly symlinks and small files that do not require much disk space).
* VM snapshotting is not possible because it is handled internally by libvirt, which does not support RAW disks. It is possible to reconfigure the 'VM snapshot' interface of OpenNebula to do atomic disk snapshots in a single StorPool transaction when only StorPool backed datastores are used.
* Only FULL opennebula backups are supported.
* Persistent Images with SHAREABLE attribute are not supported.
* Persistent Images with IMMUTABLE attribute are not supported.
* Tested only with KVM hypervisor and Alma Linux 8/Ubuntu 24.04. Should work on other Linux OS.
* The UEFI auto configuration is not supported.

## More information

* [Installation and upgrade](docs/installation.md)
* [OpenNebula configuration](docs/one_configuration.md)
* [Naming convention](docs/naming_convention.md)
* [Support Life Cycles for OpenNebula Environments](https://kb.storpool.com/storpool_integrations/OpenNebula/support_lifecycle.html)
* [Tips](docs/tips.md)
* [Known issues](docs/known_issues.md)
