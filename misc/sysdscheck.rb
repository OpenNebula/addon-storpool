#!/usr/bin/env ruby

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

#
# Environment variables
# ONE_LOCATION - OpenNebula's ONE_LOCATION variable
#
# RAFT_LEADER_IP - Used to trigger the script to action as follow
#    RAFT_LEADER_IP=localhost|127.0.01|<other local ip>
#          - run the script on the from-end
#    RAFT_LEADER_IP=ip_of_the_raft_leader
#          - run on the leader front-end
#
# ONE_DS_HOME - SYSTEMs DS home (default: /var/lib/one/datastores/)
#
# DO_CLEANUP - To remove detecded anomalies set DO_CELANUP="DO CLEANUP"
#
# DEBUG - log more information to syslog, when set to anything
#
# Example crontab job file to run each month, the script is expected in /var/lib/one/sysdscheck.rb
# cat >/etc/cron.d/sysdscheck.cron <<EOF
# RAFT_LEADER_IP=1.2.3.4
# DO_CLEANUP="disabled"
# * * 1 * * oneadmin /var/lib/one/sysdscheck.rb
# EOF
#

ONE_LOCATION=ENV["ONE_LOCATION"]

if !ONE_LOCATION
    RUBY_LIB_LOCATION="/usr/lib/one/ruby"
    VMDIR="/var/lib/one"
    CONFIG_FILE="/var/lib/one/config"
    LOG_FILE="/var/log/one/host_error.log"
else
    RUBY_LIB_LOCATION=ONE_LOCATION+"/lib/ruby"
    VMDIR=ONE_LOCATION+"/var"
    CONFIG_FILE=ONE_LOCATION+"/var/config"
    LOG_FILE=ONE_LOCATION+"/var/host_error.log"
end

$: << RUBY_LIB_LOCATION

require 'opennebula'
include OpenNebula
require 'open3'
require 'syslog/logger'

$log = Syslog::Logger.new 'misc_sp_sysdscheck'

def exit_error(msg)
    $log.error "ERROR: #{msg}"
    $stderr.puts "ERROR: #{msg}"
    exit(-1)
end

octet = /\d{,2}|1\d{2}|2[0-4]\d|25[0-5]/
case ENV['RAFT_LEADER_IP']
    when /\A#{octet}\.#{octet}\.#{octet}\.#{octet}/
        ip = ENV['RAFT_LEADER_IP']
        out, ret = Open3.capture2("ip","route","get", ENV['RAFT_LEADER_IP'])
        iproute = out.lines[0].strip.split(" ")
        if iproute[0] != "local"
            $log.info "Follower, '#{out.lines[0].strip}'"
            exit
        end
    when "localhost"
        #$log.debug "RAFT_LEADER_IP=localhost"
    else
        exit_error "No defined RAFT_LEADER_IP environment variable!"
end

begin
    client = Client.new()
rescue Exception => e
    exit_error e.to_s
end

# Loop through all vms
vms = VirtualMachinePool.new(client)
rc  = vms.info_all

if OpenNebula.is_error?(rc)
    exit_error "Could not get VM info"
end

hosts = Hash.new
vm_ids_array = vms.retrieve_elements("/VM_POOL/VM/ID")
vm_ids_array.each do |vm_id|
    xhost="/HISTORY_RECORDS/HISTORY[last()]/HOSTNAME"
    xdsid="/HISTORY_RECORDS/HISTORY[last()]/DS_ID"
    vm_host = vms.retrieve_elements("/VM_POOL/VM[ID=#{vm_id}]#{xhost}")
    if not vm_host
        vm = OpenNebula::VirtualMachine.new_with_id(vm_id, client)
        vm.info
        vm_host = vm.retrieve_elements("/VM#{xhost}")
        vm_dsid = vm.retrieve_elements("/VM#{xdsid}")
        #$log.debug "vm.info #{vm_id}:#{vm_dsid}:#{vm_host}"
    else
        vm_dsid = vms.retrieve_elements("/VM_POOL/VM[ID=#{vm_id}]#{xdsid}")
    end
    if vm_host[0]
        if vm_dsid[0]
            log.debug "VM_ID #{vm_id}, DS_ID #{vm_dsid[0]}, HOSTNAME #{vm_host[0]}\n" if ENV["DEBUG"]
            hosts[vm_host[0]] = Hash.new unless hosts[vm_host[0]]
            hosts[vm_host[0]][vm_dsid[0]] = Array.new unless hosts[vm_host[0]][vm_dsid[0]]
            hosts[vm_host[0]][vm_dsid[0]].push vm_id
        else
            exit_error "Can'f get DS_ID for VM #{vm_id}"
        end
    else
        exit_error "Can'f get host HOSTNAME for VM #{vm_id}"
    end
end

cmd = <<-EOF
set -e -o pipefail
declare -A vd
while read -r -d ' ' v; do
    vd[\$v]=\$v
done
if [ -d "ONE_DS_HOME" ]; then
    cd "ONE_DS_HOME"
    while read -u 4 v; do
        [ -d "\$v" ] || continue
        if [ -z "\${vd[\$v]}" ]; then
            if [ "DO_CLEANUP" = "DO CLEANUP" ]; then
                logger -t "misc_sp_sysdscheck[\$\$]" -- "REMOVED ONE_DS_HOME/\$v"
                rm -vf "ONE_DS_HOME/\$v"/*
                rmdir -v "ONE_DS_HOME/\$v"
            else
                logger -t "misc_sp_sysdscheck[\$\$]" -- "UNKNOWN ONE_DS_HOME/\$v"
                echo "ONE_DS_HOME/\$v unknown VM"
            fi
#        else
#            echo "ONE_DS_HOME/\$v OK"
         fi
    done 4< <(ls -dA */*)
else
    logger -t "misc_sp_sysdscheck[\$\$]" -- "ERROR! Not a directory 'ONE_DS_HOME'"
    echo "ERROR! Not a directory 'ONE_DS_HOME'" >&2
fi
EOF

one_ds_home = '/var/lib/one/datastores'
one_ds_home = ENV["ONE_DS_HOME"] if ENV["ONE_DS_HOME"]

cmd.gsub! 'ONE_DS_HOME', one_ds_home

cmd.gsub! 'DO_CLEANUP', ENV["DO_CLEANUP"] if ENV["DO_CLEANUP"]

# frozen_string_literal: true
hosts.each do |host, datastores|
    list = String.new
    datastores.each do |ds_id, vm_ids|
        vm_ids.each do |vm_id|
            list << "#{ds_id}/#{vm_id} "
        end
    end
    $log.debug "#{host} >> #{list}" if ENV["DEBUG"]
    out, err, ret = Open3.capture3("ssh", host, "#{cmd}", :stdin_data=>list)
    out.lines do |l|
        $log.info "#{host} #{l.strip}"
    end
    $log.debug "#{host} err:#{err}"
    $log.debug "#{host} ret:#{ret}" if ENV["DEBUG"]
end
