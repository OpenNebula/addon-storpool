#!/usr/bin/env python

# -------------------------------------------------------------------------- #
# Copyright 2015-2017, StorPool (storpool.com)                               #
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

#
# Credits: Todor Tanev <tt@storpool.com>
#
# vmTweakHypervEnlightenments.py <XMLfile>
#
# add the following line after cat >$domain in remotes/vmm/kvm/deploy
#  "$(dirname $0)/vmTweakHypervEnlightenments.py" "$domain"


from sys import argv
import syslog

dbg = 0
thrnum = u'1'

if dbg:
	syslog.openlog('vmTweakVirtioHypervEnlightenments.py', syslog.LOG_PID)

try:
	import lxml.etree as ET
except ImportError:
	raise RuntimeError("lxml Python module not found! Install from distribution package or pip install lxml")

xmlFile = argv[1]

et = ET.parse(xmlFile, ET.XMLParser(strip_cdata=False,remove_blank_text=True))

# ugly but working
domain = et.getroot()[0].getparent()

vm_name = et.find(".//name").text

for i in range(len(domain)):
	if domain[i].tag == 'clock':
		clock = domain[i]

# add iothreads
iothreads = ET.Element("iothreads")
iothreads.text = thrnum
domain.append(iothreads)

# configure all drives to use thread 1
try:
	alldevices = [ i for i in domain if i.tag == 'devices' ][0]
	# filter only dev="vd...
	drives = [ j for j in alldevices if j.tag == 'disk' and [l for l in j if 'dev="vd' in ET.tostring(l)]]
	for dev in drives:
		if dev.tag == 'disk':
			# loop on all elements
			for el in dev:
				 if el.tag == 'driver':
					for e in el.items():
						# check if io=native already set
						if e[0] == 'io' and e[1] == 'native':
							# tweak iothread for this device
							el.set('iothread', thrnum)
except IndexError:
	# no devices section found
	pass

conf = ET.Element('driver', iothread = thrnum)
controllers = [ c for c in domain.findall(".//controller") if 'model="virtio-scsi"' in ET.tostring(c) ]
for controller in controllers:
	try:
		driver = [ e for e in controller if e.tag == 'driver'][0]
		driver.set('iothread', thrnum)
		if 'queues' in driver.keys():
			vcpu = domain.find('.//vcpu').text
			driver.set('queues', vcpu)
	except IndexError:
		controller.append(conf)
if not controllers:
	# get first <devices>
	devices = domain.findall(".//devices")[0]
	controller=(ET.Element('controller', type = 'scsi', index = '0', model = 'virtio-scsi'))
	controller.append(conf)
	devices.append(controller)

# It is possible to recognize windows VMs by the availability of /domain/featrues/hyperv entry
if et.find(".//hyperv") is not None:
	try:
		if not ET.iselement(clock):
			pass
	except NameError:
		clock = ET.Element("clock", offset = 'utc')
		domain.append(clock)
	
	# improve clock settings for windows based hosts
	clock.append(ET.Element("timer", name = 'hypervclock', present = "yes"))
	clock.append(ET.Element("timer", name = 'rtc', tickpolicy = 'catchup'))
	clock.append(ET.Element("timer", name = 'pit', tickpolicy = 'delay'))
	clock.append(ET.Element("timer", name = 'hpet', present = 'no'))
	clock.append(ET.Element("timer", name = 'hypervclock', present = 'yes'))

#with open('{0}-{1}.XML'.format(xmlFile,vm_name), 'w') as d:
#	d.write(ET.tostring(domain, pretty_print = True))

et.write(xmlFile,pretty_print=True)
