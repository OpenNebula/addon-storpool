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
import os
from xml.etree import ElementTree as ET
from hashlib import md5

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
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

t_diskserial_env: str = os.getenv('T_DISKSERIAL', "DISABLED")  # type: ignore[attr-defined] # noqa: E501
t_diskserial: str = t_diskserial_env.upper()
xpath: str = './/USER_TEMPLATE/T_DISKSERIAL'
t_diskserial_e: Optional[ET.Element] = vm.find(xpath)
if (t_diskserial_e is not None and
        t_diskserial_e.text is not None):
    t_diskserial = t_diskserial_e.text.upper()
if t_diskserial == "DISABLED":
    print("Option T_DISKSERIAL is disabled, exit 0.", file=sys.stderr)
    sys.exit(0)

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed: bool = False
for disk in root.findall('./devices/disk'):
    try:
        if 'device' in disk.attrib:
            if disk.attrib["device"] != "disk":
                continue
        source_e: Optional[ET.Element] = disk.find('./source')
        if source_e is None:
            continue
        diskPath: str = ""
        if 'file' in source_e.attrib:
            diskPath = source_e.attrib['file']
        elif 'dev' in source_e.attrib:
            diskPath = source_e.attrib['dev']
        else:
            print("source element has no file/dev attribute"
                  f":{source_e.attrib}",
                  file=sys.stderr)
            continue
        hashtxt: str = diskPath
        if t_diskserial != "HASHPATH":
            diskId = diskPath.split('.')[-1]
            xpath = f"./TEMPLATE/DISK[DISK_ID='{diskId}']/CLONE"
            image_clone_e: Optional[ET.Element] = vm.find(xpath)
            if image_clone_e is None:
                # volatile image
                hashtxt = f"volatile-{diskId}"
            else:
                if (image_clone_e.text is not None
                        and image_clone_e.text.upper() == "YES"):
                    vm_id_e: Optional[ET.Element] = vm.find('./ID')
                    if vm_id_e is not None:
                        hashtxt = f"{vm_id_e.text}-{diskId}"
                else:
                    xpath = f"./TEMPLATE/DISK[DISK_ID='{diskId}']/IMAGE_ID"
                    image_id_e: Optional[ET.Element] = vm.find(xpath)
                    if image_id_e is not None:
                        hashtxt = f"persistent-{image_id_e.text}"
        serial_e: Optional[ET.Element] = disk.find('./serial')
        if serial_e is None:
            serial_e = ET.SubElement(disk, 'serial')
        serial_e.text = md5(hashtxt.encode()).hexdigest()[0:20]
        changed = True
    except Exception as err:
        print(f"Error: {err}", file=sys.stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
