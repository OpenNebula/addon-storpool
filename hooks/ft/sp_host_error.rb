#!/usr/bin/env ruby

# -------------------------------------------------------------------------- #
# Copyright 2015, StorPool (storpool.com)                                    #
#                                                                            #
# Portions copyright OpenNebula Project (OpenNebula.org), CG12 Labs          #
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

##############################################################################
# Script to migrate VM-s from failed host
#   Additional flags
#           -t how many times to loop in each state
#           -p <n> avoid resubmission if host comes
#                  back after n monitoring cycles
#           -f fencing-script.sh fence the failed node while script is working
##############################################################################

##############################################################################
# WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
#
# This script needs to fence the error host to prevent split brain VMs. You
# may use any fence mechanism and invoke it around L105, using host_name
#
# WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING! WARNING!
#############################################################################

ONE_LOCATION=ENV["ONE_LOCATION"]

if !ONE_LOCATION
    RUBY_LIB_LOCATION="/usr/lib/one/ruby"
    VMDIR="/var/lib/one"
    CONFIG_FILE="/var/lib/one/config"
else
    RUBY_LIB_LOCATION=ONE_LOCATION+"/lib/ruby"
    VMDIR=ONE_LOCATION+"/var"
    CONFIG_FILE=ONE_LOCATION+"/var/config"
end

$: << RUBY_LIB_LOCATION

require 'syslog'

require 'opennebula'
include OpenNebula

require 'getoptlong'

def splog(message)
    Syslog.open($0.split("/").last, Syslog::LOG_PID | Syslog::LOG_CONS) { |s| s.notice message }
end

if !(host_id=ARGV[0])
    exit -1
end

repeat = nil  # By default, don't wait for monitorization cycles"
max_count = 200
fencing_script = nil # For backward compatibility by default there is no fencing script

opts = GetoptLong.new(
            ['--pause',    '-p',GetoptLong::REQUIRED_ARGUMENT],
            ['--timeout',    '-t',GetoptLong::REQUIRED_ARGUMENT],
            ['--fencing-script',    '-f',GetoptLong::REQUIRED_ARGUMENT]
        )

begin
    opts.each do |opt, arg|
        case opt
            when '--pause'
                repeat = arg.to_i
            when '--timeout'
                max_count = arg.to_i
            when '--fencing-script'
                fencing_script = arg
        end
    end
rescue Exception => e
    exit(-1)
end

begin
    client = Client.new()
rescue Exception => e
    splog("unknown(#{host_id}) ERROR: Can't get Client object")
    puts "Error: #{e}"
    exit -1
end

# Retrieve hostname
host  =  OpenNebula::Host.new_with_id(host_id, client)
rc = host.info
if OpenNebula.is_error?(rc)
    splog("unknown(#{host_id}) ERROR: Can't get host info for host_id:#{host_id}")
    exit -1
end
host_name = host.name

hstate = host.state

if hstate != 3 and hstate != 5
    splog("#{host_name}(#{host_id}) END: Host is back (host.state:#{hstate})")
    exit 0
else
    splog("#{host_name}(#{host_id}) BEGIN: (host.state:#{hstate})")
end

if repeat
    # Retrieve host monitor interval
    monitor_interval = nil
    File.readlines(CONFIG_FILE).each{|line|
         monitor_interval = line.split("=").last.to_i if /MONITORING_INTERVAL/=~line
    }
    if monitor_interval
        1.upto(repeat) do |i|
            host.info
            hstate = host.state
            # If the host came back, exit! avoid duplicated VMs
            if hstate != 3 and hstate != 5
                splog("#{host_name}(#{host_id}) END: Host is back (host.state:#{hstate})")
                exit 0
            end
            splog("#{host_name}(#{host_id}) SLEEP: #{i}/#{repeat} sleep #{monitor_interval} (host.state:#{hstate})")
            # Sleep through the desired number of monitor interval
            sleep(monitor_interval)
        end
    else
        splog("#{host_name}(#{host_id}) ERROR: Can't get MONITORING_INTERVAL! (host.state:#{hstate})")
        exit -1
    end
end

# Loop through all vms
vms = VirtualMachinePool.new(client)
rc = vms.info_all
if OpenNebula.is_error?(rc)
    splog("#{host_name}(#{host_id}) ERROR: Can't get VM info")
    exit -1
end

state = "STATE=3"

vm_ids_array = vms.retrieve_elements("/VM_POOL/VM[#{state}]/HISTORY_RECORDS/HISTORY[HOSTNAME=\"#{host_name}\" and last()]/../../ID")

if vm_ids_array
    vmhash = Hash.new
    vm_ids_array.each do |vm_id|
        vm=OpenNebula::VirtualMachine.new_with_id(vm_id, client)
        vm.info
        vm_state = vm.state_str
        lcm_state = vm.lcm_state_str
        state =  "#{vm_state}/#{lcm_state}"
        if state == "ACTIVE/UNKNOWN"
            vmhash[vm_id] = Hash.new
            vmhash[vm_id]["vm"] = vm
            vmhash[vm_id]["state"] = state
            vmhash[vm_id]["prev_action"] = "none"
            vmhash[vm_id]["count"] = 0
            splog("#{host_name}(#{host_id}) ADD: VM #{vm_id} state #{state}")
        else
            splog("#{host_name}(#{host_id}) SKIP: VM #{vm_id} state #{state}")
        end
    end

    if vmhash.size == 0
        splog("#{host_name}(#{host_id}) END: No VM in ACTIVE/UNKNOWN state found")
        exit 0
    end

    # Begin game
    if fencing_script
        system({"FT_ACTION"=>"FENCE","FT_HOSTID"=>host_id,"FT_HOSTNAME"=>host_name}, fencing_script)
        splog("#{host_name}(#{host_id}) FENCE: script #{fencing_script} (#{$?})")
    end

    begin
        vmhash.each do |vm_id, vmh|
            vm = vmh["vm"]
            vm.info
            vm_state = vm.state_str
            lcm_state = vm.lcm_state_str
            state =  "#{vm_state}/#{lcm_state}"
            host.info
            hstate = host.state
            count = vmh["count"]
            prev_action = vmh["prev_action"]
            if state == vmhash[vm_id]["state"]
                splog("#{host_name}(#{host_id}) STATE: #{state} VM #{vm_id} pa:#{prev_action} count:#{count} host.state:#{hstate}")
                vmhash[vm_id]["count"] = 0 if count < max_count - 1
                if state == "ACTIVE/UNKNOWN" and prev_action != "resched"
                    n_state = "ACTIVE/BOOT_FAILURE"
                    vmhash[vm_id]["state"] = n_state
                    vmhash[vm_id]["prev_action"] = "resched"
                    vm.resched
                    splog("#{host_name}(#{host_id}) CALL: vm.resched VM #{vm_id} wait for #{n_state}")
                elsif state == "ACTIVE/BOOT_FAILURE" and prev_action != "recover"
                    n_state = "POWEROFF/LCM_INIT"
                    vmhash[vm_id]["state"] = n_state
                    vmhash[vm_id]["prev_action"] = "recover"
                    vm.recover(1)
                    splog("#{host_name}(#{host_id}) CALL: vm.recover(1) VM #{vm_id} wait for #{n_state}")
                elsif state == "POWEROFF/LCM_INIT" and prev_action != "undeploy"
                    n_state = "UNDEPLOYED/LCM_INIT"
                    vmhash[vm_id]["state"] = n_state
                    vmhash[vm_id]["prev_action"] = "undeploy"
                    vm.undeploy
                    splog("#{host_name}(#{host_id}) CALL: vm.undeploy VM #{vm_id} wait for #{n_state}")
                elsif state == "UNDEPLOYED/LCM_INIT" and prev_action != "resume"
                    n_state = "ACTIVE/RUNNINNG"
                    vmhash[vm_id]["state"] = n_state
                    vmhash[vm_id]["prev_action"] = "resume"
                    vm.resume
                    splog("#{host_name}(#{host_id}) CALL: vm.resume VM #{vm_id} wait for #{n_state}")
                end
            elsif state == "ACTIVE/RUNNING" and (prev_action == "resume" or prev_action == "resched")
                vmhash.delete(vm_id)
                splog("#{host_name}(#{host_id}) MIGRATED: VM #{vm_id}")
                next
            elsif state == "ACTIVE/UNKNOWN" and prev_action == "resched"
                next
            end
            vmhash[vm_id]["count"] += 1
            if count > max_count
                vmhash.delete(vm_id)
                splog("#{host_name}(#{host_id}) GIVUP: VM #{vm_id} Max retries reached! (state:#{state} nstate:#{n_state} pa:#{prev_action} host.state:#{hstate})")
            elsif state == "ACTIVE/PROLOG_MIGRATE_FAILURE"
                vmhash.delete(vm_id)
                splog("#{host_name}(#{host_id}) CLEANUP: Ghost VM #{vm_id}")
            end
        end
        sleep(1.0/1.0)
    end while vmhash.size > 0

    if fencing_script
        system({"FT_ACTION"=>"THAW","FT_HOSTID"=>host_id,"FT_HOSTNAME"=>host_name}, fencing_script)
        splog("#{host_name}(#{host_id}) THAW: script #{fencing_script} (#{$?})")
    end

    splog("#{host_name}(#{host_id}) END: Task completed")
else
    splog("#{host_name}(#{host_id}) END: Nothing to do")
end
