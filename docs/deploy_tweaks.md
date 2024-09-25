## Deploy tweaks

### Setup

#### Installation

The scripts are installed with the default installation of addon-storpool


#### Configuration

The deploy-tweaks script is activated by replacing the upstream deploy script with a local one executed on the front-end node which chainload the original script at the end.

```
VM_MAD = [
  ARGUMENTS = "... -l deploy=deploy-tweaks",
]
```


### Usage

The deploy-tweaks script is called on the active front-end node. The script call all executable helpers found in the `deploy-tweaks.d` folder one by one passing two files as arguments - a copy of the VM domain XML file and the OpenNebula's VM definition in XML format. The helper scripts overwrite the VM domain XML copy and on successful return code the VM domain XML is updated from the copy (and passed to the next helper).

Once all helper scripts are processed the native _vmm/kvm/deploy_ script on the destination KVM host id called with the tweaked domain XML for VM deployment.

#### context-cache.py

Replaces the `devices/disk/driver` attributes _cache=none_ and _io=native_ on all found cdrom disks that had _type=file_ and _device=cdrom_

#### cpu.py

* `domain/vcpu element` if missing (with default value '1')
* definition for VCPU topology using defined with `USER_TEMPLATE/T_CPU_THREADS`, `USER_TEMPLATE/T_CPU_SOCKETS`
* definition for `domain/cpu/feature` using defined variable `USER_TEMPLATE/T_CPU_FEATURES`
* definition for `domain/cpu/model` using defined variable `USER_TEMPLATE/T_CPU_MODEL`
* definition for `domain/cpu/vendor` using defined variable `USER_TEMPLATE/T_CPU_VENDOR`
* definition for `domain/cpu`attribute `check` using defined variable `USER_TEMPLATE/T_CPU_CHECK`
* definition for `domain/cpu`attribute `match` using defined variable `USER_TEMPLATE/T_CPU_MATCH`
* definition for `domain/cpu`attribute `mode` using defined variable `USER_TEMPLATE/T_CPU_MODE`
The script create/tweak the _cpu_ element of the domain XML.

> Default values could be exported via the `kvmrc` file.


##### T_CPU_SOCKETS and T_CPU_THREADS

Set the number of sockets and VCPU threads of the CPU topology.
For example the following configuration represent VM with 8 VCPUs, in single socket with 2 threads:

```
VCPU = 8
T_CPU_SOCKETS = 1
T_CPU_THREADS = 2
```

```xml
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='4' threads='2'/>
    <numa>
      <cell id='0' cpus='0-7' memory='33554432' unit='KiB'/>
    </numa>
  </cpu>
```

##### Advanced

The following variables were made available for use in some corner cases.

> For advanced use only! A special care should be taken when mixing the variables as some of the options are not compatible when combined.

###### T_CPU_MODE

Possible options: _custom_, _host-model_, _host-passthrough_.

Special keyword _delete_ will instruct the helper to delete the element from the domain XML.

###### T_CPU_FEATURES

Comma separated list of supported features. The policy could be added using a colon (':') as separator.

###### T_CPU_MODEL

The optional _fallback_ attribute could be set after the model, separated with a colon (':').
The special keyword _delete_ will instruct the helper to delete the element.

###### T_CPU_VENDOR

Could be set only when a `model` is defined.

###### T_CPU_CHECK

Possible options: _none_, _partial_, _full_.
The special keyword _delete_ will instruct the helper to delete the element.

###### T_CPU_MATCH

Possible options: _minimum_, _exact_, _strict_.
The special keyword _delete_ will instruct the helper to delete the element.


#### cpuShares.py

The script will reconfigure _/domain/cputune/shares_ using the folloing formula

`( VCPU * multiplier ) * 1024`

Default for the _multiplier_ is _0.1_ and to change per VM set _USER_TEMPLATE/T_CPU_MUL_ variable

##### T_CPUTUNE_MUL

Override VCPU _multiplier_ for the given VM

`domain/cputune/shares` = VCPU * `USER_TEMPLATE/T_CPUTUNE_MUL` * 1024

##### T_CPUTUNE_SHARES

To override the above calculations and use the value for _/domain/cputune/shares/_ for the given VM.

`domain/cputune/shares` =`USER_TEMPLATE/T_CPUTUNE_SHARES`

#### disk-cache-io.py

Set disk `cache=none` and `io=native` for all StorPool backed disks

#### feature_smm.py

See [UEFI boot](uefi_boot.md)

#### hv-enlightenments.py

Set HYPERV enlightenments features at `domain/features/hyperv` when defined `T_HV_SPINLOCKS`,T_HV_RELAXED`,`T_HV_VAPIC`,`T_HV_TIME`,`T_HV_CRASH`,`T_HV_RESET`,`T_HV_VPINDEX`,`T_HV_RUNTIME`,`T_HV_SYNC`,`T_HV_STIMER`,`T_HV_FEQUENCIES` (`T_HV_REENLIGHTENMENT`,`T_HV_TLBFLUSH`,`T_HV_IPI` and `T_HV_EVMCS`) with value _on_ or _1_ 

#### hyperv-clock.py

The script add additional tunes to the _clock_ entry when the _hyperv_ feature is enabled in the domain XML.

> Sunstone -> Templates -> VMs -> Update -> OS Booting -> Features -> HYPERV = YES

```xml
<domain>
  <clock offset="utc">
    <timer name="hypervclock" present="yes"/>
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
  </clock>
</domain>
```

Note: Same could be done by editing `HYPERV_OPTIONS` variable in `/etc/one/vmm_exec/vmm_exec_kvm.conf`

#### iothreads.py

The script will define an [iothread](https://libvirt.org/formatdomain.html#elementsIOThreadsAllocation) and assign it to all virtio-blk disks and vitio-scsi controllers.

```xml
<domain>
  <iothreads>1</iothreads>
  <devices>
    <disk device="disk" type="block">
      <source dev="/var/lib/one//datastores/0/42/disk.2" />
      <target dev="vda" />
      <driver cache="none" discard="unmap" io="native" iothread="1" name="qemu" type="raw" />
    </disk>
    <controller index="0" model="virtio-scsi" type="scsi">
      <driver iothread="1" />
    </controller>
  </devices>
</domain>
```

With OpenNebula 6.0+ use `USER_TEMPLATE/T_IOTHREADS_OVERRIDE` to override the default values)

#### kvm-hide.py

Set `domain/features/kvm/hidden[@state=on]` when `USER_TEMPLATE/T_KVM_HIDE` is defined

#### os.py

Set/update `domain/os` element

see [UEFI boot](uefi_boot.md)

#### q35-pcie-root.py

Update PCIe root ports when machine type `q35` is defined with the number defined in `USER_TEMPLATE/Q35_PCIE_ROOT_PORTS`

#### resizeCpuMem.py

See [Live resize CPU and Memory](resizeCpuMem.md)

#### scsi-queues.py

Set the number of `nqueues` for virtio-scsi controllers to match the number of VCPUs. This code is triggered when there are alredy defined number of quieues for a given VM.

```xml
<domain>
  <vcpu>4</vcpu>
  <devices>
    <controller index="0" model="virtio-scsi" type="scsi">
      <driver queues="4" />
    </controller>
  </devices>
</domain>
```

There is an option to enable the queues for virtio-blk disks too by defining `T_BLK_QUEUES=YES` per VM in the `USER_TEMPLATE` or globally in addon-storpoolrc or vmm/kvmrc file.
Note: This functionallity must be supported by the installed qemu-kvm.


#### uuid.py

Override/define `domain/uuid` with the value from `USER_TEMPLATE/T_UUID`

Note: With OpenNebula 6.0+ same could be aciheved with `OS/DEPLOY_ID`.

#### vfhostdev2interface.py

OpenNebula provides generic PCI passthrough definition using _hostdev_. But
when it is used for NIC VF passthrough the VM's kernel assign random MAC
address (on each boot). Replacing the definition with _interface_ it
is possible to define the MAC addresses via configuration variable in
_USER_TEMPLATE_. The T_VF_MACS configuration variable accept comma separated
list of MAC addresses to be asigned to the VF pass-through NICs. For example to
set MACs on two PCI passthrough VF interfaces, define the addresses in the
T_VF_MACS variable and (re)start the VM:

```
T_VF_MACS=02:00:11:ab:cd:01,02:00:11:ab:cd:02
```

The following section of the domain XML

```xml
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
      <address  domain='0x0000' bus='0xd8' slot='0x00' function='0x5'/>
    </source>
    <address type='pci' domain='0x0000' bus='0x01' slot='0x01' function='0'/>
  </hostdev>
  <hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
      <address  domain='0x0000' bus='0xd8' slot='0x00' function='0x6'/>
    </source>
    <address type='pci' domain='0x0000' bus='0x01' slot='0x02' function='0'/>
  </hostdev>
```

will be converted to

```xml
  <interface managed="yes" type="hostdev">
    <driver name="vfio" />
    <mac address="02:00:11:ab:cd:01" />
    <source>
      <address bus="0xd8" domain="0x0000" function="0x5" slot="0x00" type="pci" />
    </source>
    <address bus="0x01" domain="0x0000" function="0" slot="0x01" type="pci" />
  </interface>
  <interface managed="yes" type="hostdev">
    <driver name="vfio" />
    <mac address="02:00:11:ab:cd:02" />
    <source>
      <address bus="0xd8" domain="0x0000" function="0x6" slot="0x00" type="pci" />
    </source>
    <address bus="0x01" domain="0x0000" function="0" slot="0x02" type="pci" />
  </interface>
```

#### video.py

Redefine `domain/devices/video` and using `USER_TEMPLATE/T_VIDEO_MODEL` with space separated list of attributes (_name=value_)

#### volatile2dev.py

The script will reconfigure the volatile disks from file to device when the VM disk's TM_MAD is _storpool_.

```xml
    <disk type='file' device='disk'>
        <source file='/var/lib/one//datastores/0/4/disk.2'/>
        <target dev='sdb'/>
        <driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>
        <address type='drive' controller='0' bus='0' target='1' unit='0'/>
    </disk>
```
to

```xml
    <disk type="block" device="disk">
        <source dev="/var/lib/one//datastores/0/4/disk.2" />
        <target dev="sdb" />
        <driver name="qemu" cache="none" type="raw" io="native" discard="unmap" />
        <address type="drive" controller="0" bus="0" target="1" unit="0" />
    </disk>
```


To do the changes when hot-attaching a volatile disk the original attach_disk script (`/var/lib/one/remotes/vmm/kvm/attach_disk`) should be overrided too:

```
VM_MAD = [
    ...
    ARGUMENTS = "... -l deploy=deploy-tweaks,attach_disk=attach_disk.storpool",
    ...
]
```

#### sysinfo_smbios.py

Adds smbios information to the VMs. An entry in the OS element is created to enable the smbios sysinfo:

```xml
<os>
  <smbios mode="sysinfo"/>
</os>
```

When at least one of the folling variables are defined in the USER_TEMPLATE

##### T_SMBIOS_BIOS

A list of variables in format `key=value` separated by a semi-colon. The following example:

```
USER_TEMPLATE/T_SMBIOS_BIOS="vendor=BVendor;version=BVersion;date=05/13/2022;release=42.42"
```
Will generate the following element in the domain XML:

```xml
  <sysinfo type="smbios">
    ...
    <bios>
      <entry name="vendor">BVendor</entry>
      <entry name="version">BVersion</entry>
      <entry name="date">05/13/2022</entry>
      <entry name="release">42.42</entry>
    </bios>
  </sysinfo>
```

Note the special formating of the *date* and *release* elements in the libvirt documentation!

##### T_SMBIOS_SYSTEM

A list of variables in format `key=value` separated by a semi-colon. The following example:

```
USER_TEMPLATE/T_SMBIOS_SYSTEM="manufacturer=SManufacturer;product=SProduct;version=SVersion;serial=SSerial;sku=SSKU;family=SFamily"
```
Will generate the following element in the domain XML:

```xml
  <sysinfo type="smbios">
    <system>
      <entry name="manufacturer">SManufacturer</entry>
      <entry name="product">SProduct</entry>
      <entry name="version">SVersion</entry>
      <entry name="serial">SSerial</entry>
      <entry name="sku">SSKU</entry>
      <entry name="family">SFamily</entry>
    </system>
  </sysinfo>
```

##### T_SMBIOS_BASEBOARD

A list of variables in format `key=value` separated by a semi-colon. The following example:

```
USER_TEMPLATE/T_SMBIOS_BASEBOARD="manufacturer=BBManufacturer;version=BBVersion;serial=BBSerial;product=BBProduct;asset=BBAsset;location=BBLocation"
```
Will generate the following element in the domain XML:

```xml
  <sysinfo type="smbios">
    <baseBoard>
      <entry name="manufacturer">BBManufacturer</entry>
      <entry name="version">BBVersion</entry>
      <entry name="serial">BBSerial</entry>
      <entry name="product">BBProduct</entry>
      <entry name="asset">BBAsset</entry>
      <entry name="location">BBLocation</entry>
    </baseBoard>
  </sysinfo>
```

##### T_SMBIOS_CHASSIS

A list of variables in format `key=value` separated by a semi-colon. The following example:

```
USER_TEMPLATE/T_SMBIOS_CHASSIS="manufacturer=CManufacturer;version=CVersion;serial=CSerial;asset=CAsset;sku=CSKU"
```
Will generate the following element in the domain XML:

```xml
  <sysinfo type="smbios">
    <chassis>
      <entry name="manufacturer">CManufacturer</entry>
      <entry name="version">CVersion</entry>
      <entry name="serial">CSerial</entry>
      <entry name="asset">CAsset</entry>
      <entry name="sku">CSKU</entry>
    </chassis>
  </sysinfo>
```

##### T_SMBIOS_OEMSTRINGS

A list of strings separated by a semi-colon. The following example:

```
USER_TEMPLATE/T_SMBIOS_OEMSTRINGS="myappname:some arbitrary data;otherappname:more arbitrary data"
```
Will generate the following element in the domain XML:

```xml
  <sysinfo type="smbios">
    <oemStrings>
      <entry>myappname:some arbitrary data</entry>
      <entry>otherappname:more arbitrary data</entry>
    </oemStrings>
  </sysinfo>
```

#### persistent-cdrom.py

Enable IDE CDROM image attach/detach by replacing the corresponding actions with insert/eject.

The virtual machine could work with up to 4 CDROM devices, usually one is occupied by the CONTEXTUALIZATION CDROM, though.

##### system configuration

* activate persistent-cdrom.py

```
su - oneadmin
cd ~oneadmin/remotes/vmm/kvm/deploy-tweaks.d
ln -s ../deploy-tweaks.d.example/persistent-cdrom.py
```

* edit the opennebula configuration to use the alternate (local) scripts for `attach_disk` and `detach_disk`, restart the opennebula service and propagate the changes to the hosts:

```
vi /etc/one/oned.conf
---
VM_MAD = [
   ...
   ARGUMENTS      = "-l ...,attach_disk=attach_disk.storpool,detach_disk=detach_disk.storpool,... "
   ...
]
---

systemctl restart opennebula

su - oneadmin -c 'onehost sync -f'
```

* configure the number of CDROM devices globally in the addon-storpoolrc file:

```
T_PERSISTENT_CDROM=4
```

or per VM in the VM attributes(a.k.a. _USER_TEMPLATE_)

```
USER_TEMPLATE/T_PERSISTENT_CDROM="4"
```

Note: The value per VM overrides the global definition, so to disable the function for a VM when there is a global definition, just set `T_PERSISTENT_CDROM=0`.

* To define the persistent CDROM devices to be backed with file based images set

```
T_PERSISTENT_CDROM_TYPE="file"
```

### cputune.py

Use libvirt vCPU tune paramenters insted of cpu/shares (or in addition to the cpushares). Refer libvirt documentation for details.

The following parameters could be set as a global defaults in the addon-storpoolrc file and as overrides per VM in the VM Attributes:

```
T_CPUTUNE_PERIOD
T_CPUTUNE_QUOTA
T_CPUTUNE_GLOBAL_PERIOD
T_CPUTUNE_GLOBAL_QUOTA
T_CPUTUNE_EMULATOR_PERIOD
T_CPUTUNE_EMULATOR_QUOTA
T_CPUTUNE_IOTHREAD_PERIOD
T_CPUTUNE_IOTHREAD_QUOTA
```

By default, the script removes the cpu/shares when a cpu tune parameter iis defined. To keep the cpu/shares define as a global variable or as VM attribute the following variable

```
T_CPUTUNE_SHARES_KEEP=1
```

