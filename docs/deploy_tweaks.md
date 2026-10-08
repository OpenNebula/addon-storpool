# Deployment tweaks

## Setup

### Installation

The scripts are installed with the default installation of addon-storpool.


### Configuration

The deploy-tweaks script is activated by replacing the upstream deploy script with a local one executed on the front-end node, which chain-loads the original script at the end.

```
VM_MAD = [
  ARGUMENTS = "... -l deploy=deploy-tweaks",
]
```


## Usage

The deploy-tweaks script is called on the active front-end node. The script calls all executable helpers found in the `deploy-tweaks.d` folder one by one, passing two files as arguments - a copy of the VM domain XML file and the OpenNebula's VM definition in XML format. The helper scripts overwrite the VM domain XML copy, and on successful return code the VM domain XML is updated from the copy (and passed to the next helper).

Once all helper scripts are processed, the native _vmm/kvm/deploy_ script on the destination KVM host is called with the tweaked domain XML for VM deployment.

### context-cache.py

Sets `cache='none'` and `io='native'` on every `devices/disk` with `type='file'` and `device='cdrom'`. The `driver` element is created when it is missing. A block disk and a file disk that is not a cdrom are left unchanged.

Optional `USER_TEMPLATE` keys use the same values as `disk-cache-io.py`. The template overrides the environment. An empty value is unset. The keys are read from the VM XML.

* `T_CONTEXT_CACHE`: `default`, `none`, `writeback`, `writethrough`, `directsync`, `unsafe`
* `T_CONTEXT_IO`: `threads`, `native`, `io_uring`
* `T_CONTEXT_DISCARD`: `unmap`, `ignore`
* `T_CONTEXT_DETECT_ZEROES`: `off`, `on`, `unmap`
* `T_CONTEXT_IOEVENTFD`: `on`, `off`
* `T_CONTEXT_QUEUE_SIZE`: a power of two, written as `queue_size`

Every set key is checked before any disk is edited. A bad value exits 2, which aborts the deploy. If there is no file cdrom and the keys are valid, the script exits 0 and leaves the domain unchanged.

### cpu.py

* `domain/vcpu element` if missing (with default value '1').
* Definition for VCPU topology using defined with `USER_TEMPLATE/T_CPU_THREADS`, `USER_TEMPLATE/T_CPU_SOCKETS`.
* Definition for `domain/cpu/feature` using defined variable `USER_TEMPLATE/T_CPU_FEATURES`.
* Definition for `domain/cpu/model` using defined variable `USER_TEMPLATE/T_CPU_MODEL`.
* Definition for `domain/cpu/vendor` using defined variable `USER_TEMPLATE/T_CPU_VENDOR`.
* Definition for `domain/cpu`attribute `check` using defined variable `USER_TEMPLATE/T_CPU_CHECK`.
* Definition for `domain/cpu`attribute `match` using defined variable `USER_TEMPLATE/T_CPU_MATCH`.
* Definition for `domain/cpu`attribute `mode` using defined variable `USER_TEMPLATE/T_CPU_MODE`.

The script creates/tweaks the _cpu_ element of the domain XML.

Default values could be exported via the `kvmrc` file.


#### T_CPU_SOCKETS and T_CPU_THREADS

Set the number of sockets and VCPU threads of the CPU topology.
For example, the following configuration represents VM with 8 VCPUs, in a single socket with 2 threads:

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

#### Advanced

The following variables were made available for use in some corner cases.

**Note:** For advanced use only! A special care should be taken when mixing the variables, as some of the options are not compatible when combined.

##### T_CPU_MODE

Possible options: _custom_, _host-model_, _host-passthrough_, _maximum_.

`host-model`, `host-passthrough`, and `maximum` drop `<model>`. `custom` keeps a model only from `T_CPU_MODEL`.

Special keyword _delete_ removes the `mode` attribute.

##### T_CPU_FEATURES

Comma-separated list of features. This list replaces every `<feature>` on `<cpu>`. The policy is added after a colon (`name:require`). A missing policy is left unset. `force`, `require`, `optional`, `disable`, and `forbid` are accepted.

##### T_CPU_MODEL

The optional _fallback_ attribute is `allow` or `forbid`, after the model, separated with a colon (`:`).
The special keyword _delete_ removes `<model>`.

##### T_CPU_DIES and T_CPU_CLUSTERS

Optional positive integers on the topology written by `T_CPU_SOCKETS`. `1` is omitted. The product `sockets × dies × clusters × cores × threads` must equal the `<vcpu>` maximum. `cores` is derived. Each cell gets `unit` from `<memory>` (default `KiB`).

`T_CPU_NUMA_MEMACCESS` is `shared` or `private`. `T_CPU_NUMA_DISCARD` is `yes` or `no`.

##### T_CPU_CACHE

`emulate`, `passthrough`, or `disable`. `emulate` requires `level=3`. `passthrough` requires `mode` `host-passthrough` or `maximum`. Optional `level` is `1`, `2`, or `3` (`emulate:level=3`).

##### T_CPU_MAXPHYSADDR

`emulate:bits=42`, `passthrough`, or `passthrough:limit=39`. `bits` is required for `emulate`. `limit` is only for `passthrough`.

##### T_CPU_VENDOR

Could be set only when a `model` is defined.

##### T_CPU_CHECK

Possible options: _none_, _partial_, _full_.
The special keyword _delete_ removes the `check` attribute.

##### T_CPU_MATCH

Possible options: _minimum_, _exact_, _strict_.
The special keyword _delete_ removes the `match` attribute.

### `cpuShares.py`

The script will reconfigure _/domain/cputune/shares_ using the following formula

`( VCPU * multiplier ) * 1024`

Default for the _multiplier_ is _0.1_; to change per VM, set the _USER_TEMPLATE/T_CPU_MUL_ variable.

#### T_CPUTUNE_MUL

Override VCPU _multiplier_ for the given VM.

`domain/cputune/shares` = VCPU * `USER_TEMPLATE/T_CPUTUNE_MUL` * 1024

#### T_CPUTUNE_SHARES

To override the above calculations and use the value for _/domain/cputune/shares/_ for the given VM.

`domain/cputune/shares` =`USER_TEMPLATE/T_CPUTUNE_SHARES`

### disk-cache-io.py

Sets `cache='none'`, `io='native'`, and `discard='unmap'` on StorPool disks. The `driver` element is created when it is missing. Other driver attributes are kept.

A disk matches when its source `file` or `dev` path carries a disk id and that disk's `TM_MAD`, compared case-insensitively, is `storpool`. The id is the last `.` component when that component is an integer (`disk.0`). A source path `/dev/sp-<id>` uses that id. Any other source attribute is skipped. A path that does not yield an integer disk id is skipped.

The id is read from `TEMPLATE/DISK[DISK_ID]/TM_MAD`. When that element is missing and `TEMPLATE/CONTEXT[DISK_ID]` exists, the script uses `HISTORY_RECORDS/HISTORY[last()]/TM_MAD`.

Optional `USER_TEMPLATE` keys override those defaults when set. The template overrides the environment. An empty value is unset.

* `T_DISK_CACHE`: `default`, `none`, `writeback`, `writethrough`, `directsync`, `unsafe`
* `T_DISK_IO`: `threads`, `native`, `io_uring`
* `T_DISK_DISCARD`: `unmap`, `ignore`
* `T_DISK_DETECT_ZEROES`: `off`, `on`, `unmap`
* `T_DISK_IOEVENTFD`: `on`, `off`
* `T_DISK_QUEUE_SIZE`: a power of two, written as `queue_size`

Every set key is checked before any disk is edited. A bad value exits 2, which aborts the deploy, including when no disk matches. If no StorPool disk matches and the keys are valid, the script exits 0 and leaves the domain unchanged.

### `feature_smm.py`

Set `<features><smm state='on'><tseg unit='MiB'>48</tseg></smm>`. See [UEFI boot](uefi_boot.md).

`T_FEATURE_SMM=:state=on` or `:state=off`. `on`, `1`, `off`, and `0` are accepted. Text before the colon is ignored. `state` is the only attribute.

`T_FEATURE_SMM_TSEG=42:unit=MiB` sets the size. An empty size is `0`. An omitted unit is written as `MiB`. The size must be a whole number of MiB. `<tseg>` requires SMM `state='on'`. Turning SMM off drops `<tseg>`. A bad value exits 2, which aborts the deploy.

### `hv-enlightenments.py`

Set Hyper-V enlightenment features on an existing `domain/features/hyperv` element (OpenNebula writes that element when `HYPERV=yes`).

`T_HV_<FEATURE>=on` or `1` turns a feature on. `off` or `0` turns it off. An existing child is updated; a second copy is not added. The features are `relaxed`, `vapic`, `spinlocks`, `vpindex`, `runtime`, `synic`, `stimer`, `reset`, `vendor_id`, `frequencies`, `reenlightenment`, `tlbflush`, `ipi`, `evmcs`, `avic`, `emsr_bitmap`, and `xmm_input`. `T_HV_TIME` and `T_HV_CRASH` are ignored: libvirt has no such Hyper-V features.

Attributes use the same `value:key=value` spelling as `feature_smm.py`. `T_HV_SPINLOCKS=on` sets `retries='8191'`. `T_HV_SPINLOCKS=on:retries=4095` overrides it. The count must be from 4095 to 4294967295.

`T_HV_VENDOR_ID` is the vendor string (at most 12 characters, no comma), or `on:value=KVM Hv`. `off` clears it.

Nested children follow `T_FEATURE_SMM_TSEG`: a separate template element for each child. `T_HV_STIMER_DIRECT=on` writes `<stimer><direct state='on'/></stimer>`. `T_HV_TLBFLUSH_DIRECT` and `T_HV_TLBFLUSH_EXTENDED` do the same under `<tlbflush>`. The parent must be `state='on'`, either from its own `T_HV_*` value or from the domain XML already. A bad value exits 2, which aborts the deploy.

`T_HV_MODE` is `custom`, `passthrough`, or `host-model`. `passthrough` sets the attribute and leaves the children unchanged, because libvirt ignores them in that mode.

### `hyperv-clock.py`

The script adds additional tunes to the _clock_ entry when the _hyperv_ feature is enabled in the domain XML.

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

**Note:** Same could be done by editing `HYPERV_OPTIONS` variable in `/etc/one/vmm_exec/vmm_exec_kvm.conf`.

### iothreads.py

`T_IOTHREADS` sets an [iothread](https://libvirt.org/formatdomain.html#elementsIOThreadsAllocation) count and assigns those threads round-robin, starting at 1, to `vd*` disks and then to virtio-scsi controllers already in the domain. A controller with no `model` counts as `virtio-scsi`. `T_IOTHREADS_OVERRIDE=0` leaves the domain unchanged, including when `T_IOTHREADS` is also set. With `T_IOTHREADS` unset, a positive `T_IOTHREADS_OVERRIDE` is the spec. With neither key set, the domain stays as it is, including an existing `<iothreads>` element. `USER_TEMPLATE` wins over the environment. Empty or whitespace leaves the key unset.

The value is `N` or `N` plus attributes: `io` (`threads`, `native`, or `io_uring`, default `native`), `thread_pool_min`, `thread_pool_max`, `poll_max`, `poll_grow`, `poll_shrink`, and `queue`. `N` is a positive integer. Pool, poll, and `queue` values are unsigned integers. A bad value exits 2, which aborts the deploy.

An existing `<iothreads>` element is updated in place. Otherwise it is inserted immediately before `<devices>`, or appended when `<devices>` is absent. Its text is `N`. When any pool or poll attribute is set, `<iothreadids>` is replaced with ids `1..N` and placed immediately after `<iothreads>`. Each id has `thread_pool_min` and `thread_pool_max` when those were given. Poll values become `<poll max= grow= shrink=>` using only the attributes that were given. With no pool or poll attributes, an existing `<iothreadids>` is removed.

Disk drivers receive `io` and `iothread`. Virtio-scsi drivers receive `iothread`. `queue` writes `<iothreads><iothread id=><queue id=/></iothread></iothreads>` on both disks and virtio-scsi, in place of the `iothread` attribute. `cache`, `name`, `type`, and `queues` stay on the driver.

```xml
<domain>
  <iothreads>1</iothreads>
  <iothreadids>
    <iothread id="1" thread_pool_min="1" thread_pool_max="16">
      <poll max="64" grow="4" shrink="2"/>
    </iothread>
  </iothreadids>
  <devices>
    <disk device="disk" type="block">
      <target dev="vda"/>
      <driver cache="none" io="native" iothread="1" name="qemu" type="raw"/>
    </disk>
    <controller model="virtio-scsi" type="scsi">
      <driver iothread="1"/>
    </controller>
  </devices>
</domain>
```

### kvm-hide.py

Set KVM feature children under `domain/features/kvm`. `on` creates `<features>` and `<kvm>` when they are missing.

`T_KVM_HIDE` sets `<hidden>`. `T_KVM_HINT_DEDICATED`, `T_KVM_POLL_CONTROL`, `T_KVM_PV_IPI`, and `T_KVM_DIRTY_RING` set the other children libvirt accepts.

`on` or `1` sets `state='on'`. `off` or `0` sets `state='off'` on an existing child. An existing child is updated; a second copy is not added. A bad value exits 2, which aborts the deploy.

`T_KVM_DIRTY_RING=on:size=4096` sets `size`. The size must be a power of two from 1024 to 65536. `on` alone keeps a size already on the element. `off` drops `size`.

### `nvme-disk.py`

Append a host NVMe disk for each set `USER_TEMPLATE/T_NVME_DEVICE0` through `T_NVME_DEVICE31`. The value is a PCI address `DOMAIN:BUS:SLOT.FUNC`, plus an optional `namespace=N`. Example: `0000:81:00.0 namespace=2`.

Each disk is `<disk type='nvme' device='disk'>` with `<driver name='qemu' type='raw'/>`, `<source type='pci' managed='yes' namespace='N'>`, a PCI `<address>`, and `<target dev='vdX' bus='virtio'/>`. `X` runs backward from `z`, so index 0 is `vdz` and index 1 is `vdy`. Existing disks are left in place.

`namespace` must be an integer >= 1. Libvirt rejects 0. If `namespace=` is omitted and the index is >= 1, the namespace is the index. Index 0 with no `namespace=` exits 2. A PCI address that is not three colon-separated parts with `SLOT.FUNC`, or any trailing key other than `namespace`, exits 2.

`T_NVME_CONTROLLER=N` removes every `<controller type='nvme'>` and appends controllers `index` 0 through `N-1`. `N` must be a positive integer. With neither a device key nor `T_NVME_CONTROLLER` set, the domain is left unchanged. A missing `<devices>` exits 2 when a device key or `T_NVME_CONTROLLER` is set. A `USER_TEMPLATE` value wins over the environment; an empty value is unset. A bad value exits 2, which aborts the deploy.

### `nvme-block.py`

Same disks as `nvme-disk.py`, from `USER_TEMPLATE/T_NVME_PCIDEVICE0` through `T_NVME_PCIDEVICE31`. This script does not read `T_NVME_CONTROLLER`. With no device key set, the domain is left unchanged. A missing `<devices>` exits 2 when a device key is set. A bad value exits 2, which aborts the deploy.

### os.py

Set/update `domain/os` element; see [UEFI boot](uefi_boot.md).

### `q35-pcie-root.py`

`T_Q35_PCIE_ROOT_PORTS` replaces the PCIe controllers on a q35 domain. The value is how many `pcie-root-port` controllers to write. The domain gets one `pcie-root` at index 0, root ports indexed from 1, and a `pcie-to-pci-bridge` at the next index. An existing `<pcihole64>` on the root is kept. With the key unset, the domain is left unchanged. A bad value exits 2, which aborts the deploy.

### `resizeCpuMem.py`

See [Live resize CPU and Memory](resizeCpuMem.md).

### scsi-queues.py

`T_SCSI_QUEUES` sets `<driver queues>` on every virtio-scsi controller. A controller with no `model` counts as virtio-scsi. The value is a positive integer, or `auto`, `vcpu`, `yes`, `y`, or `1` for the current vCPU count: the `<vcpu current>` attribute when that attribute is a positive integer, otherwise the element text. A missing `<vcpu>` aborts the deploy. Optional `:cmd_per_lun=N max_sectors=N` sets those attributes; both are unsigned, so `0` is allowed. Unknown attributes abort the deploy. When the domain has no virtio-scsi controller, one is created under the first `<devices>` element. Other driver attributes are kept.

`T_BLK_QUEUES` is `YES`, `1`, `auto`, `vcpu`, or a positive integer, with optional `:queue_size=N`. `queue_size` is a power of two. The script sets those attributes on disks whose target `dev` starts with `vd`. It does not create disks. A `<driver>` is added when the disk has none. Other driver attributes are kept.

`USER_TEMPLATE` wins over the environment (`addon-storpoolrc` or `vmm/kvmrc`). Empty or whitespace is unset. With both keys unset, or when `T_BLK_QUEUES` is set but no `vd` disk exists, the domain file is not rewritten. A bad value prints `Error in scsi-queues: …` to stderr and exits 2 before the domain is written, which aborts the deploy and leaves the on-disk XML unchanged.

### `nic-queues.py`

`T_NIC_QUEUES` sets `<driver queues=>` on each interface whose `<model type='virtio'/>`. `auto`, `vcpu`, `yes`, `y`, and `1` use the current vCPU count: `<vcpu current>` when that attribute is a positive integer, otherwise the `<vcpu>` text. Any other positive integer is the queue count. `T_NIC<id>_QUEUES` overrides the global value for the NIC whose `<target dev>` has that id as its last hyphen segment, and only when the segment is all digits. `:rx_queue_size=N tx_queue_size=N txmode=iothread|timer` sets those attributes; `N` is a power of two and `txmode` is `iothread` or `timer`. `name='vhost'` is written only when `name` is missing. An existing name, every other driver attribute, and driver children stay. A `USER_TEMPLATE` value overrides the environment, and empty or whitespace leaves the key unset. With neither key set for a NIC, or when no virtio NIC is updated, the domain is not written. A missing `<vcpu>` for an automatic count, an unknown attribute, or any other bad value exits 2, which aborts the deploy.

### uuid.py

Override/define `domain/uuid` with the value from `USER_TEMPLATE/T_UUID`.

**Note:** With OpenNebula 6.0+ the same could be achieved with `OS/DEPLOY_ID`.

### `vfhostdev2interface.py`

OpenNebula provides generic PCI passthrough definition using _hostdev_. But
when it is used for NIC VF passthrough, the VM's kernel assigns random MAC
address (on each boot). By replacing the definition with _interface_ it
is possible to define the MAC addresses via configuration variable in
_USER_TEMPLATE_. The `T_VF_MACS` configuration variable accepts comma-separated
list of MAC addresses to be assigned to the VF pass-through NICs. 

For example, to set MACs on two PCI passthrough VF interfaces, define the addresses in the T_VF_MACS variable and (re)start the VM:

```
T_VF_MACS=02:00:11:ab:cd:01,02:00:11:ab:cd:02
```

The following section of the domain XML:

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

will be converted to:

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

### video.py

`T_VIDEO_MODEL` replaces every `<video>` under the first `<devices>` with one `<video><model>`. Address, alias, and driver on the replaced elements are dropped. With the key unset or empty, the domain is left unchanged. A value in `USER_TEMPLATE` wins over the environment. A missing `<devices>` element exits 2, which aborts the deploy. A bad value does too.

The value is space-separated `key=value`. A token without `=` is rejected. `type` is required: `vga`, `cirrus`, `vmvga`, `xen`, `vbox`, `gop`, `none`, `bochs`, `ramfb`, `qxl`, or `virtio`. `device` is only for `type=virtio`: `virtio-vga`, `virtio-vga-gl`, `virtio-gpu`, `virtio-gpu-gl`, `vhost-user-vga`, or `vhost-user-gpu`. `primary` is `yes` or `no`. `blob` and `edid` are `on` or `off`. `heads` and `vram` are unsigned integers. `ram`, `vgamem`, and `vram64` are unsigned integers and only for `type=qxl`. `resolution=WxH` (both dimensions greater than 0) is written as `<resolution x="W" y="H"/>`. `accel3d` and `accel2d` (`yes` or `no`) and `rendernode` (non-empty) are written on `<acceleration>`, not on `<model>`.

Model attributes are written in this order when present: `type`, `device`, `vram`, `heads`, `primary`, `blob`, `edid`, `ram`, `vgamem`, `vram64`. Then `<resolution>`, then `<acceleration>`.

```xml
<video>
  <model type="virtio" device="virtio-gpu" vram="16384" heads="1" primary="yes" blob="on" edid="off">
    <resolution x="1920" y="1080" />
    <acceleration accel3d="yes" accel2d="no" rendernode="/dev/dri/renderD128" />
  </model>
</video>
```

### volatile2dev.py

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


To do the changes when hot-attaching a volatile disk the original `attach_disk` script (`/var/lib/one/remotes/vmm/kvm/attach_disk`) should be overridden too:

```
VM_MAD = [
    ...
    ARGUMENTS = "... -l deploy=deploy-tweaks,attach_disk=attach_disk.storpool",
    ...
]
```

### `sysinfo_smbios.py`

Adds `smbios` information to the VMs. An entry in the OS element is created to enable the `smbios sysinfo`:

```xml
<os>
  <smbios mode="sysinfo"/>
</os>
```

When at least one of the following variables are defined in the USER_TEMPLATE.

An existing `<smbios mode='sysinfo'/>` is left in place and the entries are still written. Any other `mode` exits 2, which aborts the deploy. A missing `<smbios>` is created with `mode='sysinfo'`.

A block named in the template replaces that block's entries. Unknown entry names are omitted. `bios` `date` must be `mm/dd/yy` or `mm/dd/yyyy`. `system` `uuid` is accepted in addition to the names below. It must be a UUID, and it must match `<hwuuid>` when that element is present, otherwise `<uuid>`.

`<baseBoard>` may be repeated. Separate boards with `|`.

#### `T_SMBIOS_BIOS`

A list of variables in format `key=value` separated by a semi-colon. Here is an example:

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

Note the special formatting of the *date* and *release* elements in the libvirt documentation!

#### `T_SMBIOS_SYSTEM`

A list of variables in format `key=value` separated by a semi-colon. Here is an example:

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

#### `T_SMBIOS_BASEBOARD`

A list of variables in format `key=value` separated by a semi-colon. Here is an example:

```
USER_TEMPLATE/T_SMBIOS_BASEBOARD="manufacturer=BBManufacturer;version=BBVersion;serial=BBSerial;product=BBProduct;asset=BBAsset;location=BBLocation|manufacturer=Second"
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

The `|manufacturer=Second` above starts a second `<baseBoard>`.

#### `T_SMBIOS_CHASSIS`

A list of variables in format `key=value` separated by a semi-colon. Here is an example:

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

#### `T_SMBIOS_OEMSTRINGS`

A list of strings separated by a semi-colon. Here is an example:

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

### persistent-cdrom.py

CD-ROM attach and detach insert or eject the medium. The device stays in the domain. `T_PERSISTENT_CDROM` is how many of those devices to keep, at most 4. A value on the VM overrides the global one. `0` leaves the domain as OpenNebula wrote it.

On a pc machine the IDE bus has four slots, `hda`–`hdd`, shared with IDE hard disks. The context CD-ROM uses one. The script adds an empty drive on each free name until `T_PERSISTENT_CDROM` CD-ROM devices exist, or the slots run out.

On q35 the context CD-ROM keeps the name OpenNebula assigned, and `onevm updateconf` updates that disk. Each image CD-ROM is renamed to `sdzz`, then `sdzy`, `sdzx`, `sdzw`. Empty trays are added until `T_PERSISTENT_CDROM` of those names exist. The guest sees the image under the tray name. Hard disks keep the names OpenNebula assigned.

The trays are addressed on the SATA controller after the last one a hard disk uses, units 0–3. The script adds that controller and removes the per-disk AHCI controllers OpenNebula wrote for the CD-ROMs it moved. Controller 0 stays with the context disk.

An eject leaves the tray. The tray name is one OpenNebula does not hand out, so the next disk can use `sda`. A later attach inserts the image into an empty tray. The guest keeps seeing the tray names it saw at boot.

#### System configuration

1. Activate `persistent-cdrom.py`:

   ```
   su - oneadmin
   cd ~oneadmin/remotes/vmm/kvm/deploy-tweaks.d
   ln -s ../deploy-tweaks.d.example/persistent-cdrom.py
   ```

2. Edit the OpenNebula configuration to use the alternate (local) scripts for `attach_disk` and `detach_disk`, restart the opennebula service, and propagate the changes to the hosts:

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

3. Configure the number of CDROM devices globally in the `addon-storpoolrc` file:

   ```
   T_PERSISTENT_CDROM=4
   ```

   Or, per VM in the VM attributes(also known as _USER_TEMPLATE_):
   
   ```
   USER_TEMPLATE/T_PERSISTENT_CDROM="4"
   ```

   Note: The value per VM overrides the global definition, so to disable the function for a VM when there is a global definition, just set `T_PERSISTENT_CDROM=0`.

4. To define the persistent CDROM devices to be backed with file based images set:

   ```
   T_PERSISTENT_CDROM_TYPE="file"
   ```

## `cputune.py`

Use libvirt `vCPU` tune parameters instead of cpu/shares (or in addition to the `cpushares`). Refer to the documentation if libvirt for details.

The following parameters could be set as a global defaults in the `addon-storpoolrc` file, and as overrides per VM in the VM Attributes:

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

By default, the script removes the cpu/shares when a CPU tune parameter is defined. To keep the cpu/shares, define the following variable as a global variable or as VM attribute:

```
T_CPUTUNE_SHARES_KEEP=1
```

