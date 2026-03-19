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

from typing import Optional, List, Dict
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
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


def get_attributes(attr: str) -> Dict[str, str]:
    ret: Dict[str, str] = {}
    for a in attr.split(';'):
        try:
            k, v = a.split('=')
        except ValueError:
            k, v = a.split(':')
        ret[k] = v
    return ret


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

smbios_names: List[str] = [
    'bios',
    'system',
    'baseBoard',
    'chassis',
    'oemStrings',
]
sysinfo: Dict[str, str | List[str] | Dict[str, str]] = {}

for smbios_name in smbios_names:
    xpath: str = f'.//USER_TEMPLATE/T_SMBIOS_{smbios_name.upper()}'
    t_smbios_name_e: Optional[ET.Element] = vm.find(xpath)
    if t_smbios_name_e is not None and t_smbios_name_e.text is not None:
        if smbios_name == 'oemStrings':
            sysinfo[smbios_name] = t_smbios_name_e.text.split(';')
        else:
            sysinfo[smbios_name] = get_attributes(t_smbios_name_e.text)

if not sysinfo:
    sys.exit(0)

# merge all <os> elements in first one
os_e: Optional[ET.Element] = None
os_elements: List[ET.Element] = root.findall('.//os')
os_len: int = len(os_elements)
if os_len > 0:
    os_e = os_elements[0]
    if os_len > 1:
        for os_element in os_elements[1:]:
            for os_child in os_element.getchildren():  # type: ignore[attr-defined] # noqa: E501
                os_e.append(os_child)
                os_element.remove(os_child)
            for os_k, os_v in os_element.attrib.items():  # type: ignore[attr-defined] # noqa: E501
                os_e.attrib[os_k] = str(os_v)
            root.remove(os_element)
else:
    os_attrib: Dict[str, str] = {}
    os_e = ET.SubElement(root, 'os', os_attrib)

os_smbios_e: Optional[ET.Element] = os_e.find('./smbios')
if os_smbios_e is None:
    os_smbios_e = ET.SubElement(os_e, 'smbios', {"mode": "sysinfo"})
    changed = True
else:
    sys.exit(1)

sysinfo_e: Optional[ET.Element] = None
sysinfo_elements: List[ET.Element] = root.findall('.//sysinfo')
sysinfo_len: int = len(sysinfo_elements)
if sysinfo_len > 0:
    for sysinfo_element in sysinfo_elements:
        sysinfo_type: Optional[str] = sysinfo_element.get('type')
        if sysinfo_type == 'smbios':
            sysinfo_e = sysinfo_element
            break

if sysinfo_e is None:
    sysinfo_e = ET.SubElement(root, 'sysinfo', {"type": "smbios"})
    changed = True

for key, data in sysinfo.items():
    key_e: Optional[ET.Element] = sysinfo_e.find(f"./{key}")
    if key_e is not None:
        continue
    key_e = ET.SubElement(sysinfo_e, key)
    entry_e: Optional[ET.Element] = None
    if key == 'oemStrings':
        for value in data:
            entry_e = ET.SubElement(key_e, 'entry')
            entry_e.text = value
    else:
        if isinstance(data, dict):
            for name, value in data.items():
                entry_e = ET.SubElement(key_e, 'entry', {"name": name})
                entry_e.text = value
    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
