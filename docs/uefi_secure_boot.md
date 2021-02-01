### UEFI Secure Boot support

#### Configuration

1. Set ONE_PX variable in /var/lib/one/remotes/etc/vmm/kvm/kvmrc to match the one in /var/lib/one/remotes/addon-storpoolrc

```bash
grep '^ONE_PX=' /var/lib/one/remotes/addon-storpoolrc >>/var/lib/one/remotes/etc/vmm/kvm/kvmr
```

2. The OVMF files must be in /var/lib/one/remotes/OVMF

```bash
#CentOS7 example
yum -y install OVMF
cp -a /usr/share/OVMF/ /var/lib/one/rempotes/OVMF/
chown -R oneadmin.oneadmin /var/lib/one/rempotes
su - oneadmin -c 'onehost sync --force'
```

3. Restrict the OVMF_VARS_FD variable to oneadmin only

```bash
   echo "VM_RESTRICTED_ATTR = \"T_OS_LOADER\"" >>/etc/one/oned.conf
   echo "VM_RESTRICTED_ATTR = \"T_OS_NVRAM\"" >>/etc/one/oned.conf
```

#### Usage


To define which file to use as a template for the UEFI nvram (The file must be available in /var/lib/one/remotes/OVMF/ folder)

USER_TEMPLATE/T_OS_LOADER = "/var/tmp/one/OVMF/OVMF_CODE.secboot.fd:readonly=yes type=pflash"
USER_TEMPLATE/T_OS_NVRAM = "storpool:template=OVMF_VARS.fd"


##### New VMs

During VM instantiation when the contextualization IS built the provided in *T_OS_NVRAM* file will be dumped to a StorPool volume and the domain XML will be adjusted to use the volume as persistent UEFI nvram storeage.


##### Existing VMs

Following the naming convention create a StorPool volume with exact size as the *OVMF_VARS.fd* file, attach the volume to the node where the VM is running and dump the raw content of the *OVMF_VARS.fd* inside.

```bash
dd if=.../OVMF_VARS.fd of=/dev/storpool/${ONE_PX}-sys-${VM_ID}-NVRAM oflag=direct
```
