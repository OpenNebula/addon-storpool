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
    'one': "http://opennebula.org/xmlns/libvirt/1.0"
}

AUTO = ('auto', 'vcpu', 'yes', 'y', '1')


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
    print(f"Error in scsi-queues: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is not None:
        text: Optional[str] = element.text
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


def current_vcpus() -> int:
    vcpu_e: Optional[ET.Element] = root.find('./vcpu')
    if vcpu_e is None:
        fatal('missing vcpu')
    current: Optional[str] = vcpu_e.get('current')
    if current is not None and current.isdigit() and int(current) >= 1:
        return int(current)
    if vcpu_e.text is not None and vcpu_e.text.strip().isdigit():
        count: int = int(vcpu_e.text.strip())
        if count >= 1:
            return count
    fatal('missing vcpu')
    return 1


def queue_count(tag: str, text: str) -> int:
    if text.lower() in AUTO:
        return current_vcpus()
    if text.isdigit() and int(text) >= 1:
        return int(text)
    fatal(f"{tag} '{text}' is not a positive integer or auto")
    return 1


def unsigned(tag: str, text: str) -> str:
    if not text.isdigit():
        fatal(f"{tag} '{text}' is not an unsigned integer")
    return text


def positive(tag: str, text: str) -> str:
    if not text.isdigit() or int(text) < 1:
        fatal(f"{tag} '{text}' is not a positive integer")
    size: int = int(text)
    if size & (size - 1):
        fatal(f"{tag} '{text}' is not a power of two")
    return text


def set_attr(elem: ET.Element, key: str, value: str) -> bool:
    if elem.get(key) == value:
        return False
    elem.set(key, value)
    return True


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_et: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_et.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

scsi_text: Optional[str] = template_text('T_SCSI_QUEUES')
blk_text: Optional[str] = template_text('T_BLK_QUEUES')
if scsi_text is None and blk_text is None:
    sys.exit(0)

changed: bool = False

if scsi_text is not None:
    head, attrs = split_spec(scsi_text)
    unknown: List[str] = [key for key in attrs if key not in ('cmd_per_lun', 'max_sectors')]
    if unknown:
        fatal(f"unknown scsi attribute '{unknown[0]}'")
    queues: int = queue_count('T_SCSI_QUEUES', head)
    cmd_per_lun: Optional[str] = None
    if 'cmd_per_lun' in attrs:
        cmd_per_lun = unsigned('cmd_per_lun', attrs['cmd_per_lun'])
    max_sectors: Optional[str] = None
    if 'max_sectors' in attrs:
        max_sectors = unsigned('max_sectors', attrs['max_sectors'])
    controllers: List[ET.Element] = []
    for scsi in root.findall("./devices/controller[@type='scsi']"):
        if (scsi.get('model') or 'virtio-scsi') == 'virtio-scsi':
            controllers.append(scsi)
    if not controllers:
        devices_e: Optional[ET.Element] = root.find('./devices')
        if devices_e is None:
            fatal('missing devices')
        scsi_e: ET.Element = ET.SubElement(devices_e, 'controller', {
            'type': 'scsi',
            'model': 'virtio-scsi',
        })
        controllers.append(scsi_e)
        changed = True
    for scsi in controllers:
        driver_e: Optional[ET.Element] = scsi.find('./driver')
        if driver_e is None:
            driver_e = ET.SubElement(scsi, 'driver')
            changed = True
        if set_attr(driver_e, 'queues', str(queues)):
            changed = True
        if cmd_per_lun is not None and set_attr(driver_e, 'cmd_per_lun', cmd_per_lun):
            changed = True
        if max_sectors is not None and set_attr(driver_e, 'max_sectors', max_sectors):
            changed = True

if blk_text is not None:
    head, attrs = split_spec(blk_text)
    unknown = [key for key in attrs if key != 'queue_size']
    if unknown:
        fatal(f"unknown blk attribute '{unknown[0]}'")
    queues = queue_count('T_BLK_QUEUES', head)
    qsize: Optional[str] = None
    if 'queue_size' in attrs:
        qsize = positive('queue_size', attrs['queue_size'])
    for disk_e in root.findall('./devices/disk'):
        target_e: Optional[ET.Element] = disk_e.find('./target')
        if target_e is None or not target_e.get('dev', '').startswith('vd'):
            continue
        driver_e = disk_e.find('./driver')
        if driver_e is None:
            driver_e = ET.SubElement(disk_e, 'driver')
            changed = True
        if set_attr(driver_e, 'queues', str(queues)):
            changed = True
        if qsize is not None and set_attr(driver_e, 'queue_size', qsize):
            changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
