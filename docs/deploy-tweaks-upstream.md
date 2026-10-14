# Deploy-tweaks compared with upstream OpenNebula

Comparison of `vmm/kvm/deploy-tweaks.d.example` with OpenNebula master at
`release-7.1.80` (`87389d952d`, 7.2 development). Upstream sources:

* `src/vmm/LibVirtDriverKVM.cc` (`deployment_description_kvm`)
* `src/vmm_mad/exec/x86_64/vmm_exec_kvm.conf`

The tweaks rewrite the domain XML after oned has generated it, then hand
the result to the stock `vmm/kvm/deploy`. On this tree much of that XML is
first-class. Several tweaks repeat it, and a few overwrite a better result.

`deploy-tweaks` treats exit 0 as "keep this XML", exit 2 as "abort the
deploy", and any other exit as "log a warning and keep the previous XML".

## Upstream is the better implementation

Do not link these on a current KVM host. Where both run, the tweak runs
second and can undo the upstream XML.

| Tweak | Upstream | Since | If both run |
|---|---|---|---|
| `resizeCpuMem.py` | `VCPU` / `VCPU_MAX`, `MEMORY` / `MEMORY_MAX`, `MEMORY_RESIZE_MODE` | 6.0 | The tweak writes `<vcpu current>` and `<vcpus>` from `T_VCPU_MAX`, a balloon ceiling from `T_MEMORY_MAX` (`<memory>` is the max, `<currentMemory>` the current size), and `<maxMemory slots>` from `T_MAXMEMORY` plus `T_MAXMEMORY_SLOTS`. Upstream writes the same elements from the template attributes, with `MEMORY_SLOTS` default 16. |
| `cpuShares.py` | `<cputune><shares>` from the VM `CPU` attribute | long-standing; cgroup v2 scaling is in this tree | Upstream uses `ceil(CPU × 1024)` on cgroup v1 and `ceil(CPU × 100)` on cgroup v2, clamped. The tweak uses `ceil(VCPU × T_CPUTUNE_MUL × 1024)` with mul default `0.1`, and ignores cgroup v2. An absolute `T_CPUTUNE_SHARES` is the only extra knob. |
| `q35-pcie-root.py` | `Q35_ROOT_PORTS` (default 16), plus a NUMA expander topology | 6.8 | Both write an indexed `pcie-root`, root ports, and a `pcie-to-pci-bridge`. The tweak replaces every `type='pci'` controller with that flat set, so on a VM with NUMA nodes it removes the `pcie-expander-bus` controllers upstream wrote (`CURRENT-ISSUES.md` issue 46). `Q35_ROOT_PORTS` is host/cluster only; a per-VM port count is the one knob upstream lacks. |
| `uuid.py` | `OS/UUID` | 6.0 | Same `<uuid>` element. `OS/UUID` is the attribute that belongs in the template. |
| `hyperv-clock.py` | `HYPERV_TIMERS` | same shape as the tweak | The four timers match the stock config: rtc catchup, pit delay, hpet off, hypervclock on. Emitted when `FEATURES/HYPERV=yes`. The tweak deletes and rewrites those same timers. |
| `blk-queues.py` | `FEATURES/VIRTIO_SCSI_QUEUES=auto` | 6.8 | `auto` means "equal to `VCPU`". The stock config already sets that. This script only edits the SCSI controller. `T_BLK_QUEUES` does not match what it changes. |
| `console.py` | commented `RAW` example in `vmm_exec_kvm.conf` | example only | The script is that example, including `source path="/dev/pts/5"`. Upstream does not emit a serial or console by default. A fixed pts path is a host-local node, not a pty libvirt allocates. |

`hv-enlightenments.py` overlaps the stock `HYPERV_OPTIONS`, which turns on
relaxed, vapic, spinlocks (`retries='8191'`), vpindex, runtime, synic,
stimer, frequencies, tlbflush, and ipi, and turns reset, reenlightenment,
and evmcs off. For those children the tweak sets `state` on the element
upstream wrote. Its own knobs are `T_HV_MODE`, `vendor_id`, `avic`,
`emsr_bitmap`, `xmm_input`, `<stimer><direct>`, and `<tlbflush>` `direct`
and `extended`, none of which upstream writes.

## Same idea, upstream is broader, the tweak has one extra knob

### `scsi-queues.py` and `nic-queues.py`

Upstream sets virtio-scsi queues from `VIRTIO_SCSI_QUEUES` (default `auto`)
and virtio-nic queues from `NIC/VIRTIO_QUEUES` (default `auto` since 7.0;
per-NIC `VIRTIO_QUEUES` since 2018). Virtio-blk queues are
`FEATURES/VIRTIO_BLK_QUEUES` or per-disk `VIRTIO_BLK_QUEUES`, and they are
off in the stock config.

With `auto` both tweaks read `<vcpu current>`, falling back to the `<vcpu>`
text, so they agree with upstream after `VCPU_MAX`. Per-NIC upstream uses
the NIC attribute. The tweak reads `T_NIC<id>_QUEUES`, with the id parsed
from the `one-<vmid>-<nicid>` target name. The extra knobs are the driver
attributes: `cmd_per_lun`, `max_sectors`, and `queue_size` on SCSI and
`vd*` disks, `rx_queue_size`, `tx_queue_size`, and `txmode` on NICs.

`scsi-queues.py` and `blk-queues.py` both set SCSI controller queues.
Linking both is redundant.

### `iothreads.py`

Upstream `FEATURES/IOTHREADS` (default 0) plus per-disk `IOTHREAD` round-robins
virtio disks and the virtio-scsi controller. The tweak round-robins
`T_IOTHREADS` threads over `vd*` disks and then virtio-scsi controllers,
sets `io` (default `native`) on the `vd*` disks, and can write
`<iothreadids>` pool and poll attributes. `T_IOTHREADS_OVERRIDE=0` leaves
the domain alone. With neither key set, an existing `<iothreads>` stays.

`io='native'` and the pool and poll attributes are the parts the driver
does not write. Hotplug in `attach_disk` accepts `IOTHREAD` and
`VIRTIO_BLK_QUEUES`.

### `disk-cache-io.py` and `context-cache.py`

Stock `DISK` is `CACHE=none`, `DISCARD=unmap`, driver `raw`, and no `IO`.
The cache half of `disk-cache-io.py` already matches upstream for every disk,
not just StorPool. The useful delta is `io='native'` on StorPool volumes.

Context disks are hardcoded `cache='none'` with no `io` and no `discard`.
`context-cache.py` sets `io='native'` on every `type='file'` CD-ROM and on
the context CD-ROM after `volatile2dev.py` has flipped it to `type='block'`.
`disk-cache-io.py` leaves that disk id alone. `io='native'` on a
file-backed context ISO is a poor fit.

### `disk-serial.py`

Since 7.0, `DISK/SERIAL` is written as `<serial>`. Upstream skips it for SCSI
block devices, because qemu does not support a serial there. The tweak
invents a 20-character md5 (`vm-disk`, `persistent-<image>`, or
`volatile-<id>`) and will overwrite an explicit serial, including on SCSI
block.

Keep it for the automatic stable id. An image that already has `SERIAL`
should not also run this tweak.

### `cpu.py`

Upstream `CPU_MODEL` (`MODEL`, `FEATURES`), `TOPOLOGY` (sockets, cores,
threads, hugepages, memory access), and `NUMA_NODE` (pinning, distances,
numatune) cover the normal case. Feature policy is always `require`, model
fallback is always `forbid`, mode is `custom` or `host-passthrough`.

The tweak does things the driver does not:

* a `<vendor>` element
* `check` (`none`, `partial`, `full`)
* `match` (`minimum`, `exact`, `strict`)
* feature policies other than `require`
* a configurable model fallback

One overlap is destructive. When `T_CPU_SOCKETS` is set the tweak replaces
the `<topology>`, `<numa>`, and `<vcpus>` upstream generated, including host
pinning. `docs/resizeCpuMem.md` notes that the resize tweak is not
compatible with OpenNebula NUMA.

### `video.py`

Upstream `VIDEO` has `TYPE`, `VRAM`, `RESOLUTION`, and for virtio a driver
with `IOMMU` and `ATS`. The tweak's model attributes (`heads`, `ram`,
`vgamem`, `vram64`, `primary`, `blob`, `edid`, `accel2d`, `accel3d`,
`rendernode`) are absent upstream. If both are set, the tweak replaces
every `<video>` with its own, writes `resolution` only when the key has
one, and drops the iommu `<driver>`.

### `os.py` and `feature_smm.py` versus `OS/FIRMWARE`

This is the important partial overlap.

* `OS/FIRMWARE=UEFI` (this 7.2 tree) emits `<os firmware='efi'>` and lets
  libvirt pick the loader. `FIRMWARE=/path/to/OVMF_CODE.fd` (since 6.2) emits
  `<loader readonly type='pflash'>` and
  `<nvram>{system_dir}/{vmname}_VARS.fd</nvram>`. `FIRMWARE_SECURE` turns on
  secure boot and `<smm state='on'/>`. x86 UEFI also disables suspend-to-disk
  and suspend-to-mem.
* `T_OS="firmware=efi"` writes the same attribute.
* `T_OS_LOADER` overlaps the loader element. Upstream always uses
  `readonly=yes` and `type=pflash`, and it ties `secure=yes` to SMM. The
  tweak leaves SMM to a second script.
* `T_OS_NVRAM=storpool:...` is not upstream. Upstream's NVRAM is a file in
  the system datastore, or libvirt-managed in `firmware='efi'` mode. The
  tweak resolves `one-sys-<vmid>-NVRAM` through etcd and emits
  `<nvram type='block'><source dev='/dev/storpool-byid/…'/>`. That is the
  right shape for a shared StorPool vars volume and for the addon's snapshot
  path. `FIRMWARE=UEFI` is worse for that deployment: the vars never become
  a StorPool volume.
* `T_FEATURE_SMM_TSEG` (the `<tseg>` size) is missing upstream. Upstream
  only emits `<smm state="on"/>` when secure boot is on. For a large
  Windows secure-boot guest the tseg knob is the tweak's.

## No upstream equivalent

These change the domain in ways `LibVirtDriverKVM.cc` does not.

* **`persistent-cdrom.py`.** Nothing upstream keeps an empty CD-ROM device
  and inserts the medium into it. The script keeps up to four. On pc it
  fills the free `hda`–`hdd` names; the context CD-ROM already uses one.
  On q35 it renames image CD-ROMs to `sdzz`–`sdzw` and adds empty trays up
  to `T_PERSISTENT_CDROM`. The context CD-ROM keeps the name oned assigned.
  After an eject the tray stays, under a name OpenNebula does not give to
  the next disk.
* **`volatile2dev.py`.** Turns `type='file'` disks whose `TM_MAD` is
  `storpool` into `type='block'`. Upstream emits `type='block'` only when
  the disk `TYPE` is already `BLOCK`. As long as StorPool system disks show
  up as `disk.N` files, this rewrite does work. A system datastore
  whose context disk type is `BLOCK` already gets a block context device
  from oned.
* **`sysinfo_smbios.py`.** Full `<sysinfo type='smbios'>` plus
  `<os><smbios mode='sysinfo'>`. No driver support. An existing
  `<smbios mode='sysinfo'>` is kept; any other mode exits 2.
* **`kvm-hide.py`.** `<features><kvm>` with `hidden`, `hint-dedicated`,
  `poll-control`, `pv-ipi`, and `dirty-ring`. No driver support. `RAW` can
  paste it, as a raw string rather than a merge into `<features>`.
* **`vfhostdev2interface.py`.** Rewrites PCI `<hostdev>` into
  `<interface type='hostdev'>` with a MAC. Upstream PCI passthrough stays a
  hostdev. NICs are bridge, ethernet, or vhostuser only.
* **`nvme-disk.py` and `nvme-block.py`.** Both add `<disk type='nvme'>` from
  a PCI address. They differ only in the attribute name (`T_NVME_DEVICE*`
  vs `T_NVME_PCIDEVICE*`). Upstream has no NVMe disk type. One of the two
  is enough.
* **`cputune.py`.** `period` / `quota` for vcpu, global, emulator, and
  iothread. Upstream never emits those. `<shares>` is left for
  `cpuShares.py` and for the element OpenNebula already wrote.
* **`force-detach.py`.** Reads the system datastore id and then exits. It
  does not change the domain.

## What to link on a 7.x host

Leave these linked:

* `os.py` for StorPool block NVRAM
* `feature_smm.py` when a tseg size is required
* `volatile2dev.py`
* `disk-cache-io.py` for `io='native'`
* `iothreads.py` only while `FEATURES/IOTHREADS=0`
* `kvm-hide.py`, `sysinfo_smbios.py`, `vfhostdev2interface.py`
* one of the two NVMe scripts
* `cputune.py` when quota or period is used

Do not link these on 6.8 and later:

* `q35-pcie-root.py`, unless no VM has NUMA nodes and a per-VM port count
  is needed
* `blk-queues.py`
* `hyperv-clock.py`
* `uuid.py`
* `resizeCpuMem.py`
* `cpuShares.py`
* `console.py`

On 7.0 and later, `nic-queues.py` and `scsi-queues.py` only add the driver
attributes (`queue_size`, `rx_queue_size`, `tx_queue_size`, `txmode`,
`cmd_per_lun`, `max_sectors`). Link them for those, not for the count.

Use the upstream attributes for the overlapping half of `cpu.py`,
`video.py`, `hv-enlightenments.py`, and `disk-serial.py`: `CPU_MODEL`,
`TOPOLOGY`, `NUMA_NODE`, `VIDEO`, `HYPERV_OPTIONS`, `DISK/SERIAL`. Keep the
tweak for the knob upstream does not have (vendor, check, match, a
non-require feature policy, video acceleration, Hyper-V `mode` and
`vendor_id`, automatic serials).
