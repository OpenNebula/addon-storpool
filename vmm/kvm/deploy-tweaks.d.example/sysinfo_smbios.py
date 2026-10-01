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
import re
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}

BIOS_NAMES: Tuple[str, ...] = ('vendor', 'version', 'date', 'release')
SYSTEM_NAMES: Tuple[str, ...] = (
    'manufacturer', 'product', 'version', 'serial', 'uuid', 'sku', 'family',
)
BASEBOARD_NAMES: Tuple[str, ...] = (
    'manufacturer', 'product', 'version', 'serial', 'asset', 'location',
)
CHASSIS_NAMES: Tuple[str, ...] = (
    'manufacturer', 'version', 'serial', 'asset', 'sku',
)
UUID_RE = re.compile(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
)
NamedEntries = List[Tuple[str, str]]


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


def fatal(msg: str) -> None:
    print(f"Error in sysinfo_smbios: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(vm: ET.Element, tag: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is None or element.text is None:
        return None
    text: str = element.text.strip()
    if text == '':
        return None
    return text


def element_text(element: Optional[ET.Element]) -> Optional[str]:
    if element is None or element.text is None:
        return None
    text: str = element.text.strip()
    if text == '':
        return None
    return text


def reference_uuid(root: ET.Element) -> Tuple[Optional[str], str]:
    hw_text: Optional[str] = element_text(root.find('./hwuuid'))
    if hw_text is not None:
        return hw_text, 'hwuuid'
    uuid_text: Optional[str] = element_text(root.find('./uuid'))
    if uuid_text is not None:
        return uuid_text, 'uuid'
    return None, 'uuid'


def check_date(value: str) -> None:
    parts: List[str] = value.split('/')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        fatal(f"bios date '{value}' is not mm/dd/yy or mm/dd/yyyy")
    month, day, year = (int(part) for part in parts)
    if (month < 1 or month > 12 or day < 1 or day > 31
            or (year >= 100 and year < 1900)):
        fatal(f"bios date '{value}' is not mm/dd/yy or mm/dd/yyyy")


def check_uuid(root: ET.Element, value: str) -> None:
    if UUID_RE.match(value) is None:
        fatal(f"system uuid '{value}' is not a UUID")
    ref, which = reference_uuid(root)
    if ref is not None and value.lower() != ref.lower():
        fatal(f"system uuid does not match <{which}>")


def same_named(parent: ET.Element, name: str) -> List[ET.Element]:
    return [child for child in list(parent) if child.tag == name]


def parse_named(
        root: ET.Element,
        tag: str,
        template_key: str,
        text: str,
        names: Tuple[str, ...],
) -> List[NamedEntries]:
    chunks: List[str] = text.split('|') if tag == 'baseBoard' else [text]
    boards: List[NamedEntries] = []
    for chunk in chunks:
        fields: NamedEntries = []
        index: Dict[str, int] = {}
        for part in chunk.split(';'):
            item: str = part.strip()
            if item == '':
                continue
            if '=' in item:
                key, value = item.split('=', 1)
            elif ':' in item:
                key, value = item.split(':', 1)
            else:
                fatal(f"bad field '{item}'")
            key = key.strip()
            value = value.strip()
            if key not in names:
                print(
                    f"{template_key} entry '{key}' is not a libvirt "
                    "SMBIOS field",
                    file=sys.stderr)
                continue
            if tag == 'bios' and key == 'date':
                check_date(value)
            if tag == 'system' and key == 'uuid':
                check_uuid(root, value)
            if key in index:
                fields[index[key]] = (key, value)
            else:
                index[key] = len(fields)
                fields.append((key, value))
        if fields:
            boards.append(fields)
    return boards


def parse_oem(text: str) -> List[str]:
    values: List[str] = []
    for part in text.split(';'):
        item: str = part.strip()
        if item:
            values.append(item)
    return values


def named_snapshot(element: ET.Element) -> Optional[NamedEntries]:
    found: NamedEntries = []
    for child in list(element):
        if child.tag != 'entry' or list(child.attrib.items()) != [('name', child.get('name') or '')]:
            return None
        found.append((child.get('name') or '', (child.text or '').strip()))
    return found


def fill_named(element: ET.Element, entries: NamedEntries) -> None:
    for child in list(element):
        element.remove(child)
    element.text = None
    for name, value in entries:
        entry: ET.Element = ET.SubElement(element, 'entry', {'name': name})
        entry.text = value


def apply_named(parent: ET.Element, tag: str, entries: NamedEntries) -> bool:
    found: List[ET.Element] = same_named(parent, tag)
    touched: bool = False
    if not entries:
        for element in found:
            parent.remove(element)
            touched = True
        return touched
    if not found:
        element = ET.SubElement(parent, tag)
        fill_named(element, entries)
        return True
    element = found[0]
    for extra in found[1:]:
        parent.remove(extra)
        touched = True
    if named_snapshot(element) != entries:
        fill_named(element, entries)
        touched = True
    return touched


def apply_boards(parent: ET.Element, boards: List[NamedEntries]) -> bool:
    found: List[ET.Element] = same_named(parent, 'baseBoard')
    touched: bool = False
    if not boards:
        for element in found:
            parent.remove(element)
            touched = True
        return touched
    index: int
    for index, entries in enumerate(boards):
        if index < len(found):
            if named_snapshot(found[index]) != entries:
                fill_named(found[index], entries)
                touched = True
        else:
            element = ET.SubElement(parent, 'baseBoard')
            fill_named(element, entries)
            touched = True
    for extra in found[len(boards):]:
        parent.remove(extra)
        touched = True
    return touched


def oem_snapshot(element: ET.Element) -> Optional[List[str]]:
    found: List[str] = []
    for child in list(element):
        if child.tag != 'entry' or child.attrib:
            return None
        found.append((child.text or '').strip())
    return found


def apply_oem(parent: ET.Element, values: List[str]) -> bool:
    found: List[ET.Element] = same_named(parent, 'oemStrings')
    touched: bool = False
    if not values:
        for element in found:
            parent.remove(element)
            touched = True
        return touched
    if not found:
        element: ET.Element = ET.SubElement(parent, 'oemStrings')
        touched = True
    else:
        element = found[0]
        for extra in found[1:]:
            parent.remove(extra)
            touched = True
    if oem_snapshot(element) == values:
        return touched
    for child in list(element):
        element.remove(child)
    element.text = None
    for value in values:
        entry: ET.Element = ET.SubElement(element, 'entry')
        entry.text = value
    return True


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

bios_text: Optional[str] = template_text(vm, 'T_SMBIOS_BIOS')
system_text: Optional[str] = template_text(vm, 'T_SMBIOS_SYSTEM')
base_text: Optional[str] = template_text(vm, 'T_SMBIOS_BASEBOARD')
chassis_text: Optional[str] = template_text(vm, 'T_SMBIOS_CHASSIS')
oem_text: Optional[str] = template_text(vm, 'T_SMBIOS_OEMSTRINGS')

if (bios_text is None and system_text is None and base_text is None
        and chassis_text is None and oem_text is None):
    sys.exit(0)

bios_boards: Optional[List[NamedEntries]] = None
system_boards: Optional[List[NamedEntries]] = None
base_boards: Optional[List[NamedEntries]] = None
chassis_boards: Optional[List[NamedEntries]] = None
oem_values: Optional[List[str]] = None
if bios_text is not None:
    bios_boards = parse_named(
        root, 'bios', 'T_SMBIOS_BIOS', bios_text, BIOS_NAMES)
if system_text is not None:
    system_boards = parse_named(
        root, 'system', 'T_SMBIOS_SYSTEM', system_text, SYSTEM_NAMES)
if base_text is not None:
    base_boards = parse_named(
        root, 'baseBoard', 'T_SMBIOS_BASEBOARD', base_text, BASEBOARD_NAMES)
if chassis_text is not None:
    chassis_boards = parse_named(
        root, 'chassis', 'T_SMBIOS_CHASSIS', chassis_text, CHASSIS_NAMES)
if oem_text is not None:
    oem_values = parse_oem(oem_text)

changed: bool = False

# merge all <os> elements in first one
os_e: Optional[ET.Element] = None
os_elements: List[ET.Element] = root.findall('.//os')
os_len: int = len(os_elements)
if os_len > 0:
    os_e = os_elements[0]
    if os_len > 1:
        for os_element in os_elements[1:]:
            for os_child in list(os_element):
                os_e.append(os_child)
                os_element.remove(os_child)
            for os_k, os_v in os_element.attrib.items():  # type: ignore[attr-defined] # noqa: E501
                os_e.attrib[os_k] = str(os_v)
            root.remove(os_element)
            changed = True
else:
    os_e = ET.SubElement(root, 'os', {})

os_smbios_e: Optional[ET.Element] = os_e.find('./smbios')
if os_smbios_e is not None and os_smbios_e.get('mode') != 'sysinfo':
    mode: str = os_smbios_e.get('mode') or ''
    fatal(f"smbios mode '{mode}' must be sysinfo")

sysinfo_e: Optional[ET.Element] = None
for sysinfo_element in root.findall('.//sysinfo'):
    if sysinfo_element.get('type') == 'smbios':
        sysinfo_e = sysinfo_element
        break

blocks_present: bool = any((
    bool(bios_boards),
    bool(system_boards),
    bool(base_boards),
    bool(chassis_boards),
    bool(oem_values),
))
if blocks_present and os_smbios_e is None:
    ET.SubElement(os_e, 'smbios', {'mode': 'sysinfo'})
    changed = True
if blocks_present and sysinfo_e is None:
    sysinfo_e = ET.SubElement(root, 'sysinfo', {'type': 'smbios'})
    changed = True

if sysinfo_e is not None:
    if bios_boards is not None and apply_named(
            sysinfo_e, 'bios', bios_boards[0] if bios_boards else []):
        changed = True
    if system_boards is not None and apply_named(
            sysinfo_e, 'system', system_boards[0] if system_boards else []):
        changed = True
    if base_boards is not None and apply_boards(sysinfo_e, base_boards):
        changed = True
    if chassis_boards is not None and apply_named(
            sysinfo_e, 'chassis',
            chassis_boards[0] if chassis_boards else []):
        changed = True
    if oem_values is not None and apply_oem(sysinfo_e, oem_values):
        changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
