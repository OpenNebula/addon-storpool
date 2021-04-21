#!/usr/bin/env python2

# -------------------------------------------------------------------------- #
# Copyright 2015-2021, StorPool (storpool.com)                               #
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
import os
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

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vcpu_e = root.find('./vcpu')
if vcpu_e is None:
    vcpu_e = ET.SubElement(root, 'vcpu')
    vcpu_e.attrib['placement'] = 'static'
    vcpu_e.text = '1'
vcpu = int(vcpu_e.text)

vcpu_max = int(os.getenv('T_VCPU_MAX', vcpu))
vcpu_max_e = vm.find('.//USER_TEMPLATE/T_VCPU_MAX')
if vcpu_max_e is not None:
    try:
        vcpu_max = int(vcpu_max_e.text)
        if vcpu_max < 1:
            vcpu_max = 1
    except Exception as e:
        print("USER_TEMPLATE/T_VCPU_MAX is '{0}' Error:{1}".format(
              cpu_threads.text,e), file=stderr)
        exit(1)

vcpu_current = vcpu_e.get('current')
if vcpu_current is not None:
    print('VCPU already configured to "{0}" of "{1}" VCPUs'.format(
          vcpu_current,vcpu), file=stderr)
else:
    vcpu_current = vcpu
    vcpu_e.text = "{}".format(vcpu_max)
    vcpu_e.attrib['current'] = "{}".format(vcpu_current)
    vcpus_e = ET.SubElement(root, 'vcpus')
    hotpluggable = 'no'
    enabled = 'yes'
    for i in range(vcpu_max):
        vcpus_ee = ET.SubElement(vcpus_e,'vcpu',{
                'id' : "{}".format(i),
                'enabled' : "{}".format(enabled),
                'hotpluggable' : "{}".format(hotpluggable),
            })
        hotpluggable = "yes"
        if i == vcpu_current-1:
            enabled = 'no'

    changed = 1

memUnits = {
    'KiB' : 1024,
    'MiB' : 1024*1024,
    'GiB' : 1024*1024*1024,
    'TiB' : 1024*1024*1024*1024,
    }

memory_e = root.find('./memory')
unit = memory_e.get('unit')
if unit is None:
    unit = 'KiB'
    memory_e.attrib['unit'] = unit

memory = int(memory_e.text)

current_mem_e = root.find('./currentMemory')
if current_mem_e is not None:
    print("CurrentMemory already configured to '{}'". format(
          current_mem_e.text), file=stderr)
else:
    current_mem_e = ET.SubElement(root,'currentMemory',{
            'unit' : unit,
        })
    current_mem_e.text = "{}".format(memory)
    t_mem_max_e = vm.find('.//USER_TEMPLATE/T_MEMORY_MAX')
    if t_mem_max_e is not None:
        t_mem_max = int(t_mem_max_e.text) * memUnits[unit]
        if t_mem_max > memory:
            memory_e.text = "{}".format(t_mem_max)
    changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
