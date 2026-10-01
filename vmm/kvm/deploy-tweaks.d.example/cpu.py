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
import re
import sys
from xml.etree import ElementTree as ET

ns = {
    'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
    'one': "http://opennebula.org/xmlns/libvirt/1.0",
}

MODES: Tuple[str, ...] = (
    'custom', 'host-model', 'host-passthrough', 'maximum')
DROP_MODEL: Tuple[str, ...] = ('host-model', 'host-passthrough', 'maximum')
CHECKS: Tuple[str, ...] = ('none', 'partial', 'full')
MATCHES: Tuple[str, ...] = ('minimum', 'exact', 'strict')
POLICIES: Tuple[str, ...] = (
    'force', 'require', 'optional', 'disable', 'forbid')
FALLBACKS: Tuple[str, ...] = ('allow', 'forbid')
CACHE_MODES: Tuple[str, ...] = ('emulate', 'passthrough', 'disable')
ADDR_MODES: Tuple[str, ...] = ('emulate', 'passthrough')
FEATURE_NAME = re.compile(r'^[a-zA-Z0-9\-_\.]+$')
YES: Tuple[str, ...] = ('1', 'y', 'yes', 'on', 'enable', 'enabled')


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
    print(f"Error in cpu: {msg}", file=sys.stderr)
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


def choice(tag: str, text: str, allowed: Tuple[str, ...]) -> str:
    if text not in allowed and text.lower() != 'delete':
        fatal(f"{tag} '{text}' is not one of {', '.join(allowed)}")
    return text


def positive_int(tag: str, text: str) -> int:
    if not text.isdigit() or int(text) < 1:
        fatal(f"{tag} '{text}' is not a positive integer")
    return int(text)


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


def ensure_cpu() -> ET.Element:
    cpu_e: Optional[ET.Element] = root.find('./cpu')
    if cpu_e is None:
        cpu_e = ET.SubElement(root, 'cpu')
    return cpu_e


def remove_named(parent: ET.Element, tag: str) -> None:
    for child in list(parent.findall(tag)):
        parent.remove(child)


xmlDomain: str = sys.argv[1]
doc: ET.ElementTree = ET.parse(xmlDomain)
root: ET.Element = doc.getroot()

xmlVm: str = sys.argv[2]
vm_e: ET.ElementTree = ET.parse(xmlVm)
vm: ET.Element = vm_e.getroot()

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

cpu_mode: Optional[str] = template_text('T_CPU_MODE')
cpu_model: Optional[str] = template_text('T_CPU_MODEL')
cpu_vendor: Optional[str] = template_text('T_CPU_VENDOR')
cpu_check: Optional[str] = template_text('T_CPU_CHECK')
cpu_match: Optional[str] = template_text('T_CPU_MATCH')
cpu_features: Optional[str] = template_text('T_CPU_FEATURES')
cpu_cache: Optional[str] = template_text('T_CPU_CACHE')
cpu_addr: Optional[str] = template_text('T_CPU_MAXPHYSADDR')
sockets_text: Optional[str] = template_text('T_CPU_SOCKETS')
dies_text: Optional[str] = template_text('T_CPU_DIES')
clusters_text: Optional[str] = template_text('T_CPU_CLUSTERS')
threads_text: Optional[str] = template_text('T_CPU_THREADS')
mem_access: Optional[str] = template_text('T_CPU_NUMA_MEMACCESS')
discard: Optional[str] = template_text('T_CPU_NUMA_DISCARD')
alt_text: Optional[str] = template_text('T_CPU_ALT_NUMA')

if cpu_mode is not None:
    choice('T_CPU_MODE', cpu_mode, MODES)
if cpu_check is not None:
    choice('T_CPU_CHECK', cpu_check, CHECKS)
if cpu_match is not None:
    choice('T_CPU_MATCH', cpu_match, MATCHES)

if (cpu_mode in DROP_MODEL and cpu_model is not None
        and cpu_model.lower() != 'delete'):
    fatal(f"T_CPU_MODEL cannot be combined with mode '{cpu_mode}'")

model_name: Optional[str] = None
model_fallback: Optional[str] = None
if cpu_model is not None and cpu_model.lower() != 'delete':
    if ':' in cpu_model:
        model_name, model_fallback = cpu_model.split(':', 1)
    else:
        model_name = cpu_model
    if model_name == '':
        fatal('T_CPU_MODEL is empty')
    if model_fallback is not None and model_fallback not in FALLBACKS:
        fatal(f"T_CPU_MODEL fallback '{model_fallback}' is not allow or forbid")

feature_order: List[str] = []
feature_policy: Dict[str, Optional[str]] = {}
if cpu_features is not None:
    for item in cpu_features.split(','):
        item = item.strip()
        if item == '':
            continue
        if ':' in item:
            name, policy = item.split(':', 1)
            policy = policy.strip()
            if policy not in POLICIES:
                fatal(f"unknown feature policy '{policy}'")
        else:
            name, policy = item, None
        name = name.strip()
        if FEATURE_NAME.match(name) is None:
            fatal(f"feature name '{name}' is not a libvirt CPU feature name")
        if name not in feature_policy:
            feature_order.append(name)
        feature_policy[name] = policy

cache_mode: Optional[str] = None
cache_level: Optional[str] = None
if cpu_cache is not None:
    cache_mode, cache_attrs = split_spec(cpu_cache)
    if cache_mode not in CACHE_MODES:
        fatal(f"T_CPU_CACHE '{cache_mode}' is not emulate, passthrough, or disable")
    unknown = [key for key in cache_attrs if key != 'level']
    if unknown:
        fatal(f"unknown cache attribute '{unknown[0]}'")
    cache_level = cache_attrs.get('level')
    if cache_level is not None and cache_level not in ('1', '2', '3'):
        fatal(f"cache level '{cache_level}' is not 1, 2, or 3")
    if cache_mode == 'emulate' and cache_level != '3':
        fatal('cache mode emulate requires level=3')
    if cache_mode == 'passthrough':
        effective: Optional[str] = cpu_mode
        if effective == 'delete':
            effective = None
        if effective is None:
            existing_cpu: Optional[ET.Element] = root.find('./cpu')
            if existing_cpu is not None:
                effective = existing_cpu.get('mode')
        if effective not in ('host-passthrough', 'maximum'):
            fatal('cache mode passthrough requires mode host-passthrough or maximum')

addr_mode: Optional[str] = None
addr_bits: Optional[str] = None
addr_limit: Optional[str] = None
if cpu_addr is not None:
    addr_mode, addr_attrs = split_spec(cpu_addr)
    if addr_mode not in ADDR_MODES:
        fatal(f"T_CPU_MAXPHYSADDR '{addr_mode}' is not emulate or passthrough")
    unknown_addr = [key for key in addr_attrs if key not in ('bits', 'limit')]
    if unknown_addr:
        fatal(f"unknown maxphysaddr attribute '{unknown_addr[0]}'")
    addr_bits = addr_attrs.get('bits')
    addr_limit = addr_attrs.get('limit')
    if addr_mode == 'emulate':
        if addr_bits is None:
            fatal('maxphysaddr mode emulate requires bits')
        if addr_limit is not None:
            fatal('maxphysaddr limit is only supported for mode passthrough')
        positive_int('maxphysaddr bits', addr_bits)
    else:
        if addr_bits is not None:
            fatal('maxphysaddr bits cannot be used with mode passthrough')
        if addr_limit is not None:
            positive_int('maxphysaddr limit', addr_limit)

sockets: int = 0
if sockets_text is not None:
    if not sockets_text.isdigit():
        fatal(f"T_CPU_SOCKETS '{sockets_text}' is not a non-negative integer")
    sockets = int(sockets_text)

if sockets == 0 and (dies_text is not None or clusters_text is not None):
    fatal('T_CPU_DIES and T_CPU_CLUSTERS require T_CPU_SOCKETS')
if sockets == 0 and (mem_access is not None or discard is not None):
    fatal('T_CPU_NUMA_MEMACCESS and T_CPU_NUMA_DISCARD require T_CPU_SOCKETS')

dies: int = 1
clusters: int = 1
threads: int = 1
if sockets > 0:
    if dies_text is not None:
        dies = positive_int('T_CPU_DIES', dies_text)
    if clusters_text is not None:
        clusters = positive_int('T_CPU_CLUSTERS', clusters_text)
    if threads_text is not None:
        threads = positive_int('T_CPU_THREADS', threads_text)
    if mem_access is not None and mem_access not in ('shared', 'private'):
        fatal(f"T_CPU_NUMA_MEMACCESS '{mem_access}' is not shared or private")
    if discard is not None and discard not in ('yes', 'no'):
        fatal(f"T_CPU_NUMA_DISCARD '{discard}' is not yes or no")

changed: bool = False

if cpu_mode is not None or cpu_model is not None or cpu_check is not None \
        or cpu_match is not None or cpu_features is not None \
        or cpu_cache is not None or cpu_addr is not None or cpu_vendor is not None \
        or sockets > 0:
    cpu_e: ET.Element = ensure_cpu()
else:
    cpu_e = root.find('./cpu')  # type: ignore[assignment]

if cpu_mode is not None:
    if cpu_mode.lower() == 'delete':
        if cpu_e is not None and cpu_e.get('mode') is not None:
            del cpu_e.attrib['mode']
            changed = True
    else:
        cpu_e.set('mode', cpu_mode)
        changed = True
        if cpu_mode in DROP_MODEL:
            remove_named(cpu_e, 'model')
        elif cpu_model is None:
            remove_named(cpu_e, 'model')

if cpu_model is not None and not (cpu_mode in DROP_MODEL):
    if cpu_model.lower() == 'delete':
        if cpu_e is not None and cpu_e.find('model') is not None:
            remove_named(cpu_e, 'model')
            changed = True
    else:
        model_e: Optional[ET.Element] = cpu_e.find('model')
        if model_e is None:
            model_e = ET.SubElement(cpu_e, 'model')
        model_e.text = model_name
        if model_fallback is not None:
            model_e.set('fallback', model_fallback)
        elif model_e.get('fallback') is not None:
            del model_e.attrib['fallback']
        changed = True

if cpu_vendor is not None:
    if cpu_e is None or cpu_e.find('model') is None:
        fatal('T_CPU_VENDOR requires a cpu model')
    vendor_e: Optional[ET.Element] = cpu_e.find('vendor')
    if vendor_e is None:
        vendor_e = ET.SubElement(cpu_e, 'vendor')
    vendor_e.text = cpu_vendor
    changed = True

if cpu_check is not None:
    if cpu_check.lower() == 'delete':
        if cpu_e is not None and cpu_e.get('check') is not None:
            del cpu_e.attrib['check']
            changed = True
    else:
        cpu_e.set('check', cpu_check)
        changed = True

if cpu_match is not None:
    if cpu_match.lower() == 'delete':
        if cpu_e is not None and cpu_e.get('match') is not None:
            del cpu_e.attrib['match']
            changed = True
    else:
        cpu_e.set('match', cpu_match)
        changed = True

if cpu_features is not None:
    remove_named(cpu_e, 'feature')
    for name in feature_order:
        attrs: Dict[str, str] = {'name': name}
        policy = feature_policy[name]
        if policy is not None:
            attrs['policy'] = policy
        ET.SubElement(cpu_e, 'feature', attrs)
    changed = True

if sockets > 0:
    vcpu_e: Optional[ET.Element] = root.find('./vcpu')
    if vcpu_e is None or vcpu_e.text is None or not vcpu_e.text.strip().isdigit():
        fatal('T_CPU_SOCKETS requires a numeric vcpu count')
    vcpu: int = int(vcpu_e.text.strip())
    vcpu_current: int = vcpu
    if vcpu_e.get('current') is not None:
        vcpu_current = int(vcpu_e.get('current') or '0')
    per_socket: int = sockets * dies * clusters * threads
    if per_socket == 0 or vcpu % per_socket != 0:
        fatal('CPU topology does not match the vcpu count')
    cores: int = vcpu // per_socket
    if cores < 1:
        fatal('CPU topology does not match the vcpu count')

    memory_e: Optional[ET.Element] = root.find('./memory')
    if memory_e is None or memory_e.text is None or not memory_e.text.strip().isdigit():
        fatal('T_CPU_SOCKETS requires numeric memory')
    memory: int = int(memory_e.text.strip())
    if memory % sockets != 0:
        fatal('memory is not divisible by T_CPU_SOCKETS')
    cell_memory: int = memory // sockets
    unit: str = memory_e.get('unit') or 'KiB'

    remove_named(cpu_e, 'topology')
    remove_named(cpu_e, 'numa')
    topo: Dict[str, str] = {'sockets': str(sockets)}
    if dies != 1:
        topo['dies'] = str(dies)
    if clusters != 1:
        topo['clusters'] = str(clusters)
    topo['cores'] = str(cores)
    topo['threads'] = str(threads)
    ET.SubElement(cpu_e, 'topology', topo)
    numa_e: ET.Element = ET.SubElement(cpu_e, 'numa')

    alt_numa: bool = alt_text is not None and alt_text.lower() in YES
    cpumap: Dict[int, List[str]] = {}
    scount: int = 0
    for idx in range(vcpu):
        if scount not in cpumap:
            cpumap[scount] = []
        cpumap[scount].append(str(idx))
        scount = (scount + 1) % sockets
    socket_cpus: int = vcpu // sockets
    for idx in range(sockets):
        cpu_start: int = socket_cpus * idx
        cpu_end: int = socket_cpus * (idx + 1) - 1
        cpus: str = f"{cpu_start}-{cpu_end}"
        if alt_numa and threads == 1 and cpumap[idx]:
            cpus = ','.join(cpumap[idx])
        cell: Dict[str, str] = {
            'id': str(idx),
            'cpus': cpus,
            'memory': str(cell_memory),
            'unit': unit,
        }
        if mem_access is not None:
            cell['memAccess'] = mem_access
        if discard is not None:
            cell['discard'] = discard
        ET.SubElement(numa_e, 'cell', cell)

    for old in list(root.findall('vcpus')):
        root.remove(old)
    vcpus_e: ET.Element = ET.SubElement(root, 'vcpus')
    enabled: str = 'yes'
    hotpluggable: str = 'no'
    for idx in range(vcpu):
        if idx >= vcpu_current:
            enabled = 'no'
        ET.SubElement(vcpus_e, 'vcpu', {
            'id': str(idx),
            'enabled': enabled,
            'hotpluggable': hotpluggable,
        })
        hotpluggable = 'yes'
    changed = True

if cpu_cache is not None:
    remove_named(cpu_e, 'cache')
    cache_attrs_out: Dict[str, str] = {}
    if cache_level is not None:
        cache_attrs_out['level'] = cache_level
    cache_attrs_out['mode'] = cache_mode or ''
    ET.SubElement(cpu_e, 'cache', cache_attrs_out)
    changed = True

if cpu_addr is not None:
    remove_named(cpu_e, 'maxphysaddr')
    addr_attrs_out: Dict[str, str] = {'mode': addr_mode or ''}
    if addr_bits is not None:
        addr_attrs_out['bits'] = addr_bits
    if addr_limit is not None:
        addr_attrs_out['limit'] = addr_limit
    ET.SubElement(cpu_e, 'maxphysaddr', addr_attrs_out)
    changed = True

if changed:
    indent(root)
    doc.write(xmlDomain)
