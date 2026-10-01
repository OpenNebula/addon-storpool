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

from __future__ import print_function
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


xmlVm: str = sys.argv[2]
vm_element: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_element.getroot()

xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

ON: Tuple[str, ...] = ('on', '1')
OFF: Tuple[str, ...] = ('off', '0')
MIB: int = 1024 * 1024
ULLONG_MAX: int = (1 << 64) - 1


def fatal(msg: str) -> None:
    print(f"Error in feature_smm: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is None or element.text is None:
        return None
    text: str = element.text.strip()
    if text == '':
        return None
    return text


def split_attrs(text: str) -> Dict[str, str]:
    attrs: Dict[str, str] = {}
    if not text.strip():
        return attrs
    for item in text.split():
        if '=' not in item:
            fatal(f"bad attribute '{item}'")
        key, value = item.split('=', 1)
        attrs[key] = value
    return attrs


def canonical_state(state: str) -> str:
    if state in ON:
        return 'on'
    if state in OFF:
        return 'off'
    fatal(f"state '{state}' is not on, off, 1, or 0")
    return 'off'


def parse_smm(text: str) -> str:
    raw: str = text.strip()
    if ':' not in raw:
        return canonical_state(raw.lower())
    _prefix, rest = raw.split(':', 1)
    attrs: Dict[str, str] = split_attrs(rest)
    unknown: List[str] = [key for key in attrs if key != 'state']
    if unknown:
        fatal(f"unknown smm attribute '{unknown[0]}'")
    if 'state' not in attrs:
        return 'on'
    return canonical_state(attrs['state'].strip().lower())


def unit_scale(unit: str) -> int:
    low: str = unit.lower()
    if low in ('b', 'byte', 'bytes'):
        return 1
    if len(unit) == 1 or low[1:] == 'ib':
        base = 1024
    elif len(unit) == 2 and low[1] == 'b':
        base = 1000
    else:
        fatal(f"unknown tseg unit '{unit}'")
        return 1
    power: Optional[int] = {
        'k': 1, 'm': 2, 'g': 3, 't': 4, 'p': 5, 'e': 6,
    }.get(low[0])
    if power is None:
        fatal(f"unknown tseg unit '{unit}'")
        return 1
    scale: int = 1
    step: int
    for step in range(power):
        scale *= base
    return scale


def parse_tseg(text: str) -> Tuple[str, str]:
    raw: str = text.strip()
    size: str = raw
    rest: str = ''
    if ':' in raw:
        size, rest = raw.split(':', 1)
    size = size.strip()
    if size == '':
        size = '0'
    if not size.isdigit():
        fatal(f"tseg size '{size}' is not an integer")
    attrs: Dict[str, str] = split_attrs(rest)
    unknown: List[str] = [key for key in attrs if key != 'unit']
    if unknown:
        fatal(f"unknown tseg attribute '{unknown[0]}'")
    unit: str = attrs.get('unit', 'MiB')
    count: int = int(size)
    scale: int = unit_scale(unit)
    if count > ULLONG_MAX // scale:
        fatal("tseg size is too large")
    if (count * scale) % MIB != 0:
        fatal("tseg size must be a whole number of MiB")
    return str(count), unit


def same_named(parent: ET.Element, name: str) -> List[ET.Element]:
    return [child for child in list(parent) if child.tag == name]


def element_state(element: ET.Element) -> str:
    raw: Optional[str] = element.get('state')
    if raw is None or raw == 'on':
        return 'on'
    if raw == 'off':
        return 'off'
    return raw


def apply_smm(features_e: ET.Element) -> bool:
    touched: bool = False
    smm_text: Optional[str] = template_text('T_FEATURE_SMM')
    tseg_text: Optional[str] = template_text('T_FEATURE_SMM_TSEG')
    if smm_text is None and tseg_text is None:
        return False
    found: List[ET.Element] = same_named(features_e, 'smm')
    if smm_text is not None:
        state: str = parse_smm(smm_text)
    elif found:
        state = element_state(found[-1])
    else:
        state = 'off'
    if tseg_text is not None and state != 'on':
        fatal(
            "T_FEATURE_SMM_TSEG requires T_FEATURE_SMM=on "
            "or an existing <smm state='on'/>")
    size_unit: Optional[Tuple[str, str]] = None
    if tseg_text is not None:
        size_unit = parse_tseg(tseg_text)
    if not found:
        smm: ET.Element = ET.SubElement(features_e, 'smm')
        touched = True
    else:
        smm = found[-1]
        for extra in found[:-1]:
            features_e.remove(extra)
            touched = True
    if list(smm.attrib.items()) != [('state', state)]:
        smm.attrib.clear()
        smm.set('state', state)
        touched = True
    if state != 'on':
        for child in same_named(smm, 'tseg'):
            smm.remove(child)
            touched = True
        return touched
    tsegs: List[ET.Element] = same_named(smm, 'tseg')
    if size_unit is None:
        if len(tsegs) > 1:
            for extra_tseg in tsegs[:-1]:
                smm.remove(extra_tseg)
                touched = True
        return touched
    size, unit = size_unit
    if not tsegs:
        tseg: ET.Element = ET.SubElement(smm, 'tseg')
        touched = True
    else:
        tseg = tsegs[-1]
        for extra_tseg in tsegs[:-1]:
            smm.remove(extra_tseg)
            touched = True
    text: str = tseg.text.strip() if tseg.text else ''
    children: List[ET.Element] = list(tseg)
    if list(tseg.attrib.items()) != [('unit', unit)] or text != size or children:
        tseg.attrib.clear()
        tseg.set('unit', unit)
        for child in children:
            tseg.remove(child)
        tseg.text = size
        touched = True
    return touched


# merge all <features> elements in first one
features_e: Optional[ET.Element] = None
features_elements: List[ET.Element] = root.findall('.//features')
features_len: int = len(features_elements)
if features_len > 0:
    features_e = features_elements[0]
    if features_len > 1:
        for features_element in features_elements[1:]:
            for features_child in list(features_element):
                features_e.append(features_child)
                features_element.remove(features_child)
            root.remove(features_element)
            changed = True
else:
    features_e = ET.SubElement(root, 'features', {})

if apply_smm(features_e):
    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
