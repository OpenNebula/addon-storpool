#!/usr/bin/env python3

# -------------------------------------------------------------------------- #
# Copyright 2015-2022, StorPool (storpool.com)                               #
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
from sys import argv, exit, stderr
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

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


t_iothreads_e = vm.find('.//T_IOTHREADS_OVERRIDE')
if t_iothreads_e is not None:
    if t_iothreads_e.text == '0':
        print('T_IOTHREADS_OVERRIDE=0, Bail out!', file=stderr)
        exit(1)
iothreads = root.find('./iothreads')
if iothreads is None:
    iothreads = ET.SubElement(root, 'iothreads')
else:
    if t_iothreads_e is None:
        print('Found iothreads={}, but T_IOTHREADS_OVERRIDE is not set'.format(iothreads.text), file=stderr)
        exit(1)

iothreads.text = "1"

# virtio-blk
for disk in root.findall('./devices/disk'):
    target = disk.find('./target')
    if target.attrib['dev'][:2] != 'vd' :
        continue
    driver = disk.find('./driver')
    driver.attrib['io'] = 'native'
    driver.attrib['iothread'] = '1'

# virtio-scsi
controllers = root.findall("./devices/controller[@type='scsi']")
if controllers is None:
    device = root.find('./devices')
    scsi = ET.SubElement(device, 'controller', {
            'type': 'scsi',
            'model': 'virtio-scsi'
        })
    controllers = [scsi]

for scsi in controllers:
    driver = scsi.find('./driver')
    if driver is None:
        driver = ET.SubElement(scsi, 'driver')
    driver.attrib['iothread'] = '1'

indent(root)
doc.write(xmlDomain)
