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
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}

CHOICES: Tuple[Tuple[str, str, Tuple[str, ...]], ...] = (
    ('CACHE', 'cache', (
        'default', 'none', 'writeback', 'writethrough',
        'directsync', 'unsafe')),
    ('IO', 'io', ('threads', 'native', 'io_uring')),
    ('DISCARD', 'discard', ('unmap', 'ignore')),
    ('DETECT_ZEROES', 'detect_zeroes', ('off', 'on', 'unmap')),
    ('IOEVENTFD', 'ioeventfd', ('on', 'off')),
)
ORDER: Tuple[str, ...] = (
    'cache', 'io', 'discard', 'detect_zeroes', 'ioeventfd', 'queue_size')
DEFAULTS: Dict[str, str] = {
    'cache': 'none',
    'io': 'native',
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


def fatal(msg: str) -> None:
    print(f"Error in context-cache: {msg}", file=sys.stderr)
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
    if text == '':
        return None
    return text


def driver_values() -> List[Tuple[str, str]]:
    values: Dict[str, str] = dict(DEFAULTS)
    suffix: str
    attr: str
    allowed: Tuple[str, ...]
    for suffix, attr, allowed in CHOICES:
        tag: str = f"T_CONTEXT_{suffix}"
        text: Optional[str] = template_text(tag)
        if text is None:
            continue
        if text not in allowed:
            fatal(f"{tag} '{text}' is not one of {', '.join(allowed)}")
        values[attr] = text
    qtag: str = 'T_CONTEXT_QUEUE_SIZE'
    qtext: Optional[str] = template_text(qtag)
    if qtext is not None:
        if not qtext.isdigit() or int(qtext) < 1:
            fatal(f"{qtag} '{qtext}' is not a positive integer")
        size: int = int(qtext)
        if size & (size - 1):
            fatal(f"{qtag} '{qtext}' is not a power of two")
        values['queue_size'] = qtext
    pairs: List[Tuple[str, str]] = []
    name: str
    for name in ORDER:
        if name in values:
            pairs.append((name, values[name]))
    return pairs


def apply_driver(disk: ET.Element, pairs: List[Tuple[str, str]]) -> None:
    driver_e: Optional[ET.Element] = disk.find('./driver')
    if driver_e is None:
        driver_e = ET.SubElement(disk, 'driver')
    item: Tuple[str, str]
    for item in pairs:
        driver_e.set(item[0], item[1])


def source_path(disk: ET.Element) -> Optional[str]:
    source_e: Optional[ET.Element] = disk.find('./source')
    if source_e is None:
        return None
    if 'file' in source_e.attrib:
        return source_e.attrib['file']
    if 'dev' in source_e.attrib:
        return source_e.attrib['dev']
    return None


def disk_id_text(path: str) -> Optional[str]:
    dotted: str = path.split('.')[-1]
    if dotted.isdigit():
        return dotted
    leaf: str = path.rsplit('/', 1)[-1]
    if leaf.startswith('sp-') and leaf[3:].isdigit():
        return leaf[3:]
    return None


def context_disk_id() -> Optional[str]:
    element: Optional[ET.Element] = vm.find('./TEMPLATE/CONTEXT/DISK_ID')
    if element is None or element.text is None:
        return None
    text: str = element.text.strip()
    if text.isdigit():
        return text
    return None


def is_context_cdrom(disk: ET.Element) -> bool:
    wanted: Optional[str] = context_disk_id()
    if wanted is None:
        return False
    path: Optional[str] = source_path(disk)
    if path is None:
        return False
    return disk_id_text(path) == wanted


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

pairs: List[Tuple[str, str]] = driver_values()
cdroms: List[ET.Element] = []
for disk in root.findall('./devices/disk[@device="cdrom"]'):
    if disk.get('type') == 'file' or is_context_cdrom(disk):
        cdroms.append(disk)
if not cdroms:
    sys.exit(0)
disk: ET.Element
for disk in cdroms:
    apply_driver(disk, pairs)
indent(root)
doc.write(xmlDomain)
