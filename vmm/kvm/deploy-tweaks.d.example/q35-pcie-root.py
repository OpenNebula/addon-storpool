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

from __future__ import print_function
from sys import argv, stderr
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

changed = 0

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

t_q35_ports_e = vm.find('./USER_TEMPLATE/Q35_PCIE_ROOT_PORTS')
if t_q35_ports_e is not None:
    q35_ports = int(t_q35_ports_e.text)

    machine_type = root.find('./os/type')
    if 'q35' in machine_type.attrib['machine']:
        new_device = ET.SubElement(root, 'devices', {})

        ET.SubElement(new_device, 'controller', {
                'type': 'pci',
                'model': 'pcie-root'
            })
        for i in range(0,q35_ports):
            ET.SubElement(new_device, 'controller', {
                    'type': 'pci',
                    'model': 'pcie-root-port'
                })
        ET.SubElement(new_device, 'controller', {
            'type': 'pci',
            'model': 'pcie-to-pci-bridge'
        })
        changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
