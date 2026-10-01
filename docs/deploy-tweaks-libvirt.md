# Deploy-tweaks compared with libvirt

Comparison of `vmm/kvm/deploy-tweaks.d.example` with libvirt `v12.8.0-rc2`
at `~/work/git/github/libvirt`. Sources used:

* `src/conf/schemas/domaincommon.rng`, `cputypes.rng`, `basictypes.rng`
* `docs/formatdomain.rst`
* parsers and checks in `src/conf/domain_conf.c`, `src/conf/domain_validate.c`,
  `src/qemu/qemu_validate.c`

The OpenNebula-side comparison is `docs/deploy-tweaks-upstream.md`. This note
is only about whether the XML the tweaks write is defined by libvirt, and
which current libvirt forms the same topic already has.

## Not defined, or defined but ignored

### `hv-enlightenments.py`: `time` and `crash`

`virDomainHyperv` has no `time` or `crash` child. The script used to append
those elements, and a define failed with "unsupported HyperV Enlightenment
feature". It now ignores `T_HV_TIME` and `T_HV_CRASH` and reports that on
stderr.

The defined children are `relaxed`, `vapic`, `spinlocks`, `vpindex`,
`runtime`, `synic`, `stimer`, `reset`, `vendor_id`, `frequencies`,
`reenlightenment`, `tlbflush`, `ipi`, `evmcs`, `avic`, `emsr_bitmap`, and
`xmm_input`.

`<spinlocks state='on'/>` with no `retries` is accepted on this tree.
Omitted `retries` defaults to `4294967295` (never notify the hypervisor,
since 11.9.0). A count below `4095` is rejected. The script writes
`retries='8191'` unless the template sets another count.

A second child with the same name is not rejected by the parser, which
stores the last `state`. The script now updates the existing child and
drops the earlier copy.

### `q35-pcie-root.py`: a second `pcie-root`

`pcie-root`, `pcie-root-port`, and `pcie-to-pci-bridge` are valid controller
models. The script appends a second `<devices>`. The schema allows one. The
parser still reads controllers from both, then `qemu_validate.c` requires
every `pcie-root` index to be 0. The extra root gets the next index and the
define fails with "Index for 'pcie-root' controllers must be 0".

### `nvme-disk.py` and `nvme-block.py`: namespace 0

`<disk type='nvme'>` with `<source type='pci' managed='yes'>` and a PCI
`<address>` is the documented host-NVMe backend. `namespace='0'` is not:
namespaces start at 1 (`domain_validate.c`, "NVMe namespace can't be zero").
Both scripts set `namespace` from the attribute index, so index 0 is
rejected. The two scripts emit the same XML.

### `console.py`: a fixed pty path

`tty` and `<source path>` are in the character-device schema, but they are
live-XML fields. For an inactive domain the parser skips a pty
`<source path>`, and `tty` is only written back when formatting a running
console. Hardcoding `/dev/pts/5` does not allocate that node.

## Same topic, current libvirt form

Work through these one at a time. Each item is a plan, then an
implementation, then a commit.

### 1. Hyper-V (`hv-enlightenments.py`, `hyperv-clock.py`)

`hv-enlightenments.py` writes this shape. `hyperv-clock.py` is unchanged.

Since 8.0.0 `<hyperv>` has `mode`: `custom` (the default), `passthrough`
(every enlightenment the hypervisor supports; the parser ignores children),
and `host-model` (expanded into the live XML, since 11.9.0). `T_HV_MODE`
sets that attribute. `passthrough` leaves the children alone.

The script also writes `vendor_id` (`value`, at most 12 characters),
`avic`, `emsr_bitmap`, `xmm_input`, `<stimer><direct>`, and
`<tlbflush><direct>` plus `<extended>`.

The four timers in `hyperv-clock.py` match the schema: `rtc`
`tickpolicy='catchup'`, `pit` `tickpolicy='delay'`, `hpet` `present='no'`,
`hypervclock` `present='yes'`. The other clock timer, for Linux guests, is
`kvmclock`.

### 2. KVM hide (`kvm-hide.py`)

`kvm-hide.py` writes this shape.

`<kvm>` children are `hidden`, `hint-dedicated`, `poll-control`, `pv-ipi`,
and `dirty-ring`. `T_KVM_HIDE` is `hidden`. The other template keys are
`T_KVM_HINT_DEDICATED`, `T_KVM_POLL_CONTROL`, `T_KVM_PV_IPI`, and
`T_KVM_DIRTY_RING`. `on` or `1` sets `state='on'` and creates `<features>`
and `<kvm>` when they are missing. `off` or `0` sets `state='off'` on an
existing child.

`dirty-ring` `size` is required when `state='on'`: a power of two from 1024
to 65536. `T_KVM_DIRTY_RING=on:size=4096` sets it. `on` alone keeps a size
already on the element. `off` drops `size`.

### 3. SMM (`feature_smm.py`)

`feature_smm.py` writes this shape.

`<smm state='on'><tseg unit='MiB'>48</tseg></smm>`. `state` is `on` or
`off`. A missing `state` is `on`. `T_FEATURE_SMM` sets it. Text before the
colon is ignored.

`<tseg>` is a scaled integer. `T_FEATURE_SMM_TSEG=42:unit=MiB` sets the
size. The unit defaults to `MiB`. `0` does not advertise an extended TSEG
size. The size must be a whole number of MiB. `<tseg>` is written only when
SMM is on.

### 4. SMBIOS (`sysinfo_smbios.py`)

`sysinfo_smbios.py` writes this shape.

`<os><smbios mode='sysinfo'/></os>` and `<sysinfo type='smbios'>` with
`bios`, `system`, `baseBoard`, `chassis`, and `oemStrings`. Unknown entry
names are omitted. `bios` `date` must be `mm/dd/yy` or `mm/dd/yyyy`.
`system` `uuid` must match `<hwuuid>` when that element is present,
otherwise `<uuid>`.

`<baseBoard>` may be repeated. `T_SMBIOS_BASEBOARD` separates boards with
`|`. Guest data stays in `oemStrings`.

### 5. UEFI (`os.py`)

`<nvram type='block'><source dev='...'/></nvram>` is the form added in
8.5.0 (`file`, `block`, and `network`, same `<source>` as a disk). Later
knobs the tweak does not set: `format` and `templateFormat` (`raw` or
`qcow2`, since 9.2.0 and 10.10.0), `<os firmware='efi'>` with
`<loader secure= stateless= format=>` and
`<feature name='enrolled-keys|secure-boot'>` (autoselection since 5.2.0),
and `<varstore path= template=>` (the `uefi-vars` device, since 12.1.0)
instead of pflash `<nvram>`.

### 6. CPU (`cpu.py`, `resizeCpuMem.py`)

`<vcpu current=>`, `<vcpus><vcpu id= enabled= hotpluggable=></vcpus>`,
`<topology sockets= cores= threads=>`, `<numa><cell id= cpus= memory=></cell>`,
`match` (`minimum`, `exact`, `strict`), `check` (`none`, `partial`, `full`),
feature `policy` (`force`, `require`, `optional`, `disable`, `forbid`), and
model `fallback` (`allow`, `forbid`) are defined. `mode` also has
`maximum`, which the tweak's list does not. Topology may also carry `dies`
and `clusters`. A cell may set `unit` (default KiB), `memAccess`, and
`discard`. The CPU element can also carry `<cache>` and `<maxphysaddr>`.

`resizeCpuMem.py` only does ballooning (`<memory>` is the max,
`<currentMemory>` is the current size). DIMM hotplug is
`<maxMemory slots='N'>`.

### 7. Queues and iothreads

`blk-queues.py`, `scsi-queues.py`, `nic-queues.py`, and `iothreads.py`
write forms libvirt accepts: `<driver queues=>` on a virtio disk and on a
SCSI controller, `<driver name='vhost' queues=>` on an interface, and
`<iothreads>1</iothreads>` plus `<driver iothread='1'>`.

Current extras: disk `queue_size`; per-queue
`<driver><iothreads><iothread id='1'><queue id='0'/>`; `<iothreadids>` with
`thread_pool_min`, `thread_pool_max`, and `<poll>`; interface
`rx_queue_size`, `tx_queue_size`, and `txmode` (`iothread` or `timer`);
SCSI controller `cmd_per_lun` and `max_sectors`. `io` is `threads`,
`native`, or `io_uring`. The tweaks only set `native`.

### 8. Disk cache (`disk-cache-io.py`, `context-cache.py`)

`cache='none'` and `io='native'` are valid. The same driver element also
has `discard` (`unmap` or `ignore`), `detect_zeroes`, `ioeventfd`, and
`queue_size`.

### 9. PCI topology and NVMe

Root ports can also set `model name=`, `hotplug`, and
`<target chassis= port=>`. Libvirt fills index, chassis, and port when they
are omitted, which is why one unindexed `pcie-root` is fine and a second
one is not.

Host NVMe presented as virtio (`type='nvme'`, `target bus='virtio'`) is one
backend. The other is an emulated guest controller:
`<controller type='nvme'>` and `<target bus='nvme' dev='nvme0n1'>`.

### 10. Video (`video.py`)

`vga`, `cirrus`, `vmvga`, `qxl`, `virtio`, `bochs`, `ramfb`, `gop`, and
`none` are model types. `primary`, `vram`, `heads`, and
`<acceleration accel2d= accel3d= rendernode=>` match. Also defined:
virtio `device` (`virtio-vga`, `virtio-gpu`, the `-gl` variants,
`vhost-user-*`), `blob`, `edid`, and `<resolution x= y=>`.

## Already the documented element

No libvirt-schema change suggested for these:

* `uuid.py` writes `<uuid>`.
* `cputune.py` writes `shares`, `period`, `quota`, `global_period`,
  `global_quota`, `emulator_period`, `emulator_quota`, `iothread_period`,
  and `iothread_quota`. It does not write `vcpupin`, `iothreadpin`, or
  `cachetune`.
* `vfhostdev2interface.py` matches
  `<interface type='hostdev' managed='yes'>` with `<driver name='vfio'/>`
  and `<source><address type='pci'>`. The driver may also set `iommufd`.
* `persistent-cdrom.py` uses
  `<address type='drive' controller= bus= target= unit=>`.
  `qemu_validate.c` requires SATA `bus` 0 and `target` 0.
* `disk-serial.py` uses `<serial>`. The allowed characters are
  `[A-Za-z0-9_ .+\\-]`.
* `volatile2dev.py` flips `type='file'` to `type='block'` and `source file`
  to `source dev`.
