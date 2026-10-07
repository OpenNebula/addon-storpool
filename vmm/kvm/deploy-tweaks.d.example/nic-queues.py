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

from typing import Dict, List, Optional, Tuple
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    "qemu": "http://libvirt.org/schemas/domain/qemu/1.0",
    "one": "http://opennebula.org/xmlns/libvirt/1.0",
}

AUTO = ("auto", "vcpu", "yes", "y", "1")
TXMODE = ("iothread", "timer")


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
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


def fatal(msg: str) -> None:
    print(f"Error in nic-queues: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is not None:
        raw: Optional[str] = element.text
    else:
        raw = os.getenv(tag)
    if raw is None:
        return None
    text: str = raw.strip()
    if text == "":
        return None
    return text


def split_spec(text: str) -> Tuple[str, Dict[str, str]]:
    if ":" not in text:
        return text, {}
    head, rest = text.split(":", 1)
    attrs: Dict[str, str] = {}
    for item in rest.split():
        if "=" not in item:
            fatal(f"bad attribute '{item}'")
        key, value = item.split("=", 1)
        attrs[key] = value
    return head, attrs


def current_vcpus() -> int:
    vcpu_e: Optional[ET.Element] = root.find("./vcpu")
    if vcpu_e is None:
        fatal("missing vcpu")
    current: Optional[str] = vcpu_e.get("current")
    if current is not None and current.isdigit() and int(current) >= 1:
        return int(current)
    if vcpu_e.text is not None and vcpu_e.text.strip().isdigit():
        count: int = int(vcpu_e.text.strip())
        if count >= 1:
            return count
    fatal("missing vcpu")
    return 1


def queue_count(tag: str, text: str) -> int:
    if text.lower() in AUTO:
        return current_vcpus()
    if text.isdigit() and int(text) >= 1:
        return int(text)
    fatal(f"{tag} '{text}' is not a positive integer or auto")
    return 1


def checked_spec(tag: str, spec: str) -> Tuple[int, Dict[str, str]]:
    head, attrs = split_spec(spec)
    unknown: List[str] = [
        key for key in attrs
        if key not in ("rx_queue_size", "tx_queue_size", "txmode")
    ]
    if unknown:
        fatal(f"unknown nic attribute '{unknown[0]}'")
    queues: int = queue_count(tag, head)
    if "txmode" in attrs and attrs["txmode"] not in TXMODE:
        fatal(f"txmode '{attrs['txmode']}' is not iothread or timer")
    for key in ("rx_queue_size", "tx_queue_size"):
        if key not in attrs:
            continue
        if not attrs[key].isdigit() or int(attrs[key]) < 1:
            fatal(f"{key} '{attrs[key]}' is not a positive integer")
        size: int = int(attrs[key])
        if size & (size - 1):
            fatal(f"{key} '{attrs[key]}' is not a power of two")
    return queues, attrs


def apply_driver(nic_e: ET.Element, queues: int, attrs: Dict[str, str]) -> None:
    driver_e: Optional[ET.Element] = nic_e.find("./driver")
    if driver_e is None:
        driver_e = ET.SubElement(nic_e, "driver")
    if driver_e.get("name") is None:
        driver_e.set("name", "vhost")
    driver_e.set("queues", str(queues))
    for key in ("rx_queue_size", "tx_queue_size", "txmode"):
        if key in attrs:
            driver_e.set(key, attrs[key])


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

global_spec: Optional[str] = template_text("T_NIC_QUEUES")
pending: List[Tuple[ET.Element, int, Dict[str, str]]] = []

for nic_e in root.findall("./devices/interface"):
    model_e: Optional[ET.Element] = nic_e.find("./model[@type='virtio']")
    if model_e is None:
        continue
    spec: Optional[str] = global_spec
    tag: str = "T_NIC_QUEUES"
    target_e: Optional[ET.Element] = nic_e.find("./target")
    if target_e is not None and target_e.get("dev"):
        nic_id: str = target_e.get("dev", "").split("-")[-1]
        if nic_id.isdigit():
            per_tag: str = f"T_NIC{nic_id}_QUEUES"
            per_nic: Optional[str] = template_text(per_tag)
            if per_nic is not None:
                spec = per_nic
                tag = per_tag
    if spec is None:
        continue
    queues, attrs = checked_spec(tag, spec)
    pending.append((nic_e, queues, attrs))

if not pending:
    sys.exit(0)

for nic_e, queues, attrs in pending:
    apply_driver(nic_e, queues, attrs)

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)
indent(root)
doc.write(xmlDomain)
