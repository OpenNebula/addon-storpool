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

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

clock = root.find("./clock")

if root.find("./features/hyperv") is not None:
    if clock is None:
        clock = ET.SubElement(root, 'clock', {
            'offset' : 'utc',
            })
    timer = {
        'hypervclock': ["present", "yes"],
        'rtc': ["tickpolicy", "catchup"],
        'pit': ["tickpolicy", "delay"],
        'hpet': ["present", "no"],
    }
    # improve clock settings for windows based hosts
    for name, data in timer.items():
        timer_element = clock.find("./timer[@name='{}']".format(name))
        if timer_element is not None:
            clock.remove(timer_element)
        clock.append(ET.Element("timer", {'name': name, data[0]: data[1]}))

    indent(root)
    doc.write(xmlDomain)
