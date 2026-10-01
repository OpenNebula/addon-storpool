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

from typing import Dict, Optional, Tuple
import os
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}

IO: Tuple[str, ...] = ('threads', 'native', 'io_uring')
POOL_ATTRS: Tuple[str, ...] = ('thread_pool_min', 'thread_pool_max')
POLL_ATTRS: Tuple[str, ...] = ('poll_max', 'poll_grow', 'poll_shrink')
KNOWN: Tuple[str, ...] = POOL_ATTRS + POLL_ATTRS + ('io', 'queue')


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
    print(f"Error in iothreads: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    text: Optional[str]
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is not None:
        text = element.text
    else:
        text = os.getenv(tag)
    if text is None:
        return None
    text = text.strip()
    if text == '':
        return None
    return text


def split_spec(text: str) -> Tuple[str, Dict[str, str]]:
    if ':' not in text:
        return text, {}
    head, rest = text.split(':', 1)
    attrs: Dict[str, str] = {}
    for item in rest.split():
        if '=' not in item:
            fatal(f"bad attribute '{item}'")
        key, value = item.split('=', 1)
        attrs[key] = value
    return head, attrs


def unsigned(tag: str, text: str) -> str:
    if not text.isdigit():
        fatal(f"{tag} '{text}' is not an unsigned integer")
    return text


def assign(driver_e: ET.Element, iothread_id: str, queue: Optional[str],
           io_mode: Optional[str]) -> None:
    if io_mode is not None:
        driver_e.set('io', io_mode)
    for old in list(driver_e.findall('iothreads')):
        driver_e.remove(old)
    if 'iothread' in driver_e.attrib:
        del driver_e.attrib['iothread']
    if queue is None:
        driver_e.set('iothread', iothread_id)
        return
    mapping: ET.Element = ET.SubElement(driver_e, 'iothreads')
    thread_e: ET.Element = ET.SubElement(
        mapping, 'iothread', {'id': iothread_id})
    ET.SubElement(thread_e, 'queue', {'id': queue})


def ensure_driver(parent: ET.Element) -> ET.Element:
    driver_e: Optional[ET.Element] = parent.find('./driver')
    if driver_e is None:
        driver_e = ET.SubElement(parent, 'driver')
    return driver_e


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

spec: Optional[str] = template_text('T_IOTHREADS')
override: Optional[str] = template_text('T_IOTHREADS_OVERRIDE')
if override == '0':
    sys.exit(0)
if spec is None:
    spec = override
if spec is None:
    sys.exit(0)

head, attrs = split_spec(spec)
unknown = [key for key in attrs if key not in KNOWN]
if unknown:
    fatal(f"unknown iothread attribute '{unknown[0]}'")
if not head.isdigit() or int(head) < 1:
    fatal(f"count '{head}' is not a positive integer")
count: int = int(head)
io_mode: str = attrs.get('io', 'native')
if io_mode not in IO:
    fatal(f"io '{io_mode}' is not threads, native, or io_uring")
queue: Optional[str] = attrs.get('queue')
if queue is not None:
    unsigned('queue', queue)
for key in POOL_ATTRS + POLL_ATTRS:
    if key in attrs:
        unsigned(key, attrs[key])

iothreads_e: Optional[ET.Element] = root.find('iothreads')
if iothreads_e is None:
    iothreads_e = ET.Element('iothreads')
    devices_e: Optional[ET.Element] = root.find('devices')
    if devices_e is None:
        root.append(iothreads_e)
    else:
        root.insert(list(root).index(devices_e), iothreads_e)
iothreads_e.text = str(count)

for old_ids in list(root.findall('iothreadids')):
    root.remove(old_ids)
if any(key in attrs for key in POOL_ATTRS + POLL_ATTRS):
    ids_e: ET.Element = ET.Element('iothreadids')
    want_poll: bool = any(key in attrs for key in POLL_ATTRS)
    for idx in range(1, count + 1):
        thread_attrs: Dict[str, str] = {'id': str(idx)}
        if 'thread_pool_min' in attrs:
            thread_attrs['thread_pool_min'] = attrs['thread_pool_min']
        if 'thread_pool_max' in attrs:
            thread_attrs['thread_pool_max'] = attrs['thread_pool_max']
        thread_e: ET.Element = ET.SubElement(ids_e, 'iothread', thread_attrs)
        if want_poll:
            poll_attrs: Dict[str, str] = {}
            if 'poll_max' in attrs:
                poll_attrs['max'] = attrs['poll_max']
            if 'poll_grow' in attrs:
                poll_attrs['grow'] = attrs['poll_grow']
            if 'poll_shrink' in attrs:
                poll_attrs['shrink'] = attrs['poll_shrink']
            ET.SubElement(thread_e, 'poll', poll_attrs)
    root.insert(list(root).index(iothreads_e) + 1, ids_e)

nth: int = 1
for disk in root.findall('./devices/disk'):
    target_e: Optional[ET.Element] = disk.find('./target')
    if target_e is None or not target_e.get('dev', '').startswith('vd'):
        continue
    assign(ensure_driver(disk), str(nth), queue, io_mode)
    nth = (nth % count) + 1

for scsi in root.findall("./devices/controller[@type='scsi']"):
    if (scsi.get('model') or 'virtio-scsi') != 'virtio-scsi':
        continue
    assign(ensure_driver(scsi), str(nth), queue, None)
    nth = (nth % count) + 1

indent(root)
doc.write(xmlDomain)
