#!/usr/bin/env python3

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

from sys import argv
import os
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


vcpu_element = root.find('./vcpu')
if vcpu_element is not None:
    vcpu = int(vcpu_element.text)
else:
    vcpu = 1
    vcpu_element = ET.SubElement(root, 'vcpu')
    vcpu_element.text = '1'


controllers = root.findall("./devices/controller[@type='scsi']")
if len(controllers) == 0:
    devices = root.find('./devices')
    scsi = ET.SubElement(devices, 'controller', {
            'type': 'scsi',
            'model': 'virtio-scsi'
        })
    controllers = [scsi]

for scsi in controllers:
    driver = scsi.find('./driver')
    if driver is None:
        driver = ET.SubElement(scsi, 'driver')
    driver.attrib['queues'] = '{0}'.format(vcpu)

# virtio-blk
blk_queues = os.getenv('T_BLK_QUEUES', 'NO')
blk_queues_e = vm.find('.//USER_TEMPLATE/T_BLK_QUEUES')
if blk_queues_e is not None:
    blk_queues = blk_queues_e.text
if blk_queues.upper() in ['1', 'YES', 'Y']:
    for disk in root.findall('./devices/disk'):
        target = disk.find('./target')
        if target.attrib['dev'][:2] != 'vd' :
            continue
        driver = disk.find('./driver')
        driver.attrib['queues'] = '{0}'.format(vcpu)

indent(root)
doc.write(xmlDomain)
