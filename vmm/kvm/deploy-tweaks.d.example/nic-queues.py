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
# -------------------------------------------------------------------------- #
"""

from typing import Optional
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    "qemu": "http://libvirt.org/schemas/domain/qemu/1.0",
    "one": "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
    """Fix XML indent"""
    i: str = "\n" + level * ind
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + ind
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level + 1, ind)
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
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

vcpu: int = 1
vcpu_e: Optional[ET.Element] = root.find("./vcpu")
if vcpu_e is None:
    vcpu_e = ET.SubElement(root, "vcpu")
    vcpu_e.text = str(vcpu)
elif vcpu_e.text is not None:
    vcpu = int(vcpu_e.text)

nic_queues: int = 0
nic_queues_env: str = os.getenv("T_NIC_QUEUES", "0")  # type: ignore[attr-defined] # noqa: E501
if nic_queues_env.isnumeric():
    nic_queues = int(nic_queues_env)
elif nic_queues_env.upper() == "VCPU":
    nic_queues = vcpu

# check VM attributes
xpath: str = ".//USER_TEMPLATE/T_NIC_QUEUES"
t_nic_queues_e: Optional[ET.Element] = vm.find(xpath)
if t_nic_queues_e is not None and t_nic_queues_e.text is not None:
    if t_nic_queues_e.text.isnumeric() and int(t_nic_queues_e.text) >= 0:
        nic_queues = int(t_nic_queues_e.text)
    elif t_nic_queues_e.text.upper() == "VCPU":
        nic_queues = vcpu

changed: bool = False
for nic_e in root.findall("./devices/interface"):
    nic_q: int = nic_queues
    model_e: Optional[ET.Element] = nic_e.find("./model[@type='virtio']")
    if model_e is not None:
        target_e: Optional[ET.Element] = nic_e.find("./target")
        if target_e is not None and "dev" in target_e.attrib:
            nic_id: int = int(target_e.attrib["dev"].split("-")[-1])
            # check VM attributes for per-NIC queues
            xpath = f".//USER_TEMPLATE/T_NIC{nic_id}_QUEUES"
            nic_q_e: Optional[ET.Element] = vm.find(xpath)
            if nic_q_e is not None and nic_q_e.text is not None:
                if nic_q_e.text.isnumeric():
                    nic_q = int(nic_q_e.text)
                elif nic_q_e.text.upper() == "VCPU":
                    nic_q = vcpu
        if nic_q > 0:
            driver_e: Optional[ET.Element] = nic_e.find("./driver")
            if driver_e is None:
                driver_e = ET.SubElement(nic_e, "driver", {"name": "vhost"})
            driver_e.attrib["queues"] = f"{nic_q}"
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
