## Installation

The function to update the VM and enforce the policy is part of the [volumecare helper script](volumecare.md)

## Setting QoS tags

There are several places to set QoS tag names. Here is the list described by priority from lower to higher

Note: The tag name must not have colon ':' or semicolon ';' in the name!

### Global QoS Class tag name

`DEFAULT_QOSCLASS=QoS_class_tag_name` in _/var/lib/one/remotes/addon-storpoolrc_. This will set QoS class tag on each VM disk if there is no specific one set

### For VM QoS Class tag name

In the VM attributes could be set the QoS class tag via the variable named `SP_QOSCLASS`. The value will override the _DEFAULT_QOSCLASS_ variable.

Example:
`SP_QOSCLASS=QosClassTagName`


### For a Persistent image QoS Class tag name

In the Persistent image attributes add variable named `SP_QOSCLASS`. The value will override the _DEFAULT_QOSCLASS_ and the _VM_QOSCLASS_ for the VM.

Example:
`SP_QOSCLASS=QosClassTagName`

### Per VM Disk QoS Class tag name

The `SP_QOSCLASS` variable in the VM attribute could be extended with a semicolon ';' separated list of specific QoS tag for given disks in format `{VM_DISK_ID}:QosClassTagName`

Example 1:
`SP_QOSCLASS=defaultVMQosTagName;2:QosTagNameForDiskId_2;4:QosTagNameForDiskId_4`
In the above example the VM will have QoS tag named `defaultVMQosTagName` but the disks with _DISK_ID_ 2 and 4 will have `QosTagNameForDiskId_2` and `QosTagNameForDiskId_4` respectively.

Example 2:
`SP_QOSCLASS=0:QosTagNameForDiskId_0;0:QosTagNameForDiskId_3`
All VM disks will have the Global Default QoS Class tag name, if defined, but disks with _DISK_ID_ 0 and 3 will have `QosTagNameForDiskId_0` and `QosTagNameForDiskId_3` respectively.

Note: The defined VM Disk QoS Class tag will override the defined QoS Class tag name for a Persistent image!
