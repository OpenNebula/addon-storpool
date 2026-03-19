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
# # The IDE devices are limited to 4
# # MAX_CDROM_DEVICES=4
# VM Attribute:
# .//USER_TEMPLATE/T_PERSISTENT_CDROM = 4
# .//USER_TEMPLATE/T_PERSISTENT_CDROM_TYPE = block
"""

from typing import Any, Optional, List, Dict
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
msg: str = ""
target_e: Optional[ET.Element] = None
disk_e: Optional[ET.Element] = None
source_e: Optional[ET.Element] = None
readonly_e: Optional[ET.Element] = None
driver_e: Optional[ET.Element] = None

used_ide_devices: List[str] = []
dom_cdroms: Dict[str, Any] = {}
xpath: str = './/devices/disk[@device="cdrom"]'
cdrom_elements: List[ET.Element] = root.findall(xpath)
for cdrom_e in cdrom_elements:
    info: Dict[str, Any] = {"element": cdrom_e}
    target_e = cdrom_e.find('./target')
    if target_e is not None:
        target_dev: Optional[str] = target_e.get('dev')
        if target_dev is not None:
            info["target_dev"] = target_dev
            if target_dev[0:2] == 'hd':
                used_ide_devices.append(info["target_dev"])
        target_bus: Optional[str] = target_e.get('bus')
        if target_bus is not None:
            info["target_bus"] = target_bus
    if cdrom_e.get('type') == 'block':
        info["source_entry"] = "dev"
    source_e = cdrom_e.find('./source')
    if source_e is not None:
        info["source_entry"] = "file"
        info["source"] = source_e.get(info["source_entry"])
        if info["source"] is not None:
            info["disk_id"] = int(info["source"].rsplit('disk.')[1])
            dom_cdroms[info["disk_id"]] = info

dom_cdroms_count = len(dom_cdroms)

cdrom_bus: str = 'ide'
os_type_e: Optional[ET.Element] = root.find('./os/type')
if os_type_e is not None:
    machine: Optional[str] = os_type_e.get('machine')
    if machine is not None:
        if 'q35' in machine:
            cdrom_bus = 'sata'

# find first devices element
devices_e: ET.Element = root.findall('.//devices')[0]

pers_cdroms_count: int = 0
pers_cdroms_count_env: str = os.getenv('T_PERSISTENT_CDROM', '0')  # type: ignore[attr-defined] # noqa: E501
if pers_cdroms_count_env.isnumeric():
    pers_cdroms_count = int(pers_cdroms_count_env)
t_pers_cdrom_e: Optional[ET.Element] = vm_root.find(
    './/USER_TEMPLATE/T_PERSISTENT_CDROM')
if t_pers_cdrom_e is not None:
    if t_pers_cdrom_e.text is not None and t_pers_cdrom_e.text.isnumeric():
        pers_cdroms_count = int(t_pers_cdrom_e.text)

disk_cdrom_type: str = "block"
pers_cdroms_type_env: str = os.getenv('T_PERSISTENT_CDROM_TYPE', 'block')  # type: ignore[attr-defined] # noqa: E501
if pers_cdroms_type_env.lower() in ['file', 'block']:
    pers_cdroms_type = pers_cdroms_type_env.lower()
t_pers_cdrom_type_e: Optional[ET.Element] = vm_root.find(
    './/USER_TEMPLATE/T_PERSISTENT_CDROM_TYPE'
)
if t_pers_cdrom_type_e is not None:
    if (t_pers_cdrom_type_e.text is not None and
            t_pers_cdrom_type_e.text.lower() in ['file', 'block']):
        disk_cdrom_type = t_pers_cdrom_type_e.text.lower()

pers_cdroms: List[ET.Element] = []

if pers_cdroms_count > 0:
    if pers_cdroms_count > max_cdrom_devices:
        log_inf(f"persistent cdroms count {pers_cdroms_count} >"
                f" {max_cdrom_devices}! Setting {max_cdrom_devices} devices.")
        pers_cdroms_count = max_cdrom_devices

    if dom_cdroms_count > max_cdrom_devices - 1:
        msg = f"already have {dom_cdroms_count} >0. nothing to do"
        print(msg, file=sys.stderr)
        log_inf(msg)
        exit(0)

    cdroms_count: int = max_cdrom_devices - dom_cdroms_count
    if cdroms_count < 1:
        msg = f"{cdroms_count} < 1. nothing to do"
        print(msg, file=sys.stderr)
        log_inf(msg)
        exit(0)

    if cdroms_count > pers_cdroms_count:
        cdroms_count = pers_cdroms_count

    for idx in range(cdroms_count):
        # get free target_dev
        dev = None
        for i in range(max_cdrom_devices):
            dev = "hd" + chr(97 + i)
            if dev in used_ide_devices:
                dev = None
                continue
            used_ide_devices.append(dev)
            break
        if dev is not None:
            disk_e = ET.SubElement(
                    devices_e,
                    'disk',
                    {
                        "type": disk_cdrom_type,
                        "device": "cdrom",
                    },
            )
            target_e = ET.SubElement(
                disk_e,
                "target",
                {
                    "dev": dev,
                    "bus": cdrom_bus,
                },
            )
            driver_e = ET.SubElement(
                disk_e,
                "driver",
                {
                    "name": "qemu",
                    "type": "raw",
                    "cache": "none",
                    "io": "native",
                },
            )
            readonly_e = ET.SubElement(disk_e, "readonly", {})
            changed = True
            log_inf(f"added cdrom device: {dev}"
                    f" type:{disk_cdrom_type} bus:{cdrom_bus}")

if changed:
    indent(root)
    doc.write(xmlDomain)
