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

from __future__ import print_function
from typing import Optional
from sys import argv, stderr
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


xmlDomain: str = argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed: bool = False
for disk in root.findall('./devices/disk'):
    try:
        source_e: Optional[ET.Element] = disk.find('./source')
        if source_e is None:
            continue
        diskPath: str = ""
        if 'file' in source_e.attrib:
            diskPath = source_e.attrib['file']
        elif 'dev' in source_e.attrib:
            diskPath = source_e.attrib['dev']
        else:
            print(f"Unknown source attribute:{source_e.attrib}", file=stderr)
            continue
        diskId: int = int(diskPath.split('.')[-1])
        xpath: str = f"./TEMPLATE/DISK[DISK_ID='{diskId}']/TM_MAD"
        tm_mad_e: Optional[ET.Element] = vm.find(xpath)
        if tm_mad_e is None:
            xpath = f"./TEMPLATE/CONTEXT[DISK_ID='{diskId}']"
            contextDiskId_e: Optional[ET.Element] = vm.find(xpath)
            if contextDiskId_e is not None:
                # this is the context disk, get the tm_mad from the history
                xpath = './HISTORY_RECORDS/HISTORY[last()]/TM_MAD'
                tm_mad_e = vm.find(xpath)
        if tm_mad_e is not None:
            if (tm_mad_e.text is not None
                    and tm_mad_e.text.lower() == 'storpool'):
                driver_e: Optional[ET.Element] = disk.find('./driver')
                if driver_e is None:
                    continue
                driver_e.attrib['cache'] = 'none'
                driver_e.attrib['io'] = 'native'
                changed = True
    except Exception as e:
        print(f"Error: {e}", file=stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
