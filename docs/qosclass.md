# StorPool QoS Class Configuration

This document describes the configuration options for setting StorPool QoS classes in OpenNebula with the StorPool addon.

## Installation

The function to update the VM and enforce the policy is part of the [volumecare helper script](volumecare.md).

## QoS Class Priority Order

The StorPool addon uses a hierarchical approach to determine which QoS class to apply to a volume. The priority order (from lowest to highest) is:

1. Global default (`DEFAULT_QOSCLASS`)
2. Datastore-level (`SP_QOSCLASS`)
3. Image-level (for persistent images) (`SP_QOSCLASS`)
4. VM-level (`SP_QOSCLASS`)
5. Per-disk configuration within VM (`SP_QOSCLASS` with disk ID specifiers)

The highest priority setting that applies to a specific disk will be used.
Note: for the persistent images when there is a Image-level QoS class set, the VM-level classification does not override it. Only the fine-grained per-disk configuration overrides them.

The folling table shows the priorities:

|   TYPE   | `DEFAULT_QOSCLASS` | IMAGE `SP_QOSCLASS` | IMAGE DS `SP_QOSCLASS` | SYSTEM DS `SP_QOSCLASS` | VM `SP_QOSCLASS` | VM DISK `SP_QOSCLASS` |
|   :---   |  :---:  | :---: |  :---:  |   :---:  | :---: |  :---:  |
|PERSISTANT|    <    |   <!  |    <?   |    <?    |   <?  |    <    |
|NON-PERS  |    <    |   -   |    -    |    <     |   <   |    <    |
|CDROM     |    <    |   -   |    -    |    <     |   <   |    <    |
|VOLATILE  |    <    |   -   |    -    |    <     |   <   |    <    |
|SAVE-AS   |    <    |   -   |    <    |    -     |   -   |    -    |
|DS_CLONE  |    <    |   <!  |    <?   |    -     |   -   |    -    |

Where:
| Label | Desctiption |
| :---: | :---        |
| '<' | tag available |
| '<!' | a "prioritized" tag |
| '<?' | tag overriden by a "prioritized" one |
| '-' | not applicable |

## Setting QoS Tags

**Note:** QoS tag names must not contain colon `:` or semicolon `;` as these are reserved symbols used for configuration parsing!


### Global QoS Class Tag (Lowest Priority)

Set in `/var/lib/one/remotes/addon-storpoolrc`:

```
DEFAULT_QOSCLASS=QoS_class_tag_name
```

This will be applied to all VM disks and images unless overridden by a higher priority setting.

### Datastore QoS Class Tag

Set in the datastore template:

```
SP_QOSCLASS=QoS_class_tag_name
```

This applies to all volumes in the specific datastore unless overridden.

### Image QoS Class Tag

For persistent images, add to the image template:

```
SP_QOSCLASS=QoS_class_tag_name
```

### VM-Level QoS Class Tag

Set in the VM template:

```
SP_QOSCLASS=QoS_class_tag_name
```

This applies to all[*] VM disks unless overridden by Persistent Image QoS tag or per-disk settings


### Per-Disk QoS Class Tag (Highest Priority)

This an extension to the VM-level QoS class tag.
For fine-grained control, use a semicolon-separated list in the VM template:

Format: `[default_qos];[disk_id]:[qos_name];[disk_id]:[qos_name]...`


```
SP_QOSCLASS=defaultVMQosTagName;2:QosTagNameForDiskId2;4:QosTagNameForDiskId4
```

In this example:
- Disks with ID 2 and 4 will use their specific QoS classes
- All other disks will use `defaultVMQosTagName` or `persistentImageQoSTagName` if the disk is a persistent image

If you only want to specify certain disks without a VM-wide default:

```
SP_QOSCLASS=0:QosTagNameForDiskId0;3:QosTagNameForDiskId3
```

In this case:
- Disks with ID 0 and 3 will use their specific QoS classes
- All other disks will fall back to image, datastore or global defaults

## How QoS Classes Are Applied

When a VM is created or modified, the addon determines the appropriate QoS class for the VM and its disks based on the priority order above and applies it as a tag to the StorPool volume. The QoS policies defined in StorPool are then automatically applied to the volumes by the `storpool_qos` service.

When a VM disk is saved as an Image to an Image Datastore it is Inheriting the SP_QOSCLAS defined for the datastore, or the global `DEFAULT_QOSCLASS` variable. (Note: when a `DEFAULT_QOSCLASS` is not defined, the driver could pick SP_QOSCLASS from the definition the Image used for the VM disk)

When a VM si terminated, the Persistent disk Images are tagged following the standard priority.

## Debugging

To troubleshoot QoS class assignment issues, check the OS logs(syslog or journal) for output from the `debug_sp_qosclass` function, which shows which QoS class was selected.

To enable debug logging set
DEBUG_SP_QOSCLASS=1 in `/var/lib/one/remotes/addon-storpoolrc`
