#!/usr/bin/env python

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

# vmTweakVirtioScsiQueues.py <XMLfile> [<nQueues>]

from sys import argv,exit
import syslog

dbg = 1

if dbg:
	syslog.openlog('vmTweakVirtioScsiMultiqueue.py', syslog.LOG_PID)

try:
	import lxml.etree as ET
except ImportError:
	raise RuntimeError("lxml Python module not found! Install from distribution package or pip install lxml")

nQueues = None

xmlFile = argv[1]
if len(argv) == 3:
	nQueues = argv[2]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

vm_name = et.find(".//name").text

doExit = 1
diskId = -1
disks = et.findall(".//disk")
for disk in disks:
	if disk.get('device') == 'disk':
		diskId += 1
		if disk.get('type') == 'block':
			disk_target = disk.findall(".//target")
			for e in disk_target:
				target_dev = e.get('dev')
				if target_dev[0:2] == 'sd':
					doExit = 0
					if dbg:
						syslog.syslog(syslog.LOG_INFO, "VM {0} dev {1} is disk.{2}".format(vm_name,target_dev,diskId))

if doExit:
	if dbg:
		syslog.syslog(syslog.LOG_INFO, "VM {0} has no 'sd' prefixed devices".format(vm_name))
	exit(0)

controller_id = 0
controllers = et.findall(".//controller")
for controller in controllers:
	#<controller type="scsi" index="0" model="virtio-scsi">
	if controller.get('type') == 'scsi':
		conteroller_id += 1
		if controller.get('model') == 'virtio-scsi':
			doExit = 1
			driver = controller.findall(".//driver")
			for e in driver:
				if dbg:
					syslog.syslog(syslog.LOG_INFO, "VM {0} setting queues={1}>".format(vm_name,nQueues))
				# <driver queues="1" />
				if nQueues != None:
					e.set('queues',"{0}".format(nQueues))
			else:
				if nQueues != None:
					if dbg:
						syslog.syslog(syslog.LOG_INFO, "VM {0} adding driver with queues={1}>".format(vm_name,nQueues))
					driver = ET.SubElement(controller, "driver")
					driver.set('queues',"{0}".format(nQueues))

if doExit:
	et.write(xmlFile,pretty_print=True)
	exit(0)

controller = ET.Element("controller")
controller.set('type','scsi')
controller.set('index',"{0}".format(controller_id))
controller.set('model','virtio-scsi')

if nQueues != None:
	driver = ET.SubElement(controller, "driver")
	driver.set('queues',"{0}".format(nQueues))

devices = et.findall(".//devices")[0]
devices.append(controller)
if dbg:
	syslog.syslog(syslog.LOG_INFO, "VM {0} adding virtio-scsi controller with queues={1}".format(vm_name,nQueues))
et.write(xmlFile,pretty_print=True)
