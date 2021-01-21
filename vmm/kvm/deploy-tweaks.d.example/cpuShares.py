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
from math import ceil

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

cputune_mul = 0.1
t_cputune_mul_e = vm.find('./USER_TEMPLATE/T_CPUTUNE_MUL')
if t_cputune_mul_e is not None:
    #print( "T_CPUTUNE_MUL={s}".format(s=t_cputune_mul_e.text),file=stderr)
    cputune_mul = float(t_cputune_mul_e.text)

vcpu_e = vm.find('./TEMPLATE/VCPU')
set_cputune_shares = ceil((float(vcpu_e.text) * cputune_mul) * 1024.0)

for t_cputune_shares_e in vm.findall('./USER_TEMPLATE/T_CPUTUNE_SHARES'):
    if t_cputune_shares_e.text:
        #print( "T_CPUTUNE_SHARES={s}".format(s=t_cputune_shares_e.text),file=stderr)
        set_cputune_shares = t_cputune_shares_e.text

cputune_shares_e = root.find('./cputune/shares')
if cputune_shares_e is not None:
    if int(cputune_shares_e.text) != set_cputune_shares:
        #print( "cputune/shares={s}<<{n}".format(s=cputune_shares_e.text,n=set_cputune_shares),file=stderr)
        cputune_shares_e.text = str(int(set_cputune_shares))
        changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
