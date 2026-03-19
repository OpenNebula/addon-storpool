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

from typing import Optional
import sys
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


changed: bool = False

xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

xpath: str = './USER_TEMPLATE/Q35_PCIE_ROOT_PORTS'
t_q35_ports_e: Optional[ET.Element] = vm.find(xpath)
if t_q35_ports_e is not None and t_q35_ports_e.text is not None:
    q35_ports: int = int(t_q35_ports_e.text)
    os_type: Optional[ET.Element] = root.find('./os/type')
    if os_type is not None and os_type.attrib['machine'] is not None:
        if 'q35' in os_type.attrib['machine']:
            new_device_e: ET.Element = ET.SubElement(root, 'devices', {})

            ET.SubElement(new_device_e, 'controller', {
                    'type': 'pci',
                    'model': 'pcie-root'
                })
            for i in range(0, q35_ports):
                ET.SubElement(new_device_e, 'controller', {
                        'type': 'pci',
                        'model': 'pcie-root-port'
                    })
            ET.SubElement(new_device_e, 'controller', {
                'type': 'pci',
                'model': 'pcie-to-pci-bridge'
            })
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
