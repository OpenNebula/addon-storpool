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

from typing import Dict, Optional
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}

UNIT_BYTES: Dict[str, int] = {
    'b': 1,
    'bytes': 1,
    'KB': 1000,
    'K': 1000,
    'k': 1000,
    'KiB': 1024,
    'MB': 1000 * 1000,
    'M': 1024 * 1024,
    'MiB': 1024 * 1024,
    'GB': 1000 * 1000 * 1000,
    'G': 1024 * 1024 * 1024,
    'GiB': 1024 * 1024 * 1024,
    'TB': 1000 * 1000 * 1000 * 1000,
    'T': 1024 * 1024 * 1024 * 1024,
    'TiB': 1024 * 1024 * 1024 * 1024,
}
MIB: int = 1024 * 1024


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
    print(f"Error in resizeCpuMem: {msg}", file=sys.stderr)
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


def mib_to_unit(tag: str, mib_text: str, unit: str) -> int:
    if not mib_text.isdigit():
        fatal(f"{tag} '{mib_text}' is not a non-negative integer")
    if unit not in UNIT_BYTES:
        fatal(f"unknown memory unit '{unit}'")
    total: int = int(mib_text) * MIB
    scale: int = UNIT_BYTES[unit]
    if total % scale != 0:
        fatal(f"{tag} is not a whole number of {unit}")
    return total // scale


def memory_bytes(elem: ET.Element) -> int:
    unit: str = elem.get('unit') or 'KiB'
    if unit not in UNIT_BYTES:
        fatal(f"unknown memory unit '{unit}'")
    if elem.text is None or not elem.text.strip().isdigit():
        fatal('memory value is not numeric')
    return int(elem.text.strip()) * UNIT_BYTES[unit]


xmlDomain: str = sys.argv[1]
doc_et: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc_et.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vcpu_max_text: Optional[str] = template_text('T_VCPU_MAX')
if vcpu_max_text is not None:
    if not vcpu_max_text.isdigit() or int(vcpu_max_text) < 1:
        fatal(f"T_VCPU_MAX '{vcpu_max_text}' is not a positive integer")
    vcpu_max: int = int(vcpu_max_text)
    vcpu_e: Optional[ET.Element] = root.find('./vcpu')
    if vcpu_e is None:
        vcpu_e = ET.SubElement(root, 'vcpu')
        current: int = vcpu_max
    elif vcpu_e.get('current') is not None:
        current = int(vcpu_e.get('current') or '0')
    elif vcpu_e.text is not None and vcpu_e.text.strip().isdigit():
        current = int(vcpu_e.text.strip())
    else:
        current = vcpu_max
    if vcpu_max < current:
        fatal('T_VCPU_MAX is below the current vcpu count')
    vcpu_e.text = str(vcpu_max)
    vcpu_e.set('current', str(current))
    for old in list(root.findall('vcpus')):
        root.remove(old)
    vcpus_e: ET.Element = ET.SubElement(root, 'vcpus')
    enabled: str = 'yes'
    hotpluggable: str = 'no'
    for i in range(vcpu_max):
        ET.SubElement(vcpus_e, 'vcpu', {
            'id': str(i),
            'enabled': enabled,
            'hotpluggable': hotpluggable,
        })
        hotpluggable = 'yes'
        if i == current - 1:
            enabled = 'no'
    changed = True

mem_max_text: Optional[str] = template_text('T_MEMORY_MAX')
maxmemory_text: Optional[str] = template_text('T_MAXMEMORY')
slots_text: Optional[str] = template_text('T_MAXMEMORY_SLOTS')
if (maxmemory_text is None) != (slots_text is None):
    fatal('T_MAXMEMORY and T_MAXMEMORY_SLOTS must be set together')

if mem_max_text is not None or maxmemory_text is not None:
    memory_e: Optional[ET.Element] = root.find('./memory')
    if memory_e is None:
        fatal('missing memory')
    unit: str = memory_e.get('unit') or 'KiB'
    if mem_max_text is not None:
        current_e: Optional[ET.Element] = root.find('./currentMemory')
        if current_e is None:
            current_e = ET.SubElement(root, 'currentMemory', {'unit': unit})
            current_e.text = memory_e.text
        new_max: int = mib_to_unit('T_MEMORY_MAX', mem_max_text, unit)
        memory_e.set('unit', unit)
        memory_e.text = str(new_max)
        if memory_bytes(current_e) > memory_bytes(memory_e):
            fatal('T_MEMORY_MAX is below currentMemory')
        changed = True
    if maxmemory_text is not None and slots_text is not None:
        if not slots_text.isdigit() or int(slots_text) < 1:
            fatal(f"T_MAXMEMORY_SLOTS '{slots_text}' is not a positive integer")
        size: int = mib_to_unit('T_MAXMEMORY', maxmemory_text, unit)
        if memory_e.text is None or not memory_e.text.strip().isdigit():
            fatal('memory value is not numeric')
        if size < int(memory_e.text.strip()):
            fatal('T_MAXMEMORY is below memory')
        for old_max in list(root.findall('maxMemory')):
            root.remove(old_max)
        max_e: ET.Element = ET.Element('maxMemory', {
            'slots': slots_text,
            'unit': unit,
        })
        max_e.text = str(size)
        memory_e_now: Optional[ET.Element] = root.find('./memory')
        insert_at: int = list(root).index(memory_e_now) if memory_e_now is not None else 0
        root.insert(insert_at, max_e)
        changed = True

if changed:
    indent(root)
    doc_et.write(xmlDomain)
