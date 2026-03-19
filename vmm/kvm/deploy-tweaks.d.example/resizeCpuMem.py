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

from typing import Optional, Dict
import os
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


xmlDomain: str = sys.argv[1]
doc_et: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc_et.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vcpu: int = 1
vcpu_e: Optional[ET.Element] = root.find('./vcpu')
if vcpu_e is None:
    vcpu_e = ET.SubElement(root, 'vcpu')
    vcpu_e.attrib['placement'] = 'static'
    vcpu_e.text = '1'
elif vcpu_e.text is not None:
    vcpu = int(vcpu_e.text)

vcpu_max: int = int(os.getenv('T_VCPU_MAX', vcpu))  # type: ignore[attr-defined] # noqa: E501
xpath: str = './/USER_TEMPLATE/T_VCPU_MAX'
vcpu_max_e: Optional[ET.Element] = vm.find(xpath)
if vcpu_max_e is not None and vcpu_max_e.text is not None:
    try:
        vcpu_max = int(vcpu_max_e.text)
        if vcpu_max < 1:
            vcpu_max = 1
    except Exception as e:
        print("USER_TEMPLATE/T_VCPU_MAX is '{0}' Error:{1}".format(
              vcpu_max_e.text, e), file=sys.stderr)
        sys.exit(1)

vcpu_current_attr: Optional[str] = vcpu_e.get('current')

if vcpu_current_attr is not None:
    print('VCPU already configured to "{0}" of "{1}" VCPUs'.format(
          vcpu_current_attr, vcpu), file=sys.stderr)
else:
    vcpu_current: int = vcpu
    vcpu_e.text = str(vcpu_max)
    vcpu_e.attrib['current'] = str(vcpu_current)
    vcpus_e: ET.Element = ET.SubElement(root, 'vcpus')
    hotpluggable: str = 'no'
    enabled: str = 'yes'
    for i in range(vcpu_max):
        vcpus_ex: ET.Element = ET.SubElement(vcpus_e, 'vcpu', {
                'id': str(i),
                'enabled': enabled,
                'hotpluggable': hotpluggable,
            })
        hotpluggable = "yes"
        if i == vcpu_current-1:
            enabled = 'no'
    changed = True

memUnits: Dict[str, int] = {
    'KiB': 1024,
    'MiB': 1024*1024,
    'GiB': 1024*1024*1024,
    'TiB': 1024*1024*1024*1024,
    }

memory: int = 0
memory_unit: str = 'KiB'
memory_e: Optional[ET.Element] = root.find('./memory')
if memory_e is not None:
    if memory_e.text is not None:
        memory = int(memory_e.text)
        memory_unit = memory_e.get('unit') or 'KiB'
    else:
        memory_unit = 'KiB'
    memory_e.attrib['unit'] = memory_unit

    current_mem_e: Optional[ET.Element] = root.find('./currentMemory')
    if current_mem_e is None:
        current_mem_e = ET.SubElement(root, 'currentMemory', {
            'unit': memory_unit,
        })
        current_mem_e.text = str(memory)
        t_mem_max_e: Optional[ET.Element] = vm.find(
            './/USER_TEMPLATE/T_MEMORY_MAX')
        if t_mem_max_e is not None and t_mem_max_e.text is not None:
            t_mem_max: int = int(t_mem_max_e.text) * memUnits[memory_unit]
            if t_mem_max > memory:
                memory_e.text = str(t_mem_max)
        changed = True
    else:
        print(f"CurrentMemory already configured to '{current_mem_e.text}'",
              file=sys.stderr)

if changed:
    indent(root)
    doc_et.write(xmlDomain)
