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

# https://bugzilla.redhat.com/show_bug.cgi?id=1663162


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

xmlVm = argv[2]
vm_doc = ET.parse(xmlVm)
vm = vm_doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

hvEnlightenments = [
    'spinlocks',
    'relaxed',
    'vapic',
    'time',
    'crash',
    'reset',
    'vpindex',
    'runtime',
    'synic',
    'stimer',
    'frequencies',

    'reenlightenment',
    'tlbflush',
    'ipi',
    'evmcs',
]

changed = 0
hyperv = root.find("./features/hyperv")
if hyperv is not None:
    for hv in hvEnlightenments:
        option_t = ".//USER_TEMPLATE/T_HV_{o}".format(o=hv.upper())
        option = vm.find(option_t)
        if option is not None:
            if option.text.lower() in ['on','1']:
                hyperv.append(ET.Element(hv, state='on'))
                changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
