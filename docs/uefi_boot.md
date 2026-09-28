# UEFI Legacy/Secure Boot support

## Configuration

1. The `OVMF` files must be in `/var/lib/one/remotes/OVMF`:

   ```bash
   #CentOS7 example
   yum -y install OVMF
   cp -a /usr/share/OVMF/ /var/lib/one/remotes/OVMF/
   chown -R oneadmin.oneadmin /var/lib/one/remotes
   su - oneadmin -c 'onehost sync --force'
   ```

2. Restrict the variables to oneadmin only:

   ```bash
   echo "VM_RESTRICTED_ATTR = \"T_OS\"" >>/etc/one/oned.conf
   echo "VM_RESTRICTED_ATTR = \"T_OS_LOADER\"" >>/etc/one/oned.conf
   echo "VM_RESTRICTED_ATTR = \"T_OS_NVRAM\"" >>/etc/one/oned.conf
   echo "VM_RESTRICTED_ATTR = \"T_FEATURE_SMM\"" >>/etc/one/oned.conf
   echo "VM_RESTRICTED_ATTR = \"T_FEATURE_SMM_TSEG\"" >>/etc/one/oned.conf
   ```

3. Enable the `os.py` deploy-tweak on the frontend:

   ```
    cd /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
    ln -s ../deploy-tweaks.d.example/os.py .
    ln -s ../deploy-tweaks.d.example/feature_smm.py .
   ```

## Variable format

### T_FEATURE_SMM

Format: `:space separated list of element attributes`

Common element attributes:
| attribute | description |
| --------- | ----------- |
| `state=on` | optional |

For details, see the [libvirt docs](https://libvirt.org/formatdomain.html#hypervisor-features).

### T_FEATURE_SMM_TSEG

Format: `SIZE:space separated list of element attributes`

Where `SIZE` is the amount of RAM reserved for TSEG.

Common element attributes:
| attribute | description |
| --------- | ----------- |
| `unit=MiB` | mandatory |

### T_OS

Format: `:space separated list of element attributes`

Common element attributes:
| attribute | description |
| --------- | ----------- |
| `firmware=efi` | optional |

### T_OS_LOADER

Format: `PATH_TO_LOADER:space separated list of element attributes in format key=value`

Where `PATH_TO_LOADER` is the absolute path to the firmware file on the KVM node.

Common element attributes:
| attribute | description |
| --------- | ----------- |
| `readonly=yes` | mandatory |
| `type=pflash` | mandatory |
| `secure=yes` | optional, used to define secure boot, require T_FEATURE_SMM=":state=on" |

### T_OS_NVRAM

Format: `MODE:space separated list of element attributes in format key=value`

`MODE` is one of:

| mode | description |
| ---- | ----------- |
| `storpool` | the UEFI variables live in a StorPool volume `${ONE_PX}-sys-${VM_ID}-NVRAM` created by the addon (see below) |
| `PATH_TO_VM_NVRAM_FILE` | a file on the KVM node managed by libvirt; a bare file name is placed in the VM directory of the system datastore |
| empty | same as above with the file named after the `template` file |

Element attributes:
| attribute | description |
| --------- | ----------- |
| `template=OVMF_VARS.fd` | in `storpool` mode mandatory: the `OVMF_VARS` file used to seed the volume, a bare file name is resolved against `OVMF_PATH` on the front-end (default `/var/lib/one/remotes/OVMF`); in file mode optional, resolved against `NVRAM_TEMPLATE_PATH` on the KVM node (default `/var/tmp/one/OVMF`) |
| `type=[block\|file]` | optional, type of the nvram element. In `storpool` mode the default is `block` |

In `storpool` mode the domain XML gets the "new style" nvram element that
follows the syntax of a disk source (libvirt 8.5+):

```
<nvram type="block">
  <source dev="/dev/storpool-byid/${globalId}"/>
</nvram>
```

Requirements and limits of the `storpool` mode (verified with libvirt 10.0/QEMU 8.2
on Ubuntu 24.04 and libvirt 11.10/QEMU 10.1 on AlmaLinux 9):

* libvirt 8.5 or newer on the KVM nodes for `type=block`. libvirt 10.10+
  fills in `format="raw"` itself and does not touch the device.
* The volume has exactly the size of the template file. QEMU maps the pflash
  at the size of the block device: a size that is not a multiple of 4KiB is
  refused at VM start, a larger size shifts the firmware layout and OVMF does
  not find its variable store. StorPool keeps the requested byte size, so the
  `OVMF_VARS*.fd` files (540672 bytes for the current 4M builds) work as they are.
* The VM must have a `CONTEXT` section: the volume is created by the
  `context` transfer driver, which OpenNebula only invokes for VMs with context.
* The volume is not part of VM backups, matching upstream OpenNebula which
  does not back up the nvram file either. A restored VM starts with the
  variables of the template again.
* Live and cold migration, VM snapshots (create/revert/delete) and terminate
  handle the volume like the VM disks.

For OpenNebula VM Templates, the variables should be set as "*Tags*" named *T_OS_LOADER*

## Usage

Setting variables this way:

```
T_OS_LOADER = "/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash"
T_OS_NVRAM = "storpool:template=OVMF_VARS.fd"
```

will generate the following domain XML (the volume is addressed by its
StorPool globalId):

```
  <os>
    <loader readonly="yes" type="pflash">/var/tmp/one/OVMF/OVMF_CODE.secboot.fd</loader>
    <nvram type="block">
      <source dev="/dev/storpool-byid/fir.b.tqq" />
    </nvram>
  </os>
```

For UEFI + Secure Boot:

```
T_OS_LOADER = "/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash secure=yes"
T_OS_NVRAM = "storpool:template=OVMF_VARS.secboot.fd"
T_FEATURE_SMM = ":state=on"
```

As a result of defining these variable any existing definitions in the domain XML will be replaced!

### New VMs

During VM instantiation, when the contextualization is built, the `context`
transfer driver creates the StorPool volume with the exact size of the
`template` file, seeds it with the file content and registers it in the KV
store. Next, the `os.py` deploy-tweak replaces the `os/loader` and `os/nvram`
elements in the domain XML with the StorPool volume as persistent UEFI nvram
storage. A missing template file, a template size that is not a multiple of
4KiB or a volume missing from the KV store fail the deployment (the VM goes to
`FAILURE`) instead of booting the VM with the wrong firmware setup.

### Existing VMs

Define *T_OS_LOADER* and *T_OS_NVRAM* (*T_FEATURE_SMM* for SecureBoot) as
"VM Attributes":

```bash
# from command line
echo "T_OS_LOADER = \"/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash\"" > append.template
echo "T_OS_NVRAM = \"storpool:template=OVMF_VARS.fd\"" >>append.template
onevm update $VM_ID --append append.template
```

Note: for UEFI Secure Boot replace `OVMF_VARS.fd` with `OVMF_VARS.secboot.fd`.

Finally, power cycle the VM from OpenNebula (power-off --> resume): the
`context` driver creates and seeds the volume at the next deployment, no
manual volume creation is needed. An existing volume with the right name is
attached and used as is.
