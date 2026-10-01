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

# https://bugzilla.redhat.com/show_bug.cgi?id=1663162

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

HV_FLAGS: List[str] = [
    'relaxed',
    'vapic',
    'spinlocks',
    'vpindex',
    'runtime',
    'synic',
    'stimer',
    'reset',
    'vendor_id',
    'frequencies',
    'reenlightenment',
    'tlbflush',
    'ipi',
    'evmcs',
    'avic',
    'emsr_bitmap',
    'xmm_input',
]
HV_CHILDREN: Dict[str, Tuple[str, ...]] = {
    'stimer': ('direct',),
    'tlbflush': ('direct', 'extended'),
}
HV_REMOVED: Tuple[str, ...] = ('time', 'crash')
HV_MODES: Tuple[str, ...] = ('custom', 'passthrough', 'host-model')
ON: Tuple[str, ...] = ('on', '1')
OFF: Tuple[str, ...] = ('off', '0')
SPINLOCKS_DEFAULT_RETRIES: str = '8191'
SPINLOCKS_MIN_RETRIES: int = 4095
SPINLOCKS_MAX_RETRIES: int = 4294967295
VENDOR_ID_MAX: int = 12


def fatal(msg: str) -> None:
    print(f"Error in hv-enlightenments: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(name: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(
        f".//USER_TEMPLATE/T_HV_{name.upper()}")
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


def upsert(parent: ET.Element, name: str) -> ET.Element:
    found: List[ET.Element] = same_named(parent, name)
    if not found:
        return ET.SubElement(parent, name)
    keep: ET.Element = found[-1]
    for extra in found[:-1]:
        parent.remove(extra)
    return keep


def apply_children(parent_e: ET.Element, parent: str, state: str) -> None:
    for child in HV_CHILDREN.get(parent, ()):
        child_text: Optional[str] = template_text(f"{parent}_{child}")
        if child_text is None:
            continue
        child_state, child_attrs = split_spec(child_text)
        if child_attrs:
            fatal(f"T_HV_{parent}_{child} does not take attributes")
        child_state = canonical_state(child_state)
        if state != 'on':
            fatal(
                f"T_HV_{parent.upper()}_{child.upper()} requires "
                f"T_HV_{parent.upper()}=on or an existing "
                "<{parent} state='on'/>")
        child_e: ET.Element = upsert(parent_e, child)
        child_e.attrib.clear()
        child_e.set('state', child_state)
        child_e.text = None


def apply_flag(hv_e: ET.Element, name: str, text: str) -> None:
    if name == 'vendor_id':
        apply_vendor(hv_e, text)
        return
    state, attrs = split_spec(text)
    state = canonical_state(state)
    element: ET.Element = upsert(hv_e, name)
    if name == 'spinlocks':
        unknown = [key for key in attrs if key != 'retries']
        if unknown:
            fatal(f"unknown spinlocks attribute '{unknown[0]}'")
        element.attrib.clear()
        element.set('state', state)
        if state == 'on':
            retries: str = attrs.get('retries', SPINLOCKS_DEFAULT_RETRIES)
            if not retries.isdigit():
                fatal(f"spinlocks retries '{retries}' is not an integer")
            count: int = int(retries)
            if count < SPINLOCKS_MIN_RETRIES or count > SPINLOCKS_MAX_RETRIES:
                fatal(
                    "spinlocks retries must be between "
                    f"{SPINLOCKS_MIN_RETRIES} and {SPINLOCKS_MAX_RETRIES}")
            element.set('retries', str(count))
    else:
        if attrs:
            fatal(f"T_HV_{name.upper()} does not take attributes")
        element.attrib.clear()
        element.set('state', state)
    element.text = None
    if state != 'on':
        for child_name in HV_CHILDREN.get(name, ()):
            for child_e in same_named(element, child_name):
                element.remove(child_e)
    apply_children(element, name, state)


def apply_vendor(hv_e: ET.Element, text: str) -> None:
    raw: str = text.strip()
    low: str = raw.lower()
    value: Optional[str] = None
    if low in OFF:
        state = 'off'
    elif low in ON:
        fatal("T_HV_VENDOR_ID=on needs a vendor string")
    elif ':' in raw:
        state_text, rest = raw.split(':', 1)
        state = canonical_state(state_text.strip().lower())
        if not rest.startswith('value='):
            fatal("T_HV_VENDOR_ID attributes must be value=...")
        value = rest[len('value='):]
    else:
        state = 'on'
        value = raw
    if state == 'on':
        if value is None or value == '':
            fatal("T_HV_VENDOR_ID needs a vendor string")
        if len(value) > VENDOR_ID_MAX or ',' in value:
            fatal(
                "vendor_id value must be at most "
                f"{VENDOR_ID_MAX} characters and must not contain a comma")
    element: ET.Element = upsert(hv_e, 'vendor_id')
    element.attrib.clear()
    element.set('state', state)
    if state == 'on' and value is not None:
        element.set('value', value)
    element.text = None


changed: bool = False
hyperv: Optional[ET.Element] = root.find("./features/hyperv")

for removed in HV_REMOVED:
    if template_text(removed) is not None:
        print(
            f"T_HV_{removed.upper()} is not a libvirt Hyper-V feature",
            file=sys.stderr)

if hyperv is not None:
    mode_text: Optional[str] = template_text('mode')
    mode: Optional[str] = None
    if mode_text is not None:
        mode = mode_text.strip().lower()
        if mode not in HV_MODES:
            fatal(
                "T_HV_MODE must be custom, passthrough, or host-model")
        hyperv.set('mode', mode)
        changed = True
    if mode == 'passthrough':
        if any(template_text(flag) is not None for flag in HV_FLAGS):
            print(
                "T_HV_MODE=passthrough ignores Hyper-V feature children",
                file=sys.stderr)
        elif any(
                template_text(f"{parent}_{child}") is not None
                for parent, children in HV_CHILDREN.items()
                for child in children):
            print(
                "T_HV_MODE=passthrough ignores Hyper-V feature children",
                file=sys.stderr)
    else:
        for flag in HV_FLAGS:
            flag_text: Optional[str] = template_text(flag)
            if flag_text is not None:
                apply_flag(hyperv, flag, flag_text)
                changed = True
        for parent, children in HV_CHILDREN.items():
            if template_text(parent) is not None:
                continue
            found: List[ET.Element] = same_named(hyperv, parent)
            parent_e: Optional[ET.Element] = found[-1] if found else None
            parent_state: str = 'off'
            if parent_e is not None and parent_e.get('state') == 'on':
                parent_state = 'on'
            if not any(
                    template_text(f"{parent}_{child}") is not None
                    for child in children):
                continue
            if parent_e is None or parent_state != 'on':
                missing: str = next(
                    child for child in children
                    if template_text(f"{parent}_{child}") is not None)
                fatal(
                    f"T_HV_{parent.upper()}_{missing.upper()} requires "
                    f"T_HV_{parent.upper()}=on or an existing "
                    f"<{parent} state='on'/>")
            apply_children(parent_e, parent, parent_state)
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
