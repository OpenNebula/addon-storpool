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

from __future__ import print_function
from typing import Optional, Dict, List
import os
import io
import sys
from xml.etree import ElementTree as ET

ns = {
    "qemu": "http://libvirt.org/schemas/domain/qemu/1.0",
    "one": "http://opennebula.org/xmlns/libvirt/1.0",
}


def indent(elem: ET.Element, level: int = 0, ind: str = "  "):
    """
    Indent the XML element.
    """
    i: str = "\n" + level * ind
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + ind
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem_e in elem:
            indent(elem_e, level + 1, ind)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if not level:
            return
        if not elem.text or not elem.text.strip():
            elem.text = None
        if not elem.tail or not elem.tail.strip():
            elem.tail = i


def get_attributes(attr: str) -> Dict[str, str]:
    """
    Parse the attributes from a string.
    """
    ret: Dict[str, str] = {}
    for a in attr.split():
        k, v = a.split("=")
        ret[k] = v
    return ret


def get_spUid(img: str) -> str:
    """
    Get the SP_UID for a given image name.
    """
    if os.getenv("TEST_NVRAM_SOURCE", "NO") == "YES":  # type: ignore[attr-defined] # noqa: E501
        return "~ab.c.def"
    stream: io.TextIOWrapper = os.popen(  # type: ignore[attr-defined]
        f"etcdctl get --print-value-only '/byName/{img}'"
    )
    sp_uid: str = stream.read().strip("~\n")
    stream.close()
    return sp_uid


xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

changed: bool = False

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


one_px: str = os.getenv("ONE_PX", "one")  # type: ignore[attr-defined]
os_attr: Dict[str, str] = {}
loader_attr: Dict[str, str] = {}
nvram_attr: Dict[str, str] = {}

xpath: str = ".//USER_TEMPLATE/T_OS"
t_os_e: Optional[ET.Element] = vm.find(xpath)
if t_os_e is not None and t_os_e.text is not None:
    os_attr = get_attributes(t_os_e.text)

# merge all <os> elements in first one and alter the attributes
os_e: Optional[ET.Element] = None
os_elements: List[ET.Element] = root.findall(".//os")
os_len: int = len(os_elements)
if os_len > 0:
    os_e = os_elements[0]
    if os_len > 1:
        for os_element in os_elements[1:]:
            for os_child in list(os_element):
                os_e.append(os_child)
                os_element.remove(os_child)
            for os_k, os_v in os_element.attrib.items():
                os_e.attrib[os_k] = str(os_v)
            root.remove(os_element)
    for key, val in os_attr.items():
        if key in os_e.attrib:
            if val == "":
                del os_e.attrib[key]
                continue
        os_e.attrib[key] = f"{val}"
else:
    os_e = ET.SubElement(root, "os", os_attr)

xpath = ".//USER_TEMPLATE/T_OS_LOADER"
os_loader_e: Optional[ET.Element] = vm.find(xpath)
if os_loader_e is not None and os_loader_e.text is not None:
    os_loader_arr: List[str] = os_loader_e.text.split(":")
    loader_file: str = os_loader_arr[0]
    if len(os_loader_arr) > 1:
        loader_attr = get_attributes(os_loader_arr[1])

    loader_e: Optional[ET.Element] = os_e.find("./loader")
    if loader_e is not None:
        os_e.remove(loader_e)
    loader_e = ET.SubElement(os_e, "loader", loader_attr)
    loader_e.text = f"{loader_file}"
    changed = True

xpath = ".//USER_TEMPLATE/T_OS_NVRAM"
os_nvram_e: Optional[ET.Element] = vm.find(xpath)
if os_nvram_e is not None and os_nvram_e.text is not None:
    os_nvram_arr: List[str] = os_nvram_e.text.split(":")
    nvram_file: str = os_nvram_arr[0]
    if len(os_nvram_arr) > 1:
        nvram_attr = get_attributes(os_nvram_arr[1])

    nvram_type: Optional[str] = nvram_attr.get("type")

    if nvram_file == "storpool":
        nvram_attr = {}

    if "template" in nvram_attr:
        # expand relative path
        if len(nvram_attr["template"].split("/")) == 1:
            template_path: str = os.getenv(  # type: ignore[attr-defined] # noqa: E501
                "NVRAM_TEMPLATE_PATH",
                "/var/tmp/one/OVMF",
            )
            tmp: str = f"{template_path}/{nvram_attr['template']}"
            nvram_attr["template"] = tmp

    nvram_e: Optional[ET.Element] = os_e.find("./nvram")
    if nvram_e is not None:
        os_e.remove(nvram_e)
    nvram_e = ET.SubElement(os_e, "nvram", nvram_attr)
    if len(nvram_file) > 0:
        nvram_source_e: Optional[ET.Element] = None
        if nvram_file == "storpool":
            vm_id_e: Optional[ET.Element] = vm.find("./ID")
            if vm_id_e is None or vm_id_e.text is None:
                print(
                    'Error in <T_OS_NVRAM>: missing "ID" element',
                    file=sys.stderr,
                )
                changed = False
            else:
                vm_id: int = int(vm_id_e.text)
                img: str = f"{one_px}-sys-{vm_id}-NVRAM"
                sp_uid: str = get_spUid(img)
                if sp_uid != "":
                    nvram_filepath = f"/dev/storpool-byid/{sp_uid}"
                    if nvram_type is not None:
                        source = "file"
                        if nvram_type == "block":
                            source = "dev"
                        nvram_source_e = ET.SubElement(
                            nvram_e, "source", {source: nvram_filepath}
                        )
                        nvram_e.attrib["type"] = nvram_type
                    else:
                        nvram_e.text = nvram_filepath
                    changed = True
                else:
                    print(
                        f"Error getting SP_UID for volume {img}",
                        file=sys.stderr,
                    )
                    changed = False
        else:
            system_ds_e: Optional[ET.Element] = None
            system_ds_e = root.find(".//one:vm/one:system_datastore", ns)
            if system_ds_e is None or system_ds_e.text is None:
                print(
                    'Error in domain xml: missing'
                    ' "metadata/one/system_datastore" element',
                    file=sys.stderr,
                )
                changed = False
            else:
                system_ds: str = str(system_ds_e.text)
                if nvram_file == "":
                    if "template" not in nvram_attr:
                        print(
                            'Error in <T_OS_NVRAM>: empty nvram file'
                            ' and missing "template" attribute',
                            file=sys.stderr,
                        )
                        changed = False
                    nvram_file = nvram_attr["template"].split("/")[-1]
                nvram_filepath = f"{system_ds}/{nvram_file.split('/')[-1]}"
                if nvram_type is not None:
                    source = "file"
                    if nvram_type == "block":
                        source = "dev"
                    nvram_source_e = ET.SubElement(
                        nvram_e, "source", {source: nvram_filepath}
                    )
                    nvram_e.attrib["type"] = nvram_type
                else:
                    nvram_e.text = nvram_filepath
                    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
