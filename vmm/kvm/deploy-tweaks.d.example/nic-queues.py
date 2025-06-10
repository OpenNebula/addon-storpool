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
# -------------------------------------------------------------------------- #

from sys import argv
import os
from xml.etree import ElementTree as ET

ns = {
    "qemu": "http://libvirt.org/schemas/domain/qemu/1.0",
    "one": "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem, level=0, ind="  "):
    """Fix XML indent"""
    i = "\n" + level * ind
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


xmlDomain = argv[1]

doc = ET.parse(xmlDomain)
root = doc.getroot()

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


vcpu = 1
vcpu_element = root.find("./vcpu")
if vcpu_element is None:
    vcpu_element = ET.SubElement(root, "vcpu")
    vcpu_element.text = vcpu
else:
    vcpu = int(vcpu_element.text)


nic_queues = 0
nic_queues_env = os.getenv("T_NIC_QUEUES", "0")
if nic_queues_env.upper() == "VCPU":
    nic_queues = vcpu
elif nic_queues_env.isnumeric():
    nic_queues = int(nic_queues_env)


nic_queues_e = vm.find(".//USER_TEMPLATE/T_NIC_QUEUES")
if nic_queues_e is not None:
    if nic_queues_e.text.isnumeric() and int(nic_queues_e.text) > 0:
        nic_queues = int(nic_queues_e.text)
    elif nic_queues_e.text.upper() == "VCPU":
        nic_queues = vcpu


changed = False
for nic_e in root.findall("./devices/interface"):
    nic_q = 0
    if nic_queues > 0:
        nic_q = nic_queues
    model_e = nic_e.find("./model[@type='virtio']")
    if model_e is not None:
        target_e = nic_e.find("./target")
        nic_id = int(target_e.attrib["dev"].split("-")[-1])
        nic_q_e = vm.find(f".//USER_TEMPLATE/T_NIC{nic_id}_QUEUES")
        if nic_q_e is not None:
            if nic_q_e.text.isnumeric():
                nic_q = int(nic_q_e.text)
            elif nic_q_e.text == "vcpu":
                nic_q = vcpu
        if nic_q > 0:
            driver_e = nic_e.find("./driver")
            if driver_e is None:
                driver_e = ET.SubElement(nic_e, "driver", {"name": "vhost"})
            driver_e.attrib["queues"] = f"{nic_q}"
            changed = True


if changed:
    indent(root)
    doc.write(xmlDomain)
