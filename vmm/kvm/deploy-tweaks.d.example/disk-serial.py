#!/usr/bin/env python3

# -------------------------------------------------------------------------- #
# Copyright 2015-2024, StorPool (storpool.com)                               #
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

from __future__ import print_function
from xml.etree import ElementTree as ET
from hashlib import md5
import sys
import os

ns = {'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
       'one': "http://opennebula.org/xmlns/libvirt/1.0"
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


xmlDomain = sys.argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = sys.argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

t_diskserial = os.getenv('T_DISKSERIAL', "DISABLED").upper()
t_diskserial_e = vm.find('.//USER_TEMPLATE/T_DISKSERIAL')
if t_diskserial_e is not None:
    t_diskserial = t_diskserial_e.text.upper()
if t_diskserial == "DISABLED":
    print("Disabled, exit 0.", file=sys.stderr)
    sys.exit(0)

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed = 0
for disk in root.findall('./devices/disk'):
    try:
        if 'device' in disk.attrib:
            if disk.attrib["device"] != "disk":
                continue
        source = disk.find('./source')
        if 'file' in source.attrib:
            diskPath = source.attrib['file']
        elif 'dev' in source.attrib:
            diskPath = source.attrib['dev']
        else:
            print("Unknown source attribute:{a}".format(a=source.attrib),
                  file=sys.stderr)
            continue
        hashtxt = diskPath
        if t_diskserial != "HASHPATH":
            diskId = diskPath.split('.')[-1]
            image_clone_e = vm.find(
                './TEMPLATE/DISK[DISK_ID="{i}"]/CLONE'.format(i=diskId)
            )
            if image_clone_e is None:
                # volatile image
                hashtxt = f"volatile-{diskId}"
            else:
                if image_clone_e.text.upper() == "YES":
                    vm_id_e = vm.find('./ID')
                    hashtxt = f"{vm_id_e.text}-{diskId}"
                else:
                    image_id_e = vm.find(
                        './TEMPLATE/DISK[DISK_ID="{i}"]/IMAGE_ID'.format(
                            i=diskId)
                    )
                    hashtxt = f"persistent-{image_id_e.text}"
        serial = disk.find('./serial')
        if serial is None:
            serial = ET.SubElement(disk, 'serial')
        serial.text = md5(hashtxt.encode()).hexdigest()[0:20]
        changed = 1
    except Exception as e:
        print("Error: {e}".format(e=e), file=sys.stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
