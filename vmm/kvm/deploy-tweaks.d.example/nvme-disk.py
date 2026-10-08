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

from typing import Dict, List, Optional, Tuple
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}

HEX = '0123456789abcdefABCDEF'


def indent(elem: ET.Element, level: int = 0, ind: str = "  ") -> None:
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
    print(f"Error in nvme-disk: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    text: Optional[str] = os.getenv(tag)
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is not None and element.text is not None:
        text = element.text
    if text is None:
        return None
    text = text.strip()
    if text == '':
        return None
    return text


def positive_int(tag: str, text: str) -> int:
    if not text.isdigit() or int(text) < 1:
        fatal(f"{tag} '{text}' is not a positive integer")
    return int(text)


def is_hex(text: str) -> bool:
    if text == '':
        return False
    for ch in text:
        if ch not in HEX:
            return False
    return True


def parse_device(tag: str, text: str, index: int) -> Tuple[str, str, str, str, str]:
    parts: List[str] = text.split(':')
    if len(parts) != 3:
        fatal(f"{tag} '{text}' is not a PCI address")
    tokens: List[str] = parts[2].split()
    if not tokens or tokens[0].count('.') != 1:
        fatal(f"{tag} '{text}' is not a PCI address")
    slot, func = tokens[0].split('.')
    if not (is_hex(parts[0]) and is_hex(parts[1]) and is_hex(slot) and is_hex(func)):
        fatal(f"{tag} '{text}' is not a PCI address")
    attrs: Dict[str, str] = {}
    for item in tokens[1:]:
        if '=' not in item:
            fatal(f"{tag} bad attribute '{item}'")
        key, value = item.split('=', 1)
        if key != 'namespace':
            fatal(f"{tag} unknown attribute '{key}'")
        attrs[key] = value
    if 'namespace' in attrs:
        namespace_text: str = attrs['namespace']
        if not namespace_text.isdigit() or int(namespace_text) < 1:
            fatal(f"{tag} namespace '{namespace_text}' is not an integer >= 1")
        namespace = str(int(namespace_text))
    elif index >= 1:
        namespace = str(index)
    else:
        fatal(f"{tag} namespace is missing")
    return parts[0], parts[1], slot, func, namespace


def target_dev(index: int) -> str:
    """Index 0..25 is vdzz..vdza; 26..31 continue as vdyz..vdyu."""
    group: int = index // 26
    pos: int = index % 26
    return 'vd' + chr(ord('z') - group) + chr(ord('z') - pos)


def add_disk(parent: ET.Element, index: int, domain: str, bus: str,
             slot: str, func: str, namespace: str) -> None:
    disk_e: ET.Element = ET.SubElement(parent, 'disk', {
        'type': 'nvme',
        'device': 'disk',
    })
    ET.SubElement(disk_e, 'driver', {
        'name': 'qemu',
        'type': 'raw',
    })
    source_e: ET.Element = ET.SubElement(disk_e, 'source', {
        'type': 'pci',
        'managed': 'yes',
        'namespace': namespace,
    })
    ET.SubElement(source_e, 'address', {
        'domain': '0x' + domain,
        'bus': '0x' + bus,
        'slot': '0x' + slot,
        'function': '0x' + func,
    })
    ET.SubElement(disk_e, 'target', {
        'dev': target_dev(index),
        'bus': 'virtio',
    })


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

disks: List[Tuple[int, str, str, str, str, str]] = []
for index in range(32):
    tag = f"T_NVME_DEVICE{index}"
    text: Optional[str] = template_text(tag)
    if text is None:
        continue
    domain, bus, slot, func, namespace = parse_device(tag, text, index)
    disks.append((index, domain, bus, slot, func, namespace))

controller: Optional[int] = None
controller_text: Optional[str] = template_text('T_NVME_CONTROLLER')
if controller_text is not None:
    controller = positive_int('T_NVME_CONTROLLER', controller_text)

if not disks and controller is None:
    sys.exit(0)

devices_list: List[ET.Element] = root.findall('./devices')
if not devices_list:
    fatal('missing devices')
devices_e: ET.Element = devices_list[0]

if controller is not None:
    for parent in devices_list:
        for child in list(parent):
            if child.tag == 'controller' and child.get('type') == 'nvme':
                parent.remove(child)
    for idx in range(controller):
        ET.SubElement(devices_e, 'controller', {
            'type': 'nvme',
            'index': str(idx),
        })

for index, domain, bus, slot, func, namespace in disks:
    add_disk(devices_e, index, domain, bus, slot, func, namespace)

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

indent(root)
doc.write(xmlDomain)
