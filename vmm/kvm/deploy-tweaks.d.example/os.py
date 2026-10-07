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
from typing import Optional, Dict, List, Tuple
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
        if "=" not in a:
            fatal(f"bad attribute '{a}'")
        k, v = a.split("=", 1)
        ret[k] = v
    return ret


def fatal(msg: str) -> None:
    """
    Report an error that must abort the deploy (deploy-tweaks treats exit
    code 2 as fatal) instead of silently deploying a domain without the
    requested UEFI setup.
    """
    print(f"Error in os: {msg}", file=sys.stderr)
    sys.exit(2)


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


YES_NO: Tuple[str, ...] = ("yes", "no")
LOADER_VALUES: Dict[str, Tuple[str, ...]] = {
    "readonly": YES_NO,
    "secure": YES_NO,
    "stateless": YES_NO,
    "type": ("rom", "pflash"),
    "format": ("raw", "qcow2"),
}
NVRAM_ATTRS: Tuple[str, ...] = ("template", "templateFormat", "type", "format")
FIRMWARE_FEATURES: Tuple[str, ...] = ("secure-boot", "enrolled-keys")
FeatureList = List[Tuple[str, str]]


def split_once(text: str) -> Tuple[str, str]:
    if ":" in text:
        head, rest = text.split(":", 1)
        return head, rest
    return text, ""


def check_choice(kind: str, key: str, value: str, choices: Tuple[str, ...]) -> None:
    if value not in choices:
        fatal(f"{kind} {key} '{value}' must be {' or '.join(choices)}")


def parse_firmware(text: str) -> FeatureList:
    found: FeatureList = []
    index: Dict[str, int] = {}
    for item in text.split():
        if "=" not in item:
            fatal(f"bad attribute '{item}'")
        key, value = item.split("=", 1)
        if key not in FIRMWARE_FEATURES:
            fatal(f"unknown firmware feature '{key}'")
        check_choice("firmware feature", key, value, YES_NO)
        if key in index:
            found[index[key]] = (key, value)
        else:
            index[key] = len(found)
            found.append((key, value))
    return found


def apply_os_attrs(os_element: ET.Element, attrs: Dict[str, str]) -> bool:
    touched: bool = False
    for key, val in attrs.items():
        if val == "":
            if key in os_element.attrib:
                del os_element.attrib[key]
                touched = True
            continue
        if os_element.get(key) != val:
            os_element.set(key, val)
            touched = True
    return touched


def apply_firmware(os_element: ET.Element, features: FeatureList) -> bool:
    desired: FeatureList = features
    element: Optional[ET.Element] = os_element.find("./firmware")
    current: FeatureList = []
    if element is not None:
        for child in list(element):
            if child.tag != "feature":
                current = []
                break
            current.append((child.get("name") or "", child.get("enabled") or ""))
    if element is not None and current == desired:
        return False
    if element is not None:
        os_element.remove(element)
    element = ET.SubElement(os_element, "firmware")
    for name, enabled in desired:
        feat: ET.Element = ET.SubElement(element, "feature")
        feat.set("enabled", enabled)
        feat.set("name", name)
    return True


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
loader_file: Optional[str] = None
nvram_file: Optional[str] = None
firmware_features: Optional[FeatureList] = None

xpath: str = ".//USER_TEMPLATE/T_OS"
t_os_e: Optional[ET.Element] = vm.find(xpath)
if t_os_e is not None and t_os_e.text is not None and t_os_e.text.strip() != "":
    os_attr = get_attributes(t_os_e.text)
    for os_key, os_val in os_attr.items():
        if os_key != "firmware":
            fatal(f"unknown os attribute '{os_key}'")
        if os_val != "":
            check_choice("os", "firmware", os_val, ("bios", "efi"))

xpath = ".//USER_TEMPLATE/T_OS_LOADER"
os_loader_e: Optional[ET.Element] = vm.find(xpath)
if os_loader_e is not None and os_loader_e.text is not None:
    loader_file, loader_rest = split_once(os_loader_e.text)
    if loader_rest.strip():
        loader_attr = get_attributes(loader_rest)
    for loader_key, loader_val in loader_attr.items():
        if loader_key not in LOADER_VALUES:
            fatal(f"unknown loader attribute '{loader_key}'")
        check_choice("loader", loader_key, loader_val, LOADER_VALUES[loader_key])

xpath = ".//USER_TEMPLATE/T_OS_NVRAM"
os_nvram_e: Optional[ET.Element] = vm.find(xpath)
if os_nvram_e is not None and os_nvram_e.text is not None:
    nvram_file, nvram_rest = split_once(os_nvram_e.text)
    if nvram_rest.strip():
        nvram_attr = get_attributes(nvram_rest)
    for nvram_key in nvram_attr:
        if nvram_key not in NVRAM_ATTRS:
            fatal(f"unknown nvram attribute '{nvram_key}'")
    nvram_type: Optional[str] = nvram_attr.get("type")
    nvram_format: Optional[str] = nvram_attr.get("format")
    template_format: Optional[str] = nvram_attr.get("templateFormat")
    nvram_legacy: bool = nvram_type == "legacy"
    if nvram_legacy:
        nvram_attr.pop("type", None)
        nvram_type = None
    elif nvram_type is not None:
        check_choice("nvram", "type", nvram_type, ("file", "block"))
    if nvram_format is not None:
        check_choice("nvram", "format", nvram_format, ("raw", "qcow2"))
    if template_format is not None:
        check_choice("nvram", "templateFormat", template_format, ("raw", "qcow2"))
    if nvram_file == "storpool":
        if nvram_format == "qcow2":
            fatal("storpool nvram format must be raw")
        if template_format is not None:
            fatal("storpool nvram does not take templateFormat")

if loader_attr.get("stateless") == "yes" and nvram_file is not None:
    fatal("stateless=yes cannot be combined with T_OS_NVRAM")

xpath = ".//USER_TEMPLATE/T_OS_FIRMWARE"
os_firmware_e: Optional[ET.Element] = vm.find(xpath)
if os_firmware_e is not None and os_firmware_e.text is not None and os_firmware_e.text.strip() != "":
    firmware_features = parse_firmware(os_firmware_e.text)

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
            changed = True
    if apply_os_attrs(os_e, os_attr):
        changed = True
else:
    os_e = ET.SubElement(root, "os", os_attr)
    if os_attr:
        changed = True

if firmware_features is not None and os_e.get("firmware") != "efi":
    fatal("T_OS_FIRMWARE requires firmware=efi")

if loader_file is not None:
    loader_e: Optional[ET.Element] = os_e.find("./loader")
    if loader_e is not None:
        os_e.remove(loader_e)
    loader_e = ET.SubElement(os_e, "loader", loader_attr)
    loader_e.text = f"{loader_file}"
    changed = True

if nvram_file is not None:
    if nvram_file == "storpool":
        # type=block is the libvirt 8.5 form and the default. type=legacy
        # keeps the path as element text. type=file stays an override.
        kept: Dict[str, str] = {}
        if nvram_format is not None:
            kept["format"] = nvram_format
        nvram_attr = kept
        if nvram_type is None and not nvram_legacy:
            nvram_type = "block"

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
                fatal('missing "ID" element')
            else:
                vm_id: int = int(vm_id_e.text)
                img: str = f"{one_px}-sys-{vm_id}-NVRAM"
                sp_uid: str = get_spUid(img)
                if sp_uid == "":
                    fatal(f"volume {img} not found in the KV store")
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
                    changed = True
                else:
                    nvram_e.text = nvram_filepath
                    changed = True

if firmware_features is not None and apply_firmware(os_e, firmware_features):
    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
