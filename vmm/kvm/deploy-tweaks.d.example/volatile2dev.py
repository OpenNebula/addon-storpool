#!/usr/bin/env python2

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

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed = 0
for disk in root.findall('./devices/disk[@type="file"]'):
    try:
        source = disk.find('./source')
        file_path = source.attrib['file']
        disk_id = file_path.split('.')[-1]
        tm_mad = vm.find('./TEMPLATE/DISK[DISK_ID="{}"]/TM_MAD'.format(disk_id))
        context_disk_id = vm.find('./TEMPLATE/CONTEXT/DISK_ID')
        if tm_mad is not None:
            if tm_mad.text.lower() == 'storpool':
                source.attrib['dev'] = file_path
                del source.attrib['file']
                disk.attrib['type'] = 'block'
                changed = 1
        elif context_disk_id is not None:
            if context_disk_id.text == disk_id:
                context_tm_mad = vm.find('.//HISTORY[last()]/TM_MAD')
                if context_tm_mad.text.lower() == 'storpool':
                    source.attrib['dev'] = file_path
                    del source.attrib['file']
                    disk.attrib['type'] = 'block'
                    changed = 1
        else:
            print("Can't get TM_MAD for disk '{}'".format(file_path), file=stderr)
    except Exception as e:
        print("Error: {}".format(e), file=stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
