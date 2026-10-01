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

TYPES: Tuple[str, ...] = (
    'vga', 'cirrus', 'vmvga', 'xen', 'vbox', 'gop', 'none', 'bochs',
    'ramfb', 'qxl', 'virtio')
VIRTIO_DEVICES: Tuple[str, ...] = (
    'virtio-vga', 'virtio-vga-gl', 'virtio-gpu', 'virtio-gpu-gl',
    'vhost-user-vga', 'vhost-user-gpu')
YESNO: Tuple[str, ...] = ('yes', 'no')
ONOFF: Tuple[str, ...] = ('on', 'off')
MODEL_ORDER: Tuple[str, ...] = (
    'type', 'device', 'vram', 'heads', 'primary', 'blob', 'edid',
    'ram', 'vgamem', 'vram64')
QXL_ONLY: Tuple[str, ...] = ('ram', 'vgamem', 'vram64')
ACCEL_ORDER: Tuple[str, ...] = ('accel3d', 'accel2d', 'rendernode')
KNOWN: Tuple[str, ...] = MODEL_ORDER + ('resolution',) + ACCEL_ORDER


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
    print(f"Error in video: {msg}", file=sys.stderr)
    sys.exit(2)


def template_text(tag: str) -> Optional[str]:
    text: Optional[str] = os.getenv(tag)
    element: Optional[ET.Element] = vm.find(f".//USER_TEMPLATE/{tag}")
    if element is not None and element.text is not None:
        text = element.text
    if text is None:
        return None
    text = text.strip()
    if text == '':
        return None
    return text


def one_of(tag: str, text: str, allowed: Tuple[str, ...]) -> str:
    if text not in allowed:
        fatal(f"{tag} '{text}' is not one of {', '.join(allowed)}")
    return text


def unsigned(tag: str, text: str) -> str:
    if not text.isdigit():
        fatal(f"{tag} '{text}' is not an unsigned integer")
    return text


def parse_spec(text: str) -> Dict[str, str]:
    attrs: Dict[str, str] = {}
    for item in text.split():
        if '=' not in item:
            fatal(f"bad attribute '{item}'")
        key, value = item.split('=', 1)
        if key not in KNOWN:
            fatal(f"unknown attribute '{key}'")
        attrs[key] = value
    return attrs


def parse_resolution(text: str) -> Tuple[str, str]:
    parts = text.split('x')
    if (len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit()
            or int(parts[0]) < 1 or int(parts[1]) < 1):
        fatal(f"resolution '{text}' is malformed")
    return parts[0], parts[1]


def build_video(attrs: Dict[str, str]) -> ET.Element:
    if 'type' not in attrs:
        fatal("type is required")
    vtype: str = one_of('type', attrs['type'], TYPES)
    if 'device' in attrs:
        if vtype != 'virtio':
            fatal("device is only valid when type=virtio")
        one_of('device', attrs['device'], VIRTIO_DEVICES)
    if 'primary' in attrs:
        one_of('primary', attrs['primary'], YESNO)
    if 'blob' in attrs:
        one_of('blob', attrs['blob'], ONOFF)
    if 'edid' in attrs:
        one_of('edid', attrs['edid'], ONOFF)
    for key in ('heads', 'vram'):
        if key in attrs:
            unsigned(key, attrs[key])
    for key in QXL_ONLY:
        if key not in attrs:
            continue
        if vtype != 'qxl':
            fatal(f"{key} is only valid when type=qxl")
        unsigned(key, attrs[key])
    res_x: Optional[str] = None
    res_y: Optional[str] = None
    if 'resolution' in attrs:
        res_x, res_y = parse_resolution(attrs['resolution'])
    for key in ('accel2d', 'accel3d'):
        if key in attrs:
            one_of(key, attrs[key], YESNO)
    if 'rendernode' in attrs and attrs['rendernode'] == '':
        fatal("rendernode is empty")

    model_attrs: Dict[str, str] = {}
    for key in MODEL_ORDER:
        if key in attrs:
            model_attrs[key] = attrs[key]
    video_e: ET.Element = ET.Element('video')
    model_e: ET.Element = ET.SubElement(video_e, 'model', model_attrs)
    if res_x is not None and res_y is not None:
        ET.SubElement(model_e, 'resolution', {'x': res_x, 'y': res_y})
    accel_attrs: Dict[str, str] = {}
    for key in ACCEL_ORDER:
        if key in attrs:
            accel_attrs[key] = attrs[key]
    if accel_attrs:
        ET.SubElement(model_e, 'acceleration', accel_attrs)
    return video_e


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

spec: Optional[str] = template_text('T_VIDEO_MODEL')
if spec is None:
    sys.exit(0)

video_e: ET.Element = build_video(parse_spec(spec))
devices_e: Optional[ET.Element] = root.find('./devices')
if devices_e is None:
    fatal("domain/devices element not found")

videos = list(devices_e.findall('video'))
if videos:
    index = list(devices_e).index(videos[0])
else:
    index = len(devices_e)
for old in videos:
    devices_e.remove(old)
devices_e.insert(index, video_e)

indent(root)
doc.write(xmlDomain)
