#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2022, StorPool (storpool.com)                               #
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

def get_attributes(attr):
    ret = {}
    for a in attr.split(';'):
        try:
            k,v = a.split('=')
        except ValueError as err:
            k,v = a.split(':')
        ret[k] = v
    return ret

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

smbios_names = [ 'bios', 'system', 'baseBoard', 'chassis', 'oemStrings' ]
sysinfo = {}

for smbios_name in smbios_names:
    t_smbios_name_e = vm.find('.//USER_TEMPLATE/T_SMBIOS_{}'.format(smbios_name.upper()))
    if t_smbios_name_e is not None:
        if smbios_name == 'oemStrings':
            sysinfo[smbios_name] = t_smbios_name_e.text.split(';')
        else:
            sysinfo[smbios_name] = get_attributes(t_smbios_name_e.text)

if not sysinfo:
    exit(0)

# merge all <os> elements in first one
os_e = None
os_elements = root.findall('.//os')
os_len = len(os_elements)
if os_len > 0:
    os_e = os_elements[0]
    if os_len > 1:
        for os_element in os_elements[1:]:
            for os_child in os_element.getchildren():
                os_e.append(os_child)
                os_element.remove(os_child)
            for os_k, os_v in os_element.attrib.iteritems():
                os_e.attrib[os_k] = '{}'.format(os_v)
            root.remove(os_element)
else:
    os_e = ET.SubElement(root, 'os', os_attrib)

os_smbios_e = os_e.find('./smbios')
if os_smbios_e is None:
    os_smbios_e = ET.SubElement(os_e, 'smbios', {"mode": "sysinfo"})
    changed = 1
else:
    exit(1)

sysinfo_e = None
sysinfo_elements = root.findall('.//sysinfo')
sysinfo_len = len(sysinfo_elements)
if len(sysinfo_elements):
    for sysinfo_element in sysinfo_elements:
        sysinfo_type = sysinfo_element.get('type')
        if sysinfo_type == 'smbios':
            sysinfo_e = sysinfo_element
            break

if sysinfo_e is None:
    sysinfo_e = ET.SubElement(root, 'sysinfo', {"type": "smbios"})
    changed = 1

for key, data in sysinfo.items():
    key_e = sysinfo_e.find('./{}'.format(key))
    if key_e is not None:
        continue
    key_e = ET.SubElement(sysinfo_e, key)
    if key == 'oemStrings':
        for value in data:
            entry_e = ET.SubElement(key_e, 'entry')
            entry_e.text = value
    else:
        for name, value in data.items():
            entry_e = ET.SubElement(key_e, 'entry', {"name": name})
            entry_e.text = value
    changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
