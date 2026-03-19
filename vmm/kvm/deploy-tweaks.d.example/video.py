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

# an example to define QXL
# USER_TEMPLATE/T_VIDEO_MODE="type=qxl primary=yes"
#
"""

from typing import Optional, Dict, List
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
vm_doc: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_doc.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


changed: bool = False
xpath: str = ".//USER_TEMPLATE/T_VIDEO_MODEL"
t_video_e: Optional[ET.Element] = vm.find(xpath)
if t_video_e is not None and t_video_e.text is not None:
    attributes: Dict[str, str] = {}
    acceleration: Dict[str, str] = {}
    for v_option in t_video_e.text.split():
        data: List[str] = v_option.split('=')
        if data[0] in ['accel2d', 'accel3d', 'rendernode']:
            acceleration[data[0]] = data[1]
        else:
            attributes[data[0]] = data[1]
    devices_e: Optional[ET.Element] = root.find('./devices')
    if devices_e is None:
        print("domain/devices element not found", file=sys.stderr)
        sys.exit(1)
    video_e: Optional[ET.Element] = devices_e.find('./video')
    if video_e is None:
        video_e = ET.SubElement(devices_e, 'video')
    model_e: Optional[ET.Element] = video_e.find('./model')
    if model_e is not None:
        video_e.remove(model_e)
    model_e = ET.SubElement(video_e, 'model', attributes)
    if acceleration:
        acceleration_e = ET.SubElement(model_e, 'acceleration', acceleration)
    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
