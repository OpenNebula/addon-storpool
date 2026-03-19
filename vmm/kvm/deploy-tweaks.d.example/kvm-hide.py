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

from typing import Optional
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
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


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_doc: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

changed: bool = False

xpath: str = './/USER_TEMPLATE/T_KVM_HIDE'
option_e: Optional[ET.Element] = vm.find(xpath)
if option_e is not None and option_e.text is not None:
    if option_e.text.lower() in ['on', '1']:
        features_e: Optional[ET.Element] = root.find('./features')
        if features_e is None:
            features_e = ET.SubElement(root, 'features')
        kvm_e: Optional[ET.Element] = features_e.find('./kvm')
        if kvm_e is None:
            kvm_e = ET.SubElement(features_e, 'kvm')
        hidden_e: Optional[ET.Element] = kvm_e.find('./hidden')
        if hidden_e is None:
            kvm_e.append(ET.Element('hidden', state='on'))
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
