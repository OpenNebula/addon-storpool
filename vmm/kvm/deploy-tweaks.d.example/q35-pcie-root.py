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


def fatal(msg: str) -> None:
    print(f"Error in q35-pcie-root: {msg}", file=sys.stderr)
    sys.exit(2)


def is_pci(elem: ET.Element) -> bool:
    return elem.tag == 'controller' and elem.get('type') == 'pci'


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

ports_e: Optional[ET.Element] = vm.find('.//USER_TEMPLATE/T_Q35_PCIE_ROOT_PORTS')
if ports_e is None or ports_e.text is None or ports_e.text.strip() == '':
    sys.exit(0)

ports_text: str = ports_e.text.strip()
if not ports_text.isdigit():
    fatal(f"T_Q35_PCIE_ROOT_PORTS '{ports_text}' is not a non-negative integer")
ports: int = int(ports_text)

os_type: Optional[ET.Element] = root.find('./os/type')
machine: str = ''
if os_type is not None and os_type.get('machine') is not None:
    machine = os_type.get('machine') or ''
if 'q35' not in machine:
    fatal('T_Q35_PCIE_ROOT_PORTS requires machine type q35')

# OpenNebula 7.2 and later writes an index on each pcie-root-port (flat),
# and 7.0 and later does so for the NUMA expander topology. Rewriting those
# controllers drops the expander buses. Older domains have no root ports,
# or root ports with no index.
for controller in root.iter('controller'):
    if (controller.get('type') == 'pci'
            and controller.get('model') == 'pcie-root-port'
            and controller.get('index') is not None):
        sys.exit(0)

devices_list = root.findall('./devices')
if not devices_list:
    fatal('missing devices')

first: ET.Element = devices_list[0]
hole: Optional[ET.Element] = None
insert_after: Optional[ET.Element] = None
placed: bool = False

for devices in devices_list:
    for child in list(devices):
        if not is_pci(child):
            if devices is first and not placed:
                insert_after = child
            continue
        if hole is None and child.get('model') == 'pcie-root':
            found: Optional[ET.Element] = child.find('pcihole64')
            if found is not None:
                child.remove(found)
                hole = found
        devices.remove(child)
        if devices is first:
            placed = True

for devices in devices_list[1:]:
    if len(devices) == 0:
        root.remove(devices)

if insert_after is None:
    insert_at: int = 0
else:
    insert_at = list(first).index(insert_after) + 1

root_e: ET.Element = ET.Element('controller', {
    'type': 'pci',
    'index': '0',
    'model': 'pcie-root',
})
if hole is not None:
    root_e.append(hole)
first.insert(insert_at, root_e)
insert_at += 1

for idx in range(1, ports + 1):
    port_e: ET.Element = ET.Element('controller', {
        'type': 'pci',
        'index': str(idx),
        'model': 'pcie-root-port',
    })
    first.insert(insert_at, port_e)
    insert_at += 1

bridge_e: ET.Element = ET.Element('controller', {
    'type': 'pci',
    'index': str(ports + 1),
    'model': 'pcie-to-pci-bridge',
})
first.insert(insert_at, bridge_e)

indent(root)
doc.write(xmlDomain)
