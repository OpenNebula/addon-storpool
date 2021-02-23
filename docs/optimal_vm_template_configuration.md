# VM Template definition

## Common setup

### General

####Physical CPU
For 5 times oversubscription set physical _CPU = VCPU/10_

Example: use 0.2 for 2 VCPUs

### Storage

#### Disk -> Advanced options

##### BUS

Should be set to `SCSI/SATA`

##### Bus adapter controller

Should be left blank. OpenNebula will add definiiotn to virtio-scsi controler When scsi _virtio-scsi Queues_ are set (see below)

##### Cache

Should be set to `none`

##### Discard

Set to `unmap` to allow discards

##### IO

The IO policy should be set to `native`

##### Image mapping driver

Should be set to `raw`

### Network

#### Default hardware model to emulate for all NICs

Should be set to `virtio`

#### Default network filtering rule for all NICs

Depending on the use case.
[addon-vnfilter](https://github.com/storpool/addon-vnfilter) should be considered to extend the IP spoofing filters with ARP filtering for IPv4.

### OS & CPU

#### Boot

##### CPU Architecture

Depending on the use case. Usually `x86_64`

##### Bus for SD disks

Should be set to `SCSI`

When left blank it defaults depending on the style of the device (in the example it is _SCSI_).

##### Macine type

Depending ont the use case.
Machine type `q35` is mandatory for UEFI (secure) boot

#### Features

##### ACPI

Should be set to `Yes`

##### QEMU Guest Agent

Should be set to `Yes`

Usually not used but but better to hev it enabled when need arise.

##### HYPERV

Should be set for VMs with MS Windows OS

##### virtio-scsi Queues

Should be set to to match the number of VCPUs
(There is a deploy-thweak script to take care for this so any positive value should be enough to trigger the tweak)

#### CPU Model

Depending on the use case

### Input/Output

#### Graphics

On KVM hosts that had both Public accessible NIC and Private (management) NIC it is possible to configure libvirt to bind the VNC on the private network. For this define a common name in the _/etc/hosts_ on each KVM and set the name in the _Listen on IP_ field.

For example, to use the common name `vncaccess` set on each kvm host:

```
#KVM host 1 /etc/hosts
x.x.x.x kvm1hostname vncaccess
x.x.x.y kvm2hostname 

#KVM host 2 /etc/hosts
x.x.x.x kvm1hostname
x.x.x.y kvm2hostname vncaccess
```

And set _Listen on IP_ to `vncaccess`

The password (generation) depends on the use case.

#### Inputs

Set a `Tablet` type on `USB` bus to have better mouse experiens on the VNC console

### Context

### Custom vars

Depends on the use case. It is possible to set the VM hostname to match the _name_ of the VM defining `SET_HOSTNAME` variable with value `$NAME`




