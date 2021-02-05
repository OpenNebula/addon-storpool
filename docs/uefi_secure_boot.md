### UEFI + Secure Boot support

#### Configuration

1. Set ONE_PX variable in /var/lib/one/remotes/etc/vmm/kvm/kvmrc to match the one in /var/lib/one/remotes/addon-storpoolrc

```bash
grep '^ONE_PX=' /var/lib/one/remotes/addon-storpoolrc >>/var/lib/one/remotes/etc/vmm/kvm/kvmrc
```

2. The OVMF files must be in /var/lib/one/remotes/OVMF

```bash
#CentOS7 example
yum -y install OVMF
cp -a /usr/share/OVMF/ /var/lib/one/remotes/OVMF/
chown -R oneadmin.oneadmin /var/lib/one/remotes
su - oneadmin -c 'onehost sync --force'
```

3. Restrict the variables to oneadmin only

```bash
echo "VM_RESTRICTED_ATTR = \"T_OS\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_OS_LOADER\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_OS_NVRAM\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_FEATURE_SMM\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_FEATURE_SMM_TSEG\"" >>/etc/one/oned.conf
```

4. Enable the os.py deploy-tweak on the frontend

```
 cd /var/lib/one/remotes/vmm/kvm/deploy-tweaks.d
 ln -s ../deploy-tweaks.d.example/os.py .
 ln -s ../deploy-tweaks.d.example/feature_smm.py .
```

#### Variable format


##### T_OS

"space separated list of element attributes"

Common for the topic:

*firmware=efi*


##### T_OS_LOADER

*PATH_TO_LOADER*:*space separated list of element attributes in format key=value*

*PATH_TO_LOADER* is the absolute path to the firmware file on the KVM node

Common attributes:

*readonly=yes* - mandatory
*type=pflash* - mandatory
*secure=yes* - optional, used to define secure boot, require T_FEATURE_SMM=":state=on"

##### T_OS_NVRAM

*PATH_TO_VM_NVRAM_FILE*:*space separated list of element attributes in format key=value*

*PATH_TO_VM_NVRAM_FILE* with the *storpool* keyword the path will be a StorPool Volume. When there are no '/' in the string it is considered a relative path against the environment variable *NVRAM_TEMPLATE_PATH* (defined in *kvmrc* or *addon-storpoolrc* file)

To define which file to use as a template for the UEFI nvram (The file must be available in /var/lib/one/remotes/OVMF/ folder).
For OpenNebula VM Templates the variables should be set as "*Tags*" named *T_OS_LOADER*

#### Usage

```
T_OS_LOADER = "/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash"
T_OS_NVRAM = "storpool:template=OVMF_VARS.fd"
```

For UEFI + Secure Boot

```
T_OS_LOADER = "/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash secure=yes"
T_OS_NVRAM = "storpool:template=OVMF_VARS.secboot.fd"
T_FEATURE_SMM = ":state=on"
```

Definig these variable any existing definitions in the domain XML will be replaced!

##### New VMs

During VM instantiation when the contextualization is built the configured in *T_OS_NVRAM* file will be dumped to a StorPool volume.
Nex the *os.py* deploy-tweak will replace the *os/loader* and *os/nvram* elements in the domain XML the StorPool volume as a persistent UEFI nvram storeage.

##### Existing VMs

(note: for UEFI Secure Boot replace *OVMF_VARS.fd* with *OVMF_VARS.secboot.fd*)

Following the naming convention create a StorPool volume with exact size as the *OVMF_VARS.fd* file, attach the volume to the node where the VM is running and dump the raw content of the *OVMF_VARS.fd* inside.

```bash
storpool volume ${ONE_PX}-sys-${VM_ID}-NVRAM size 528k template ${ONE_PX}-ds-${SYSTEM_DS_ID} tag nvm=${VM_ID} tag vc-policy=${VM_VC_POLICY}
storpool attach volume ${ONE_PX}-sys-${VM_ID}-NVRAM here
dd if=.../OVMF_VARS.fd of=/dev/storpool/${ONE_PX}-sys-${VM_ID}-NVRAM oflag=direct
```
note: `tag vc-policy=${VM_VC_POLICY}` could be skipped when there is no VC_policy defined for the given VM

When the StorPool Volume is ready define *T_OS_LOADER* and *T_OS_NVRAM* (*T_FEATURE_SMM* for SecureBoot) as "VM Attributes"

```bash
# from command line
echo "T_OS_LOADER = \"/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash\"" > append.template
echo "T_OS_NVRAM = \"storpool:template=OVMF_VARS.fd\"" >>append.template
onevm update $VM_ID --append append.template
```

Finally the VM should be restarted from OpenNebula with power cycling (power-off --> resume) for change to take effect.
