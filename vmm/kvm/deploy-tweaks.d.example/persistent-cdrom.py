#!/usr/bin/env python3
"""
# -------------------------------------------------------------------------- #
# Copyright 2015-2025, StorPool (storpool.com)                               #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# Global env:
# T_PERSISTENT_CDROM=4
# T_PERSISTENT_CDROM_TYPE="block"
# # The IDE devices are limited to 4 (shared with IDE hard disks)
# # MAX_CDROM_DEVICES=4
# VM Attribute:
# .//USER_TEMPLATE/T_PERSISTENT_CDROM = 4
# .//USER_TEMPLATE/T_PERSISTENT_CDROM_TYPE = block
"""

from typing import Any, Optional, List, Dict, Tuple
import os
import sys
from xml.etree import ElementTree as ET
import syslog

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}


def indent(elem, level=0, ind="  "):
    i = "\n" + level * ind
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + ind
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level+1, ind)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if not level:
            return
        if not elem.text or not elem.text.strip():
            elem.text = None
        if not elem.tail or not elem.tail.strip():
            elem.tail = i


def log_inf(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_INFO, "[I]vmm_sp_deploy: " + logmsg)
    else:
        print("[I]" + logmsg, file=sys.stderr)


def log_err(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_ERR, "[E]vmm_sp_deploy: " + logmsg)
    print("[E]" + logmsg, file=sys.stderr)


def log_dbg(logmsg):
    if test_env is None:
        syslog.syslog(syslog.LOG_DEBUG, "[D]vmm_sp_deploy: " + logmsg)
    else:
        print("[D]" + logmsg, file=sys.stderr)


def sata_persistent_slot(index: int) -> str:
    return "sdz" + chr(122 - index)


def is_persistent_sata_slot(dev: str) -> bool:
    return (
        dev.startswith("sdz")
        and len(dev) == 4
        and 'w' <= dev[3] <= 'z'
    )


def cdrom_has_source(disk_e: ET.Element) -> bool:
    source_e = disk_e.find('./source')
    if source_e is None:
        return False
    for attr in ('dev', 'file'):
        val = source_e.get(attr)
        if val:
            return True
    return False


def get_free_ide_device(used_devices: List[str]) -> Optional[str]:
    for i in range(max_cdrom_devices):
        dev = "hd" + chr(97 + i)
        if dev in used_devices:
            continue
        used_devices.append(dev)
        log_dbg(f"get_free_ide_device({used_devices=}) = {dev} // {i=}")
        return dev
    return None


def get_free_sata_device(used_devices: List[str]) -> Optional[str]:
    for i in range(max_cdrom_devices):
        dev = sata_persistent_slot(i)
        if dev in used_devices:
            continue
        used_devices.append(dev)
        log_dbg(f"get_free_sata_device({used_devices=}) = {dev} // {i=}")
        return dev
    return None


def add_cdrom(
    devices_e: ET.Element,
    cdrom_bus: str,
    disk_cdrom_type: str,
    dev: str,
) -> bool:
    log_dbg(f"add_cdrom({cdrom_bus=}, {disk_cdrom_type=}, {dev=})")
    disk_e = ET.SubElement(
        devices_e,
        'disk',
        {
            "type": disk_cdrom_type,
            "device": "cdrom",
        },
    )
    _ = ET.SubElement(  # type: ignore[attr-defined] # noqa: E501
        disk_e,
        "target",
        {
            "dev": dev,
            "bus": cdrom_bus,
        },
    )
    _ = ET.SubElement(  # type: ignore[attr-defined] # noqa: E501
        disk_e,
        "driver",
        {
            "name": "qemu",
            "type": "raw",
            "cache": "none",
            "io": "native",
        },
    )
    _ = ET.SubElement(disk_e, "readonly", {})  # type: ignore[attr-defined] # noqa: E501
    log_inf(f"added CDROM device: {dev}"
            f" type:{disk_cdrom_type} bus:{cdrom_bus}")
    return True


def change_cdrom(
    disk_e: ET.Element,
    cdrom_bus: str,
    disk_cdrom_type: str,
    dev: str,
) -> bool:
    changed: bool = False
    msg: str = ""
    type_e = disk_e.get('type')
    if type_e is not None and type_e != disk_cdrom_type:
        disk_e.set('type', disk_cdrom_type)
        msg += f" type:{type_e} -> {disk_cdrom_type}"
        changed = True
    target_e = disk_e.find('./target')
    if target_e is not None:
        target_bus = target_e.get('bus')
        if target_bus is not None and target_bus != cdrom_bus:
            target_e.set('bus', cdrom_bus)
            msg += f" bus:{target_bus} -> {cdrom_bus}"
            changed = True
        target_dev = target_e.get('dev')
        if target_dev is not None and target_dev != dev:
            target_e.set('dev', dev)
            msg += f" dev:{target_dev} -> {dev}"
            changed = True
            address_e = disk_e.find('./address')
            if address_e is not None:
                disk_e.remove(address_e)
                msg += " removed address"
    if msg:
        log_inf(f"change_cdrom(){msg}")
    return changed


def collect_cdroms(
    root: ET.Element,
) -> Tuple[List[Dict[str, Any]], List[str], List[str], int]:
    all_cdroms: List[Dict[str, Any]] = []
    used_hd_devices: List[str] = []
    used_sd_devices: List[str] = []
    ide_disks_count: int = 0

    for disk_e in root.findall('.//devices/disk'):
        target_e = disk_e.find('./target')
        if target_e is None:
            continue

        target_dev = target_e.get('dev')
        if target_dev is None:
            continue

        target_prefix = target_dev[0:2]
        target_bus = target_e.get('bus')
        is_ide_slot = target_prefix == 'hd' or target_bus == 'ide'

        if disk_e.get('device') != 'cdrom':
            # IDE hard disks share the same 4 IDE slots as CDROMs.
            if is_ide_slot:
                if target_dev not in used_hd_devices:
                    used_hd_devices.append(target_dev)
                ide_disks_count += 1
                log_dbg(f"IDE disk occupies slot {target_dev}"
                        f" bus={target_bus}")
            continue

        info: Dict[str, Any] = {"element": disk_e}
        info["target_dev"] = target_dev
        info["target_prefix"] = target_prefix
        if target_prefix == 'hd':
            if target_dev not in used_hd_devices:
                used_hd_devices.append(target_dev)
        elif target_prefix == 'sd':
            used_sd_devices.append(target_dev)

        if target_bus is not None:
            info["target_bus"] = target_bus

        info["has_source"] = cdrom_has_source(disk_e)
        if info["has_source"]:
            disk_type = disk_e.get('type')
            if disk_type == 'block':
                source_entry = "dev"
            elif disk_type == 'file':
                source_entry = "file"
            else:
                source_entry = None
            source_e = disk_e.find('./source')
            if source_e is not None and source_entry is not None:
                source = source_e.get(source_entry)
                if source is not None and 'disk.' in source:
                    info["disk_id"] = int(source.rsplit('disk.')[1])

        all_cdroms.append(info)

    return all_cdroms, used_hd_devices, used_sd_devices, ide_disks_count


test_env = os.getenv('TEST_ENV', None)  # type: ignore[attr-defined]
# The pc type has 1 IDE controller so 4 devices max
max_cdrom_devices = int(os.getenv('MAX_CDROM_DEVICES', '4'))  # type: ignore[attr-defined] # noqa: E501
xmlDomain = sys.argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = sys.argv[2]
vm_e = ET.parse(xmlVm)
vm_root = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed: bool = False

context_disk_id: Optional[int] = None
context_disk_id_e: Optional[ET.Element] = vm_root.find(
    './/TEMPLATE/CONTEXT/DISK_ID',  # type: ignore[attr-defined] # noqa: E501
)
if context_disk_id_e is not None:
    context_disk_id = int(context_disk_id_e.text)

all_cdroms, used_hd_devices, used_sd_devices, ide_disks_count = \
    collect_cdroms(root)
total_cdroms_count = len(all_cdroms)

cdrom_bus: str = 'ide'
os_type_e: Optional[ET.Element] = root.find('./os/type')
if os_type_e is not None:
    machine: Optional[str] = os_type_e.get('machine')
    if machine is not None:
        if 'q35' in machine:
            cdrom_bus = 'sata'
        log_inf(f"{machine=} {cdrom_bus=}")

# find first devices element. Will add the new cdrom devices to this element.
devices_e: ET.Element = root.findall('.//devices')[0]

pers_cdroms_count: int = 0
pers_cdroms_count_env: str = os.getenv('T_PERSISTENT_CDROM', '0')  # type: ignore[attr-defined] # noqa: E501
if pers_cdroms_count_env.isnumeric():
    pers_cdroms_count = int(pers_cdroms_count_env)
t_pers_cdrom_e: Optional[ET.Element] = vm_root.find(
    './/USER_TEMPLATE/T_PERSISTENT_CDROM')
if t_pers_cdrom_e is not None:
    if t_pers_cdrom_e.text is not None and t_pers_cdrom_e.text.isnumeric():
        log_dbg(f"{t_pers_cdrom_e.text=} USER_TEMPLATE")
        pers_cdroms_count = int(t_pers_cdrom_e.text)

disk_cdrom_type: str = "block"
pers_cdroms_type_env: str = os.getenv('T_PERSISTENT_CDROM_TYPE', 'block')  # type: ignore[attr-defined] # noqa: E501
if pers_cdroms_type_env.lower() in ['file', 'block']:
    disk_cdrom_type = pers_cdroms_type_env.lower()
t_pers_cdrom_type_e: Optional[ET.Element] = vm_root.find(
    './/USER_TEMPLATE/T_PERSISTENT_CDROM_TYPE'
)
if t_pers_cdrom_type_e is not None:
    if (t_pers_cdrom_type_e.text is not None and
            t_pers_cdrom_type_e.text.lower() in ['file', 'block']):
        disk_cdrom_type = t_pers_cdrom_type_e.text.lower()

if pers_cdroms_count > 0:
    target_count = pers_cdroms_count
    if target_count > max_cdrom_devices:
        log_inf(f"persistent cdroms count {target_count} >"
                f" {max_cdrom_devices}! Setting {max_cdrom_devices} devices.")
        target_count = max_cdrom_devices

    log_dbg(f"{cdrom_bus=} {target_count=} {total_cdroms_count=}"
            f" {used_hd_devices=} {used_sd_devices=}")

    if cdrom_bus == 'ide':
        # IDE controller has only 4 slots shared with hard disks.
        available_ide_slots = max_cdrom_devices - ide_disks_count
        if available_ide_slots < 0:
            available_ide_slots = 0
        if target_count > available_ide_slots:
            log_inf(f"persistent cdroms count {target_count} reduced to"
                    f" {available_ide_slots} due to {ide_disks_count}"
                    f" IDE disk(s)")
            target_count = available_ide_slots

        if total_cdroms_count >= target_count:
            msg = (f"already have {total_cdroms_count} cdrom devices"
                   f" (target {target_count}). nothing to do")
            print(msg, file=sys.stderr)
            log_inf(msg)
            exit(0)

        while total_cdroms_count < target_count:
            dev = get_free_ide_device(used_hd_devices)
            if dev is None:
                log_inf(f"no free IDE CDROM slot left at {total_cdroms_count}"
                        f"/{target_count}")
                break
            if add_cdrom(devices_e, cdrom_bus, disk_cdrom_type, dev):
                changed = True
                total_cdroms_count += 1

    elif cdrom_bus == 'sata':
        for cdrom in all_cdroms:
            if not cdrom.get("has_source"):
                log_dbg(f"Skipping CDROM without source"
                        f" '{cdrom['target_dev']}'")
                continue
            disk_id = cdrom.get("disk_id")
            if disk_id is not None and disk_id == context_disk_id:
                log_dbg(f"Skipping CONTEXTUALIZATION CDROM"
                        f" {cdrom['target_dev']} {disk_id=}"
                        f" {context_disk_id=}")
                continue
            if is_persistent_sata_slot(cdrom["target_dev"]):
                log_dbg(f"Skipping PERSISTENT SATA CDROM"
                        f" {cdrom['target_dev']} {disk_id=}")
                continue
            log_dbg(f"{disk_id=} {context_disk_id=} {used_sd_devices=}")
            dev = get_free_sata_device(used_sd_devices)
            if dev is not None:
                if change_cdrom(
                    cdrom['element'],
                    cdrom_bus,
                    disk_cdrom_type,
                    dev,
                ):
                    changed = True
                    cdrom["target_dev"] = dev
            else:
                log_dbg(f"Failed to change CDROM"
                        f" {cdrom['target_dev']} {disk_id=}")
        log_dbg(f"Adding remaining {target_count - total_cdroms_count}"
                f" cdrom devices to {target_count}")
        while total_cdroms_count < target_count:
            dev = get_free_sata_device(used_sd_devices)
            if dev is None:
                log_inf(f"no free SATA CDROM slot left at {total_cdroms_count}"
                        f"/{target_count}")
                break
            if add_cdrom(devices_e, cdrom_bus, disk_cdrom_type, dev):
                changed = True
                total_cdroms_count += 1


if changed:
    indent(root)
    doc.write(xmlDomain)
