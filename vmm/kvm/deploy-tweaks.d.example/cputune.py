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

from __future__ import print_function
import os
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

changed = False

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

delete_shares = False
cputune = {}
for pfx in [None, "global", "emulator", "iothread"]:
    for entry in ["period", "quota"]:
        e = entry
        if pfx:
            e = f"{pfx}_{entry}"
        t_cputune_e = os.getenv(f"T_CPUTUNE_{e.upper()}")
        if t_cputune_e is not None:
            cputune[e] = t_cputune_e
        t_cputune_e = vm.find(f"./USER_TEMPLATE/T_CPUTUNE_{e.upper()}")
        if t_cputune_e is not None:
            cputune[e] = t_cputune_e.text

cputune_e = root.find("./cputune")
for key, val in cputune.items():
    if val:
        delete_shares = True
        t_cputune_e = ET.SubElement(cputune_e, key)
        t_cputune_e.text = str(val)
        changed = True

cputune_shares_keep = os.getenv("T_CPUTUNE_SHARES_KEEP")
if cputune_shares_keep is not None:
    delete_shares = False
t_cputune_shares_keep_e = vm.find("./USER_TEMPLATE/T_CPUTUNE_SHARES_KEEP")
if t_cputune_shares_keep_e is not None:
    delete_shares = False

if delete_shares:
    shares_e = cputune_e.find("./shares")
    if shares_e is not None:
        cputune_e.remove(shares_e)

if changed:
    indent(root)
    doc.write(xmlDomain)
