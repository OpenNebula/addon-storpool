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

from typing import Optional, Dict, List
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

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

clock_e: Optional[ET.Element] = root.find("./clock")

hyperv_e: Optional[ET.Element] = root.find("./features/hyperv")
if hyperv_e is not None:
    if clock_e is None:
        clock_e = ET.SubElement(root, 'clock', {
            'offset': 'utc',
            })
    timer_d: Dict[str, List[str]] = {
        'hypervclock': ["present", "yes"],
        'rtc': ["tickpolicy", "catchup"],
        'pit': ["tickpolicy", "delay"],
        'hpet': ["present", "no"],
    }
    # improve clock settings for windows based hosts
    for name, data in timer_d.items():
        timer_xpath: str = f"./timer[@name='{name}']"
        timer_e: Optional[ET.Element] = clock_e.find(timer_xpath)
        if timer_e is not None:
            clock_e.remove(timer_e)
        clock_e.append(ET.Element("timer", {'name': name, data[0]: data[1]}))

    indent(root)
    doc.write(xmlDomain)
