#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2018, StorPool (storpool.com)                               #
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

def indent(elem, level=0):
    i = "\n" + level*"\t"
    if len(elem):
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

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

clock = root.find("./clock")

if root.find("./features/hyperv") is not None:
    if clock is None:
        clock = ET.SubElement(root, 'clock', {
            'offset' : 'utc',
            })
        clock = ET.Element("clock", offset = 'utc')

    # improve clock settings for windows based hosts
    clock.append(ET.Element("timer", name = 'hypervclock', present = "yes"))
    clock.append(ET.Element("timer", name = 'rtc', tickpolicy = 'catchup'))
    clock.append(ET.Element("timer", name = 'pit', tickpolicy = 'delay'))
    clock.append(ET.Element("timer", name = 'hpet', present = 'no'))

    indent(root)
    doc.write(xmlDomain)
