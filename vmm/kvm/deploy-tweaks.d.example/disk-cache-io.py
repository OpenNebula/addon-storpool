#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2019, StorPool (storpool.com)                               #
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

def indent(elem, level=0):
    i = "\n" + level*"\t"
    if elem is not None:
#        if not elem.text or not elem.text.strip():
#            elem.text = i + "\t"
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level+1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
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
for disk in root.findall('./devices/disk'):
    try:
        source = disk.find('./source')
        if 'file' in source.attrib:
            diskPath = source.attrib['file']
        elif 'dev' in source.attrib:
            diskPath = source.attrib['dev']
        else:
            print("Unknown source attribute:{a}".format(a=source.attrib),
                  file=stderr)
            continue
        diskId = diskPath.split('.')[-1]
        tm_mad = vm.find('./TEMPLATE/DISK[DISK_ID="{i}"]/TM_MAD'.format(
                             i=diskId))
        if tm_mad is None:
            contextId = vm.find('./TEMPLATE/CONTEXT[DISK_ID="{i}"]'.format(
                                    i=diskId))
            if contextId is not None:
                tm_mad = vm.find('./HISTORY_RECORDS/HISTORY[last()]/TM_MAD')

        if tm_mad is not None:
            if tm_mad.text.lower() == 'storpool':
                driver = disk.find('./driver')
                driver.attrib['cache'] = 'none'
                driver.attrib['io'] = 'native'
                changed = 1
        else:
            tm_mad = vm.find('./HISTORY_RECORDS/HISTORY[first()]/TM_MAD')
            print("Can't get TM_MAD for disk '{d}'".format(d=diskPath),
                  file=stderr)
    except Exception as e:
        print("Error: {e}".format(e=e), file=stderr)

if changed:
    indent(root)
    doc.write(xmlDomain)
