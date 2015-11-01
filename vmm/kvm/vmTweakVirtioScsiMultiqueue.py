#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015, StorPool (storpool.com)                                    #
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

# vmTweakVirtioScsiQueues.py <XMLfile> <nQueues>

from sys import argv,exit

try:
    import lxml.etree as ET
except ImportError:
    raise RuntimeError("lxml Python module not found! Install from distribution package ot pip install lxml")


xmlFile = argv[1]
nQueues = argv[2]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

# ugly but working
domain = et.getroot()[0].getparent()

doExit = 1

did = 0
disks = et.findall(".//disk")
for disk in disks:
	if disk.get('device') == 'disk':
		if disk.get('type') == 'block':
			target = disk.findall(".//target")
			for e in target:
				if e.get('dev')[0:2] == 'sd':
					doExit = 0
		did += 1

if doExit:
	print "no sdX"
	exit(0)

controllers = et.findall(".//controller")
for controller in controllers:
	#<controller type="scsi" index="0" model="virtio-scsi">
	if controller.get('type') == 'scsi':
		if controller.get('model') == 'virtio-scsi':
			doExit = 1
			driver = controller.findall(".//driver")
			for e in driver:
				# <driver queues="1" />
				e.set('queues',"{0}".format(nQueues))
			else:
				driver = ET.SubElement(controller, "driver")
				driver.set('queues',"{0}".format(nQueues))

if doExit:
	et.write(xmlFile,pretty_print=True)
	exit(0)

cid = 0
controller = ET.Element("controller")
controller.set('type','scsi')
controller.set('index',"{0}".format(cid))
controller.set('model','virtio-scsi')

driver = ET.SubElement(controller, "driver")
driver.set('queues',"{0}".format(nQueues))

domain.append(controller)

et.write(xmlFile,pretty_print=True)
