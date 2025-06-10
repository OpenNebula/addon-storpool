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
from os import environ
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

vmListen = None
if 'GRAPHICS_LISTEN' in environ:
    vmListen = environ.get('GRAPHICS_LISTEN')
else:
    vmListen_e = vm.find('./TEMPLATE/GRAPHICS/LISTEN')
    if vmListen_e is not None:
        vmListen = vmListen_e.text

changed = 0

if vmListen is not None:
    #<graphics type="vnc" port="6122" autoport="no" listen="vnc.localdomain">
    #    <listen type="address" address="vnc.localdomain"/>
    #</graphics>
    for graphics_e in root.findall('./devices/graphics'):
        if graphics_e.get('listen') is not None:
            if graphics_e.attrib['listen'] != vmListen:
                graphics_e.attrib['listen'] = vmListen
                changed = 1
        for listen_e in graphics_e.findall('./listen'):
            if listen_e.get('address') is not None:
                if listen_e.attrib['address'] != vmListen:
                    listen_e.attrib['address'] = vmListen
                    changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
