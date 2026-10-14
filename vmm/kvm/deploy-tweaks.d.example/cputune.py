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

from typing import Optional, Dict
import os
from sys import argv
from xml.etree import ElementTree as ET

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

cputune: Dict[str, str] = {}
for pfx in [None, "global", "emulator", "iothread"]:
    for entry in ["period", "quota"]:
        e: str = entry
        if pfx:
            e = f"{pfx}_{entry}"
        t_cputune: Optional[str] = os.getenv(f"T_CPUTUNE_{e.upper()}")  # type: ignore[attr-defined] # noqa: E501
        if t_cputune is not None:
            cputune[e] = t_cputune
        t_cputune_e: Optional[ET.Element] = vm.find(
            f"./USER_TEMPLATE/T_CPUTUNE_{e.upper()}")
        if t_cputune_e is not None and t_cputune_e.text is not None:
            cputune[e] = str(t_cputune_e.text)

cputune_e: Optional[ET.Element] = root.find("./cputune")
if cputune_e is None:
    cputune_e = ET.SubElement(root, "cputune")

for key, val in cputune.items():
    if val:
        t_cputune_e = ET.SubElement(cputune_e, key)
        t_cputune_e.text = str(val)
        changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
