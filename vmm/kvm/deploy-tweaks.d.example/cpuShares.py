#!/usr/bin/env python3
"""
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
"""
from __future__ import print_function
from typing import Optional
from sys import argv
from xml.etree import ElementTree as ET
from math import ceil

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  ") -> None:
    i: str = "\n" + level * ind
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


changed: bool = False

xmlDomain: str = argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

cputune_mul: float = 0.1
xpath: str = './USER_TEMPLATE/T_CPUTUNE_MUL'
t_cputune_mul_e: Optional[ET.Element] = vm.find(xpath)
if t_cputune_mul_e is not None:
    cputune_mul = float(t_cputune_mul_e.text or "0.1")

vcpu: int = 1
vcpu_e: Optional[ET.Element] = vm.find('./TEMPLATE/VCPU')
if (vcpu_e is not None and
        vcpu_e.text is not None and
        vcpu_e.text.isnumeric()):
    vcpu = int(vcpu_e.text)
set_cputune_shares: int = ceil((float(vcpu) * cputune_mul) * 1024.0)

xpath = './USER_TEMPLATE/T_CPUTUNE_SHARES'
for t_cputune_shares_e in vm.findall(xpath):
    if (t_cputune_shares_e is not None and
            t_cputune_shares_e.text is not None and
            t_cputune_shares_e.text.isnumeric()):
        set_cputune_shares = int(t_cputune_shares_e.text)

cputune_shares_e: Optional[ET.Element] = root.find('./cputune/shares')
if cputune_shares_e is not None:
    if int(cputune_shares_e.text or "0") != set_cputune_shares:
        cputune_shares_e.text = str(set_cputune_shares)
        changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
