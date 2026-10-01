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

from typing import Dict, List, Optional, Tuple
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

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

KVM_FLAGS: List[Tuple[str, str]] = [
    ('hide', 'hidden'),
    ('hint_dedicated', 'hint-dedicated'),
    ('poll_control', 'poll-control'),
    ('pv_ipi', 'pv-ipi'),
    ('dirty_ring', 'dirty-ring'),
]
ON: Tuple[str, ...] = ('on', '1')
OFF: Tuple[str, ...] = ('off', '0')
DIRTY_RING_MIN: int = 1024
DIRTY_RING_MAX: int = 65536


def fatal(msg: str) -> None:
    print(f"Error in kvm-hide: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(name: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(
        f".//USER_TEMPLATE/T_KVM_{name.upper()}")
    if element is None or element.text is None:
        return None
    text: str = element.text.strip()
    if text == '':
        return None
    return text


def split_spec(text: str) -> Tuple[str, Dict[str, str]]:
    raw: str = text.strip()
    state: str = raw
    rest: str = ''
    if ':' in raw:
        state, rest = raw.split(':', 1)
    attrs: Dict[str, str] = {}
    if rest.strip():
        for item in rest.split():
            if '=' not in item:
                fatal(f"bad attribute '{item}' in '{text}'")
            key, value = item.split('=', 1)
            attrs[key] = value
    return state.strip().lower(), attrs


def canonical_state(state: str) -> str:
    if state in ON:
        return 'on'
    if state in OFF:
        return 'off'
    fatal(f"state '{state}' is not on, off, 1, or 0")
    return 'off'


def same_named(parent: ET.Element, name: str) -> List[ET.Element]:
    return [child for child in list(parent) if child.tag == name]


def checked_size(raw: str) -> str:
    if not raw.isdigit():
        fatal(f"dirty-ring size '{raw}' is not an integer")
    count: int = int(raw)
    if (count < DIRTY_RING_MIN or count > DIRTY_RING_MAX
            or (count & (count - 1)) != 0):
        fatal(
            "dirty-ring size must be a power of 2 between "
            f"{DIRTY_RING_MIN} and {DIRTY_RING_MAX}")
    return str(count)


def assign(parent: ET.Element, tag: str, attrs: Dict[str, str]) -> bool:
    found: List[ET.Element] = same_named(parent, tag)
    touched: bool = False
    if not found:
        element: ET.Element = ET.SubElement(parent, tag)
        touched = True
    else:
        element = found[-1]
        for extra in found[:-1]:
            parent.remove(extra)
            touched = True
    desired: List[Tuple[str, str]] = [('state', attrs['state'])]
    if 'size' in attrs:
        desired.append(('size', attrs['size']))
    children: List[ET.Element] = list(element)
    text: str = element.text.strip() if element.text else ''
    if list(element.attrib.items()) != desired or children or text:
        element.attrib.clear()
        for key, value in desired:
            element.set(key, value)
        for child in children:
            element.remove(child)
        element.text = None
        touched = True
    return touched


changed: bool = False
features: Optional[ET.Element] = root.find('./features')
kvm: Optional[ET.Element] = None
if features is not None:
    kvm = features.find('./kvm')


def ensure_kvm() -> ET.Element:
    global changed, features, kvm
    if features is None:
        features = ET.SubElement(root, 'features')
        changed = True
    if kvm is None:
        kvm = ET.SubElement(features, 'kvm')
        changed = True
    return kvm


for key, tag in KVM_FLAGS:
    flag_text: Optional[str] = template_text(key)
    if flag_text is None:
        continue
    state, flag_attrs = split_spec(flag_text)
    state = canonical_state(state)
    if tag == 'dirty-ring':
        unknown: List[str] = [name for name in flag_attrs if name != 'size']
        if unknown:
            fatal(f"unknown dirty-ring attribute '{unknown[0]}'")
        if state == 'off':
            if flag_attrs:
                fatal("T_KVM_DIRTY_RING=off does not take attributes")
            if kvm is None or not same_named(kvm, tag):
                continue
            if assign(kvm, tag, {'state': 'off'}):
                changed = True
            continue
        size: Optional[str] = flag_attrs.get('size')
        if size is None and kvm is not None:
            present: List[ET.Element] = same_named(kvm, tag)
            if present:
                size = present[-1].get('size')
        if size is None:
            fatal("T_KVM_DIRTY_RING=on needs size")
        size = checked_size(size.strip())
        if assign(ensure_kvm(), tag, {'state': 'on', 'size': size}):
            changed = True
        continue
    if flag_attrs:
        fatal(f"T_KVM_{key.upper()} does not take attributes")
    if state == 'off':
        if kvm is None or not same_named(kvm, tag):
            continue
        if assign(kvm, tag, {'state': 'off'}):
            changed = True
        continue
    if assign(ensure_kvm(), tag, {'state': 'on'}):
        changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
