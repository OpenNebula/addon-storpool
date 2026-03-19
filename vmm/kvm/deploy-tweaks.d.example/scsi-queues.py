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
"""

from typing import Optional, List
import sys
import os
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
    i: str = "\n" + level * ind
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


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vcpu: int = 1
vcpu_e: Optional[ET.Element] = root.find('./vcpu')
if vcpu_e is not None and vcpu_e.text is not None:
    vcpu = int(vcpu_e.text)
else:
    vcpu = 1
    vcpu_e = ET.SubElement(root, 'vcpu')
    vcpu_e.text = '1'


controllers: List[ET.Element] = root.findall(
    "./devices/controller[@type='scsi']")
if len(controllers) == 0:
    devices_e: Optional[ET.Element] = root.find('./devices')
    if devices_e is None:
        raise ValueError("No devices found")
    scsi: ET.Element = ET.SubElement(devices_e, 'controller', {
            'type': 'scsi',
            'model': 'virtio-scsi'
        })
    controllers = [scsi]

driver_e: Optional[ET.Element] = None
for scsi in controllers:
    driver_e = scsi.find('./driver')
    if driver_e is None:
        driver_e = ET.SubElement(scsi, 'driver')
    driver_e.attrib['queues'] = str(vcpu)

# virtio-blk
blk_queues: str = os.getenv('T_BLK_QUEUES', 'NO')  # type: ignore[attr-defined]
xpath: str = './/USER_TEMPLATE/T_BLK_QUEUES'
t_blk_queues_e: Optional[ET.Element] = vm.find(xpath)
if t_blk_queues_e is not None and t_blk_queues_e.text is not None:
    blk_queues = t_blk_queues_e.text
if blk_queues.upper() in ['1', 'YES', 'Y']:
    for disk_e in root.findall('./devices/disk'):
        target_e: Optional[ET.Element] = disk_e.find('./target')
        if target_e is None or target_e.attrib['dev'][:2] != 'vd':
            continue
        driver_e = disk_e.find('./driver')
        if driver_e is None:
            driver_e = ET.SubElement(disk_e, 'driver')
        driver_e.attrib['queues'] = str(vcpu)

indent(root)
doc.write(xmlDomain)
