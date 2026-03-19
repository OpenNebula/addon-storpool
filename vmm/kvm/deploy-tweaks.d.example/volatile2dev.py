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
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
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
vm_element: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed: bool = False
for disk in root.findall('./devices/disk[@type="file"]'):
    try:
        source = disk.find('./source')
        if source is None:
            continue
        file_path: str = source.attrib['file']
        disk_id: str = file_path.split('.')[-1]
        xpath: str = f"./TEMPLATE/DISK[DISK_ID='{disk_id}']/TM_MAD"
        tm_mad: Optional[ET.Element] = vm.find(xpath)
        xpath = "./TEMPLATE/CONTEXT/DISK_ID"
        context_disk_id: Optional[ET.Element] = vm.find(xpath)
        if tm_mad is not None and tm_mad.text is not None:
            if tm_mad.text.lower() == 'storpool':
                source.attrib['dev'] = file_path
                del source.attrib['file']
                disk.attrib['type'] = 'block'
                changed = True
        elif context_disk_id is not None and context_disk_id.text is not None:
            if context_disk_id.text == disk_id:
                xpath = './/HISTORY[last()]/TM_MAD'
                context_tm_mad: Optional[ET.Element] = vm.find(xpath)
                if (context_tm_mad is not None and
                        context_tm_mad.text is not None):
                    if context_tm_mad.text.lower() == 'storpool':
                        source.attrib['dev'] = file_path
                        del source.attrib['file']
                        disk.attrib['type'] = 'block'
                        changed = True
        else:
            print(f"Can't get TM_MAD for disk '{file_path}'", file=sys.stderr)
    except Exception as err:
        print(f"Error: {err}", file=sys.stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
