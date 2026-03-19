from enum import IntEnum


class DiskType(IntEnum):
    """OpenNebula disk types"""
    NONPERSISTENT = 0
    PERSISTENT = 1
    VOLATILE = 2
    CDROM = 3
    CONTEXT = 4
    NVRAM = 5
    CHECKPOINT = 6


class ImageType(IntEnum):
    """OpenNebula image types"""
    OS = 0
    CDROM = 1
    DATABLOCK = 2
    KERNEL = 3
    RAMDISK = 4
    CONTEXT = 5
