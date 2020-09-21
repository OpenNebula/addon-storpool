#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2020, StorPool (storpool.com)                               #
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

from sys import argv
from xml.etree import ElementTree as ET

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

xmlDomain = argv[1]

doc = ET.parse(xmlDomain)
root = doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed = 0

# virtio-blk
for disk in root.findall('./devices/disk'):
    target = disk.find('./target')
    if target.attrib['dev'][:2] != 'vd' :
        continue
    driver = disk.find('./driver')
    if driver is not None:
        if driver.get('iothread') is not None:
            del driver.attrib['iothread']
            changed = 1

# virtio-scsi
for scsi in root.findall("./devices/controller[@type='scsi']"):
    driver = scsi.find('./driver')
    if driver is not None:
        if driver.get('iothread') is not None:
            del driver.attrib['iothread']
            changed = 1

if 0:
    iothreads = root.find('./iothreads')
    if iothreads is not None:
        root.remove(iothreads)
        changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
