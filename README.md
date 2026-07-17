# StorPool storage driver

[StorPool](https://storpool.com/) is a distributed, software-defined block storage platform that transforms standard servers into enterprise-grade shared storage.
With StorPool, [OpenNebula](https://opennebula.io/) clouds gain storage that scales linearly on standard x86 servers, eliminates single points of failure, and delivers consistent sub-100 microsecond latency, all managed through the familiar OpenNebula interface without manual storage operations.

## Quick specification

| Feature | Details |
| :--- | :--- |
| **Supported hypervisors** | KVM (Tested on Alma Linux and Ubuntu) |
| **Storage architecture** | Distributed block storage / Software-defined storage |
| **Core features** | Atomic disk snapshots, QoS Class tags, MultiCluster |
| **License** | Apache License 2.0 |


## Requirements

### OpenNebula Front-end

* Network access to the StorPool API management interface
* StorPool Python 3 installed

### OpenNebula Node

* StorPool initiator driver (`storpool_block`).
* The Bridge node must have `qemu-img` available. It is used by the addon during imports to convert various source image formats to StorPool backed RAW images.


### StorPool cluster

A working StorPool cluster is mandatory.

## Features

Standard OpenNebula datastore operations:

* Datastore MAD (`DATASTORE_MAD`) and Transfer Manager MAD (`TM_MAD`) functionality (see limitations).
* SYSTEM datastore volatile disks as StorPool block devices (see limitations).
* SYSTEM datastore on shared filesystem or ssh when `TM_MAD=storpool` is used.
* SYSTEM datastore context image as a StorPool block device (see limitations).
* Support migration from one SYSTEM datastore to another if both are using `storpool` TM_MAD.

### Extras

* Delayed termination of non-persistent images: When a VM is terminated, the corresponding StorPool volume is stored as a snapshot that is deleted permanently after a predefined time period (default 48 hours).
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
* Send volume snapshot to a remote StorPool cluster on image deletion.
* Alternate local kvm/deploy script replacement, which allows [tweaks](docs/deploy_tweaks.md) to the domain XML of the VMs with various helper tools like fix virtio-scsi ``nqueues`` to match the number of VCPUs, and so on.
* Support VM checkpoint file stored directly on a StorPool backed block device (see the limitations).
* Replace the "VM snapshot" interface scripts to do atomic disk snapshots on StorPool with the option to set a limit on the number of snapshots per VM (see limitations).
* Support for [UEFI Normal/Secure boot](docs/uefi_boot.md) with persistent UEFI NVRAM stored on a StorPool backed block device.
* Support CDROM hotplug.



## Limitations

* OpenNebula temporarily keeps the VM checkpoint file on the Host and then (optionally) transfers it to the storage. A workaround was added on the base of [OpenNebula 3272](https://github.com/OpenNebula/one/issues/3272).
* When SYSTEM datastore integration is enabled, the reported free/used/total space of the Datastore is the space on StorPool. (On the host filesystem there are mostly symlinks and small files that do not require much disk space).
* VM snapshotting is not possible because it is handled internally by libvirt, which does not support RAW disks. It is possible to reconfigure the 'VM snapshot' interface of OpenNebula to do atomic disk snapshots in a single StorPool transaction when only StorPool backed datastores are used.
* Only FULL OpenNebula backups are supported.
* Persistent Images with SHAREABLE or IMMUTABLE attribute are not supported.
* Tested only with KVM hypervisor and Alma Linux/Ubuntu. Should work on other Linux OS.
* The UEFI auto configuration is not supported.

## Development

To contribute bug patches or new features, you can use the GitHub Pull Request model. It is assumed that code and documentation are contributed under the Apache License 2.0.
For details, see:

* [How to Contribute](http://opennebula.io/contribute/)
* Support: [OpenNebula user forum](https://forum.opennebula.io/c/integration/33)
* Issues Tracking: [GitHub issues](https://github.com/OpenNebula/addon-storpool/issues)

### Authors

* Leader: ``Anton Todorov`` (a.todorov@storpool.com)

## Documentation

* [Installation and upgrade](docs/installation.md)
* [OpenNebula configuration](docs/one_configuration.md)
* [Naming convention](docs/naming_convention.md)
* [Support Life Cycles for OpenNebula Environments](https://kb.storpool.com/storpool_integrations/OpenNebula/support_lifecycle.html)
* [Tips](docs/tips.md)
* [Known issues](docs/known_issues.md)

## Frequently asked questions about StorPool integration

### How does StorPool integrate with OpenNebula and what does the plugin support?

StorPool is tightly integrated with OpenNebula as a datastore driver.
Persistent and non-persistent images (virtual disks) are stored in a StorPool cluster, while OpenNebula controls the hypervisor compute nodes.
Everyday workflows become automated -- for example, when a virtual machine (VM) is created in OpenNebula, StorPool automatically creates a new volume and connects it to the VM.

Thanks to the tight integration between StorPool and OpenNebula, common operations like volume creation, snapshots, and restores can all be managed from the GUI of OpenNebula, the command-line interface, or via automated scripts.
The OpenNebula add-on module by StorPool flows OpenNebula storage requests directly into the StorPool cluster.

### How does StorPool handle redundancy and replication in OpenNebula?

StorPool provides two mechanisms for protecting data from unplanned events: replication and erasure coding.
With replication, a few copies of the data are written synchronously across the Cluster in different physical servers; system administrators can set the number of replication copies.
The [erasure coding](https://kb.storpool.com/admin-guide/redundancy.html#erasure-coding) mechanism reduces the amount of data stored on the same hardware set, while at the same time preserves the level of data protection.

### Can OpenNebula users leverage the disaster recovery features of StorPool?

Yes, StorPool Storage includes built-in disaster recovery (DR) capabilities with its [Disaster Recovery Engine](https://kb.storpool.com/disaster-recovery/index.html) (included at no additional cost).
Users can configure snapshot replication policies on a per-VM basis, test automated failover, and execute actual failover procedures.

### How do StorPool and OpenNebula help reduce hardware costs?

StorPool supports the use of cost-efficient [commodity hardware](https://storpool.com/advantages/san-storage-arrays-and-all-flash-arrays-too-expensive) and leverages common open-source software.
As a result, hardware costs for cloud solutions based on StorPool are reduced drastically.
Customers can leverage or reuse existing hardware.

### How does StorPool minimize downtime and maintenance windows in an OpenNebula cloud?

StorPool Storage’s distributed shared-nothing architecture delivers an always-on cloud model that minimizes outages caused by hardware failures and human errors.
It eliminates painful maintenance windows by allowing non-disruptive deployment of software updates, patches, and hardware swap-outs, reducing planned downtime to a minimum.
Such an integrated solution is crucial for enterprise clouds, which demand extreme reliability, performance, and highly efficient operations with maximum uptime.

### What is the operational advantage of using OpenNebula with the managed storage platform provided by StorPool?

Operational overhead is minimized because a team of experts at StorPool handles the deployment, management, and updating of the storage infrastructure.

### Is it possible to retain data for a period of time?

Sometimes there are government/regulation requirements to keep customer data for a given period of time after the termination of the contract.
You can do this by setting your system to send volume snapshot to a remote StorPool cluster on image deletion.

### Is the StorPool OpenNebula driver actively maintained?

The StorPool driver is actively maintained on GitHub, you can check the [commit history](https://github.com/OpenNebula/addon-storpool/commits/master/).



