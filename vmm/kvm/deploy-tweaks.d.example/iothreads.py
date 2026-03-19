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
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
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


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

t_iothreads_e: Optional[ET.Element] = vm.find('.//T_IOTHREADS_OVERRIDE')
if t_iothreads_e is not None:
    if t_iothreads_e.text == '0':
        print('T_IOTHREADS_OVERRIDE=0, Bail out!', file=sys.stderr)
        sys.exit(1)
iothreads_e: Optional[ET.Element] = root.find('./iothreads')
if iothreads_e is None:
    iothreads_e = ET.SubElement(root, 'iothreads')
else:
    if t_iothreads_e is None:
        print(f"Found iothreads={iothreads_e.text}"
              f", but T_IOTHREADS_OVERRIDE is not set", file=sys.stderr)
        sys.exit(1)

iothreads_e.text = "1"

driver_e: Optional[ET.Element] = None
target_e: Optional[ET.Element] = None
device_e: Optional[ET.Element] = None
scsi_e: Optional[ET.Element] = None

# virtio-blk
for disk in root.findall('./devices/disk'):
    target_e = disk.find('./target')
    if target_e is None or target_e.attrib['dev'][:2] != 'vd':
        continue
    driver_e = disk.find('./driver')
    if driver_e is None:
        driver_e = ET.SubElement(disk, 'driver')
    driver_e.attrib['io'] = 'native'
    driver_e.attrib['iothread'] = '1'

# virtio-scsi
controllers: List[ET.Element] = root.findall(
    "./devices/controller[@type='scsi']")
if not controllers:
    device_e = root.find('./devices')
    if device_e is None:
        raise RuntimeError("Can't find devices element")
    scsi_e = ET.SubElement(device_e, 'controller', {
            'type': 'scsi',
            'model': 'virtio-scsi'
        })
    controllers = [scsi_e]

for scsi in controllers:
    driver_e = scsi.find('./driver')
    if driver_e is None:
        driver_e = ET.SubElement(scsi, 'driver')
    driver_e.attrib['iothread'] = '1'

indent(root)
doc.write(xmlDomain)
