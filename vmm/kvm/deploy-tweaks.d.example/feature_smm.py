#!/usr/bin/env python3

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

from __future__ import print_function
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

def get_attributes(attr):
    ret = {}
    for a in attr.split():
        k,v = a.split('=')
        ret[k] = v
    return ret

def parse_features(features):
    ret = {}
    for feat in features.split(';'):
        name,value,attributes = feat.split(':')
        ret[name] = {'val':value,'attr':get_attributes(attributes)}
    return ret

xmlVm = argv[2]
vm_element = ET.parse(xmlVm)
vm = vm_element.getroot()

xmlDomain = argv[1]
doc = ET.parse(xmlDomain)
root = doc.getroot()

changed = 0

for prefix, uri in ns.items():
    ET.register_namespace(prefix, uri)

# merge all <features> elements in first one
features_e = None
features_elements = root.findall('.//features')
features_len = len(features_elements)
if features_len > 0:
    features_e = features_elements[0]
    if features_len > 1:
        for features_element in features_elements[1:]:
            for features_child in features_element.getchildren():
                features_e.append(features_child)
                features_element.remove(features_child)
            root.remove(features_element)
            changed = 1
else:
    features_e = ET.SubElement(root, 'features', {})

t_smm_e = vm.find('.//USER_TEMPLATE/T_FEATURE_SMM')
if t_smm_e is not None:
    value, attr = t_smm_e.text.split(':')
    smm_e = features_e.find('./smm')
    if smm_e is not None:
        features_e.remove(smm_e)
    smm_e = ET.SubElement(features_e, 'smm', get_attributes(attr))
#    if value != '':
#        f_e.text = '{}'.format(value)
    changed = 1
    t_tseg_e = vm.find('.//USER_TEMPLATE/T_FEATURE_SMM_TSEG')
    if t_tseg_e is not None:
        value, attr = t_tseg_e.text.split(':')
        tseg_e = ET.SubElement(smm_e, 'tseg', get_attributes(attr))
        if value == '':
            value = 0
        tseg_e.text = '{}'.format(value)

if changed:
    indent(root)
    doc.write(xmlDomain)
