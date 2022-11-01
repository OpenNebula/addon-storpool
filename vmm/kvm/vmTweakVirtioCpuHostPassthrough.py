#!/usr/bin/env python

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

# vmTweakVirtioCpuHostPassthrough.py <XMLfile>
#
# add the following line after cat >$domain in remotes/vmm/kvm/deploy
#  "$(dirname $0)/vmTweakVirtioCpuHostPassthrough.py" "$domain"

from sys import argv
import syslog

dbg = 0

if dbg:
	syslog.openlog('vmTweakVirtioCpuHostPassthrough.py', syslog.LOG_PID)

try:
	import lxml.etree as ET
except ImportError:
	raise RuntimeError("lxml Python module not found! Install from distribution package or pip install lxml")

xmlFile = argv[1]
if len(argv) == 3:
	nQueues = argv[2]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

domain = et.getroot()[0].getparent()

cpu = ET.Element("cpu")

cpu.set('mode','host-passthrough')

domain.append(cpu)

et.write(xmlFile,pretty_print=True)
