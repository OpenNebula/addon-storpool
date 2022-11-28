#!/usr/bin/env python3

# -------------------------------------------------------------------------- #
# Copyright 2015-2022, StorPool (storpool.com)                               #
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

from __future__ import print_function
import os
from sys import argv, exit, stderr
from xml.etree import ElementTree as ET

ns = {'qemu': 'http://libvirt.org/schemas/domain/qemu/1.0',
       'one': "http://opennebula.org/xmlns/libvirt/1.0"
     }

def indent(elem, level=0, ind="  "):
    i = "\n" + level * ind
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

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()


xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)


try:
    memory = int(root.find('./memory').text)
except Exception as e:
    print('Cant get memory info from domain XML "{0}"'.format(e), file=stderr)
    exit(1)


vcpu_element = root.find('./vcpu')
if vcpu_element is None:
    vcpu_element = ET.SubElement(root, 'vcpu')
    vcpu_element.text = '1'
vcpu = int(vcpu_element.text)

#if vcpu%2 > 0:
#    print("VCPU % 2 = {v} != 0".format(v=vcpu%2), file=stderr)
#    exit(1)

cpu = root.find('./cpu')
if cpu is None:
    cpu = ET.SubElement(root, 'cpu')


threads = int(os.getenv('T_CPU_THREADS', 1))
cpu_threads = vm.find('.//USER_TEMPLATE/T_CPU_THREADS')
if cpu_threads is not None:
    try:
        threads = int(cpu_threads.text)
        if threads < 1:
            threads = 1
    except Exception as e:
        print("USER_TEMPLATE/CPU_THREADS is '{0}' Error:{1}".format(
                                        cpu_threads.text,e),file=stderr)
        exit(1)

sockets = int(os.getenv('T_CPU_SOCKETS', 0))
cpu_sockets = vm.find('.//USER_TEMPLATE/T_CPU_SOCKETS')
if cpu_sockets is not None:
    try:
        sockets = int(cpu_sockets.text)
    except Exception as e:
        print("USER_TEMPLATE/CPU_SOCKETS is '{0}' Error:{1}".format(
                                        cpu_sockets.text,e),file=stderr)

if sockets > 0:
    socket_cpu_threads = int(vcpu / sockets)
    socket_cores = int(socket_cpu_threads / threads)

    topology = ET.SubElement(cpu, 'topology', {
            'sockets' : '{0}'.format(sockets),
              'cores' : '{0}'.format(socket_cores),
            'threads' : '{0}'.format(threads),
        })

    changed = 1

    numa = ET.SubElement(cpu, 'numa')
    for i in range(sockets):
        cpuStart = socket_cpu_threads * i
        cpuEnd = (socket_cpu_threads * (i+1)) -1
        cpuMem = int(memory / sockets)
        cell = ET.SubElement(numa, 'cell', {
                'id' : '{0}'.format(i),
              'cpus' : '{0}-{1}'.format(cpuStart, cpuEnd),
            'memory' : '{0}'.format(cpuMem),
            })

cpu_features = os.getenv('T_CPU_FEATURES', None)
vm_cpu_features = vm.find('.//USER_TEMPLATE/T_CPU_FEATURES')
if vm_cpu_features is not None:
    cpu_features = vm_cpu_features.text
if cpu_features is not None:
    for f in cpu_features.split(','):
        arr = f.split(':')
        name = arr[0]
        feature = ET.SubElement(cpu, 'feature' , {
                'name' : name
            })
        if len(arr) > 1:
            if arr[1] in ['force','require','optional','disable','forbid']:
                feature.set('policy', arr[1])
        changed = 1


cpu_model = os.getenv('T_CPU_MODEL', None)
vm_cpu_model = vm.find('.//USER_TEMPLATE/T_CPU_MODEL')
if vm_cpu_model is not None:
    cpu_model = vm_cpu_model.text
if cpu_model is not None:
    model = cpu.find('./model')
    if cpu_model.lower() == 'delete':
        if model is not None:
            cpu.remove(model)
            changed = 1
    else:
        m = cpu_model.split(':')
        cpu_model = m[0]
        fallback = None
        if model is None:
            model = ET.SubElement(cpu, 'model')
        model.text = cpu_model
        if len(m) > 1:
            fallback = m[1]
        if fallback is not None:
            model.set('fallback', fallback)
        else:
            if model.get('fallback') is not None:
                del model.atrrib['fallback']
        changed = 1

cpu_vendor = os.getenv('T_CPU_VENDOR', None)
vm_cpu_vendor = vm.find('.//USER_TEMPLATE/T_CPU_VENDOR')
if vm_cpu_vendor is not None:
    cpu_vendor = vm_cpu_vendor.text
if cpu_vendor is not None:
    model = cpu.find('./model')
    if model is not None:
        vendor = cpu.find('.//vendor')
        if vendor is None:
            vendor = ET.SubElement(cpu, 'vendor')
        vendor.text = cpu_vendor
        changed = 1

cpu_check = os.getenv('T_CPU_CHECK', None)
vm_cpu_check = vm.find('.//USER_TEMPLATE/T_CPU_CHECK')
if vm_cpu_check is not None:
    cpu_check = vm_cpu_check.text
if cpu_check is not None:
    if cpu_check.lower() == 'delete':
        if cpu.get('check') is not None:
            del cpu.attrib['check']
            changed = 1
    else:
        if cpu_check in ['none','partial','full']:
            cpu.set('check', cpu_check)
            changed = 1

cpu_match = os.getenv('T_CPU_MATCH', None)
vm_cpu_match = vm.find('.//USER_TEMPLATE/T_CPU_MATCH')
if vm_cpu_match is not None:
    cpu_match = vm_cpu_match.text
if cpu_match is not None:
    if cpu_match.lower() == 'delete':
        if cpu.get('match') is not None:
            del cpu.attrib['match']
            changed = 1
    else:
        if cpu_match in ['minimum','exact','strict']:
            cpu.set('match', cpu_match)
            changed = 1

cpu_mode = os.getenv('T_CPU_MODE', None)
vm_cpu_mode = vm.find('.//USER_TEMPLATE/T_CPU_MODE')
if vm_cpu_mode is not None:
    cpu_mode = vm_cpu_mode.text
if cpu_mode is not None:
    if cpu_mode.lower() == 'delete':
        if cpu.get('mode') is not None:
            del cpu.attrib['mode']
            changed = 1
    else:
        if cpu_match in ['custom','host-model','host-passthrough']:
            cpu.set('mode', cpu_mode)
            changed = 1

if changed:
    indent(root)
    doc.write(xmlDomain)
