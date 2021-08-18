# Live resize CPU and Memory


## Limitations

The functionality has the following limitations:

* not compatible with OpenNebula's NUMA configuration
* not compatible with hugepages

Tested with OpenNebula 5.10 should work with 5.12, 6.0+ has native functionality

## Installation

Enable the deploy-tweaks script:

```bash
mkdir -p ~oneadmin/remotes/vmm/kvm/deploy-tweaks.d
cd ~oneadmin/remotes/vmm/kvm/deploy-tweaks.d
ln -s ../deploy-tweaks.d.example/resizeCpuMem.py resizeCpuMem.py
cd -
```

Install the helper hook

```bash
cp addon-storpool/hooks/resizeCpuMem.sh ~oneadmin/remotes/hooks/resizeCpuMem.sh
onehook create addon-storpool/misc/resizeCpuMem.hook
chown -R oneadmin.oneadmin ~oneadmin/remotes
```

Add protected variables 

```bash
echo "VM_RESTRICTED_ATTR = \"T_VCPU_MAX\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_VCPU_NEW\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_CPU_SHARES\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_MEMORY_MAX\"" >>/etc/one/oned.conf
echo "VM_RESTRICTED_ATTR = \"T_MEMORY_NEW\"" >>/etc/one/oned.conf

systemctl restart opennebula
```

## Configuration

To trigger the reconfiguration of the domain XML:

* Set *T_VCPU_MAX* to enable VCPU hotplug
* Set *T_MEMORY_MAX* to enable Memory hotplug 

## Usage

After a VM is restarted and the new domain XML configuration is in place it is possible to change the number of VCPUs and the size of the VM Memory.

### VCPU change

* Set *T_CPU_SHARES* to the new value(this is the CPU element in the VM/Cpu tab)
* Set *T_VCPU_NEW* to the desired number of VCPUs.

On success the relevant VM elements will be updated ant the *T_VCPU_NEW* variable will be deleted.

### Memory change

* Set *T_MEMORY_NEW* to the desired new size (in MiB).

On success the relevant VM elements will be updated ant the *T_MEMORY_NEW* variable will be deleted.

## API

Using *one.vm.update* API call all variables could be set in a single call.


