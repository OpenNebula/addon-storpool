#!/usr/bin/env ruby
#
# --------------------------------------------------------------------------
# Copyright 2015-2020, StorPool (storpool.com)
#
# Portions copyright OpenNebula Project (OpenNebula.org), OpenNebula systems
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#---------------------------------------------------------------------------

RUBY_LIB_LOCATION = '/usr/lib/one/ruby'
GEMS_LOCATION     = '/usr/share/one/gems'

if File.directory?(GEMS_LOCATION)
    Gem.use_paths(GEMS_LOCATION)
end

$LOAD_PATH << RUBY_LIB_LOCATION

require 'tempfile'
require 'fileutils'
require 'augeas'
require 'yaml'
require 'getoptlong'
require 'pp'

class Hash
    # Returns a new hash containing the contents of other_hash and the
    #   contents of self. If the value for entries with duplicate keys
    #   is a Hash, it will be merged recursively, otherwise it will be that
    #   of other_hash.
    #
    # @param [Hash] other_hash
    #
    # @return [Hash] Containing the merged values
    #
    # @example Merging two hashes
    #   h1 = {:a => 3, {:b => 3, :c => 7}}
    #   h2 = {:a => 22, c => 4, {:b => 5}}
    #   
    #   h1.deep_merge(h2) #=> {:a => 22, c => 4, {:b => 5, :c => 7}}
    def deep_merge(other_hash)
        target = dup

        other_hash.each do |hash_key, hash_value|
            if hash_value.is_a?(Hash) and self[hash_key].is_a?(Hash)
                target[hash_key] = self[hash_key].deep_merge(hash_value)
            elsif hash_value.is_a?(Array) and self[hash_key].is_a?(Array)
                hash_value.each_with_index { |elem, i|
                    if self[hash_key][i].is_a?(Hash) and elem.is_a?(Hash)
                        target[hash_key][i] = self[hash_key][i].deep_merge(elem)
                    else
                        target[hash_key] = hash_value
                    end
                }
            else
                target[hash_key] = hash_value
            end
        end

        target
   end
end

default_config = {
    "/etc/one/oned.conf" => {
        :lens => "Oned.lns",
        :apply => {
            "vm_mad_kvm_arguments_l" => {
                :method => "oned_conf_arguments",
                :element => "VM_MAD[NAME='\"kvm\"']/ARGUMENTS",
                :match => "-l",
                :arguments => {
                        "deploy=deploy-tweaks" => "deploy=deploy-tweaks",
                },
            },
            "datastore_mad_arguments_d" => {
                :method => "oned_conf_arguments",
                :element => "DATASTORE_MAD[EXECUTABLE='\"one_datastore\"']/ARGUMENTS",
                :match => "-d",
                :arguments => {
                    "storpool" => "storpool",
                },
            },
            "datastore_mad_arguments_s" => {
                :method => "oned_conf_arguments",
                :element => "DATASTORE_MAD[EXECUTABLE='\"one_datastore\"']/ARGUMENTS",
                :match => "-s",
                :arguments => {
                    "storpool" => "storpool",
                },
            },
            "tm_mad_arguments_d" => {
                :method => "oned_conf_arguments",
                :element => "TM_MAD[EXECUTABLE='\"one_tm\"']/ARGUMENTS",
                :match => "-d",
                :arguments => {
                    "storpool" => "storpool",
                },
            },
            "ds_mad_conf" => {
                :method => "oned_conf_vector",
                :element => "DS_MAD_CONF",
                :match => "[NAME='\"storpool\"']",
                :arguments => {
                    "NAME" => "\"storpool\"",
                    "REQUIRED_ATTRS" => "\"DISK_TYPE\"",
                    "PERSISTENT_ONLY" => "\"NO\"",
                    "MARKETPLACE_ACTIONS" => "\"\"",
                },
            },
            "tm_mad_conf" => {
                :method => "oned_conf_vector",
                :element => "TM_MAD_CONF",
                :match => "[NAME='\"storpool\"']",
                :arguments => {
                    "NAME" => "\"storpool\"",
                    "LN_TARGET" => "\"NONE\"",
                    "CLONE_TARGET" => "\"SELF\"",
                    "SHARED" => "\"yes\"",
                    "DS_MIGRATE" => "\"yes\"",
                    "DRIVER" => "\"raw\"",
                    "ALLOW_ORPHANS" => "\"yes\"",
                    "TM_MAD_SYSTEM" => "\"ssh,shared\"",
                    "LN_TARGET_SSH" => "\"NONE\"",
                    "CLONE_TARGET_SSH" => "\"SELF\"",
                    "DISK_TYPE_SSH" => "\"BLOCK\"",
                    "LN_TARGET_SHARED" => "\"NONE\"",
                    "CLONE_TARGET_SHARED" => "\"SELF\"",
                    "DISK_TYPE_SHARED" => "\"BLOCK\"",
                },
            },
            "vm_restricted_attr" => {
                :method => "oned_conf_array",
                :element => "VM_RESTRICTED_ATTR",
                :arguments => {
                    "DISKSNAPSHOT_LIMIT" => "DISKSNAPSHOT_LIMIT",
                    "VMSNAPSHOT_LIMIT" => "VMSNAPSHOT_LIMIT",
                    "T_CPU_THREADS" => "T_CPU_THREADS",
                    "T_CPU_SOCKETS" => "T_CPU_SOCKETS",
                    "T_CPU_FEATURES" => "T_CPU_FEATURES",
                    "T_CPU_MODE" => "T_CPU_MODE",
                    "T_CPU_MODEL" => "T_CPU_MODEL",
                    "T_CPU_VENDOR" => "T_CPU_VENDOR",
                    "T_CPU_CHECK" => "T_CPU_CHECK",
                    "T_CPU_MATCH" => "T_CPU_MATCH",
                    "T_VF_MACS" => "T_VF_MACS",
                    "VC_POLICY" => "VC_POLICY",
                },
            },
        },
    },
    "/var/lib/one/remotes/etc/vmm/kvm/kvmrc" => {
        :lens => "Shellvars.lns",
        :apply => {
            "default_attach_disk" => {
                :method => "simple_conf",
                :arguments => {
                    'DEFAULT_ATTACH_CACHE' => "none",
                    'DEFAULT_ATTACH_DISCARD' => "unmap",
                    'DEFAULT_ATTACH_IO' => "native",
                },
            },
        },
    },
    "/etc/one/vmm_exec/vmm_execrc" => {
        :lens => "Shellvars.lns",
        :apply => {
            "live_disk_snapshots" => {
                :method => "simple_conf",
                :match => " ",
                :delete => nil,
                :arguments => {
                    "LIVE_DISK_SNAPSHOTS" => "kvm-storpool",
                },
            },
        },
    },
}

def log(msg, level=0)
    if $verbose >= level
        puts "#{msg}"
    end
end

def oned_conf_arguments(aug, c, name=nil)
    element = c[:element]
    argument_idx = nil
    argument_hash = {}
    parsed_str = ''
    argument_add = {}
    argument_del = {}
    changed = []
    arguments_new = []

    if c[:arguments].nil?
        log "#ERR# No 'arguments'. Skipped."
        return
    end
    arguments = aug.get(element).gsub(/\"/,"")
    arguments = arguments.split(' ')
    arguments.each_with_index do |v, i|
        if v == c[:match]
            argument_idx = i+1
            parsed_str = arguments[argument_idx]
        end
    end
    log "#DBG# parsed_str '#{parsed_str}' argument_idx=#{argument_idx} match='#{c[:match]}'",2
    if !parsed_str.empty?
        l_arr = parsed_str.split(',')
        l_arr.each do |lvar|
            argument_hash[lvar] = lvar
        end
    end
    log "#DBG# argument_hash=#{argument_hash}",2

    c[:arguments].each do |k, v|
        log "#DBG# walk argument_add{#{k}}='#{v}' (nil:#{v.nil?})",2
        if v.nil?
            log "[DEL] '#{k}' from #{c[:element]}",0
            argument_hash.delete(k)
            changed << "#{c[:match]} #{argument_hash.keys.join(',')}"
        else
            if argument_hash.key?(v)
                log "#OK# '#{v}' from #{c[:element]}",1
            else
                log "#ADD# '#{v}' from #{c[:element]}",1
                arguments_new << v
            end
        end
    end
    log "#DBG# arguments_new='#{arguments_new}'",2
    if argument_idx.nil?
        arguments << c[:match]
        arguments << arguments_new.join(',')
        changed << "#{c[:match]} #{arguments_new.join(',')}"
    else
        arguments[argument_idx] = argument_hash.keys.join(',')
        if !arguments_new.empty?
            arguments[argument_idx] += ",#{arguments_new.join(',')}"
            changed << "#{c[:match]} #{arguments[argument_idx]}"
        end
    end
    log "#DBG# changed=#{changed}",2
    if changed.empty?
        log "#OK# #{element} = \"#{arguments.join(' ')}\"",0
    else
        log "#SET# #{element} = \"#{arguments.join(' ')}\"",0
        aug.set(element, "\"#{arguments.join(' ')}\"")
    end
end

def oned_conf_array(aug, c, name=nil)
    if c[:arguments].nil?
        log "#ERR# No 'arguments'. Skipped."
        return
    end
    element = c[:element]
    attrib = {}
    i=1
    while aug.exists("#{element}[#{i}]")
        ev = aug.get("#{element}[#{i}]").gsub(/\"/,"")
        attrib[ev] = i
        i = i + 1
    end

    c[:arguments].each do |k, v|
        if attrib.key?(k)
            if v.nil?
                log "#TBD# rename ##{element} = \"k\" !!!!!!!!!!",0
#TBD                aug.rename("#{element}[#{i}]", "#comment[LAST()+1]")
                next
            end
            log "#OK# #{element}[#{attrib[k]}] = #{k}"
        else
            if !v.nil?
                log "#SET# #{element}[#{i}] = \"#{k}\" "
                aug.set("#{element}[#{i}]", "\"#{k}\"")
                i = i + 1
            end
        end
    end
end

def oned_conf_vector(aug, c, name = nil)
    if c[:arguments].nil?
        log "#ERR# No 'arguments'. Skipped."
        return
    end
    aug_q = "#{c[:element]}#{c[:match]}"
    changed = false
    if aug.exists(aug_q)
        c[:arguments].each do |k, v|
            aug_qk = aug_q + "/" + k
            log "#DBG# aug_q:#{aug_qk}",4
            if aug.exists(aug_qk)
                val = aug.get(aug_qk)
                log "#DBG# val:#{val}",4
                if v != val
                    log "#SET# #{aug_qk} = #{v} (old #{val})"
                    aug.set(aug_qk, v)
                    changed = true
                else
                    log "#OK# #{aug_qk} = #{val}"
                end
            else
                log "#SET# #{aug_qk} = #{v}"
                aug.set(aug_qk, v)
                changed = true
            end
        end
    else
        i = 1
        while aug.exists("#{c[:element]}[#{i}]")
            i = i + 1
        end
        log "#SET# #{c[:element]}[#{i}]"
        aug.set("#{c[:element]}[#{i}]", nil)
        c[:arguments].each do |k, v|
            log "#SET# #{c[:element]}[#{i}]/#{k} = #{v}",0
            aug.set("#{c[:element]}[#{i}]/#{k}", v)
        end
        changed = true
    end
end

def simple_conf(aug, c, name=nil)
    if c[:arguments].nil?
        log "#ERR# No 'arguments'. Skipped."
        return
    end
    c[:arguments].each do |k, v|
        if aug.exists(k)
             val = aug.get(k)
             if c[:match].nil?
                 if v == val
                     log "#OK# #{k}=#{v}",0
                 else
                     log "#SET# #{k}='#{v}' (was '#{val}') #exist+match",0
                     aug.set(k, v)
                 end
             else
                 change = false
                 val_a = val.gsub(/\"/,"").split(c[:match])
                 val_a.each_with_index do |vv, i|
                     if vv == v
                         val_a.delete_at(i)
                         change = true
                     end
                 end
                 if change
                     if c[:delete].nil?
                         change = false
                     end
                 elsif c[:delete].nil?
                         val_a << v
                         change = true
                 end
                 if change
                     v = "\"#{val_a.join(c[:match])}\""
                     log "#SET# #{k}=#{v} (was #{val}) #exist",0
                     aug.set(k, v)
                 else
                     log "#OK# #{k}=#{val}",0
                 end
             end
        else
            comment_idx = nil
            comment_val = ''
            i=1
            while aug.exists("#comment[#{i}]")
                comment_val = aug.get("#comment[#{i}]")
                val = comment_val.gsub(/^[ \t]*#[ \t]*/,'')
                if val.split('=')[0] == k
                    comment_idx = i
                    break
                end
                i = i + 1
            end
            if comment_idx.nil?
                log "#SET# #{k} = '#{v}' #new line"
            else
                aug.rename("#comment[#{comment_idx}]", k)
                log "#SET# #{k} = '#{v}' #replace comment[#{comment_idx}]:#{comment_val}"
            end
            aug.set(k, v)
        end
    end
end

def loadYaml(yamlfile)
    begin
        log "Loading #{yamlfile}",1
        YAML.load_file(yamlfile)
    rescue Exception => err
        log "Load YAML (#{yamlfile}) errorr: #{err}"
        exit 1
    end
end

@methods = {
    "oned_conf_arguments" => method(:oned_conf_arguments),
    "oned_conf_array" => method(:oned_conf_array),
    "oned_conf_vector" => method(:oned_conf_vector),
    "simple_conf" => method(:simple_conf),
}

merge = []
$verbose = 0
write = false
$yamldump = false

opts=GetoptLong.new(
    ["--help", "-h", GetoptLong::NO_ARGUMENT],
    ["--write", "-w", GetoptLong::NO_ARGUMENT],
    ["--merge", "-m", GetoptLong::REQUIRED_ARGUMENT],
    ["--conf", "-c", GetoptLong::REQUIRED_ARGUMENT],
    ["--verbose", "-v", GetoptLong::NO_ARGUMENT],
    ["--yamldump", "-y", GetoptLong::NO_ARGUMENT],
)

opts.each { |option,v|
    case option
    when "--write"
        write = true
    when "--yamldump"
        $yamldump = true
    when "--conf"
        default_config = loadYaml(v)
        default_config = {} if default_config.nil?
        log "[DBG] default_config:#{default_config}"
    when "--merge"
        merge << v
    when "--verbose"
        $verbose = $verbose + 1
    when "--help"
        puts "Usage: #{File.basename($0)} [-h|--help] [-v|--verbose] [-w|--write] [-c|--conf yamlfile] [-m|--merge yamlfile] [-y|--yamldump]"
        puts "  -h|--help     This help"
        puts "  -v|--verbose"
        puts "     Be verbose (could be applied multiple times)"
        puts "  -w|--write"
        puts "     Write changes replacing the original files"
        puts "  -m|--merge FILE"
        puts "     Merge the Yaml file to the current configuration."
        puts "     (Could be used multiple times to merge files)"
        puts "  -y|--yamldump"
        puts "     Dump the configuration to stdout as an YAML and exit"
        puts "  -c|--conf FILE"
        puts "     Load YAML file to replate the internal default configuration"
        exit
    end
}

merge.each do |yamlfile|
    yamldata = loadYaml(yamlfile)
    if yamldata.nil?
        log "#WRN# empty yaml #{yamlfile}"
    else
        default_config = default_config.deep_merge(yamldata)
    end
end

if $yamldump
   puts default_config.to_yaml
   exit
end

aug = Augeas.create(:no_modl_autoload => true,
                    :no_load          => true,
                    :root             => '/',
                    )

time = Time.now
timestamp = time.strftime("%Y%m%d_%H%M%S")

default_config.each do |conf_file, cfg|
    log "##### #{conf_file} #####"
    if cfg[:lens].nil?
      log "#ERR# no lens defined! Skipped."
      next
    end
    begin
        stat = File.stat(conf_file)
        mode = stat.mode & 0xFFF
    rescue Errno::ENOENT => err
        log "#WRN# File doesn't exist #{conf_file}"
        next
    rescue Errno::EACCES => err
        log "#WRN# Can't read from #{conf_file}. No permission."
        next
    rescue => err
        log "#ERR# #{err.inspect}"
        exit 1
    end
    tmp_file = Tempfile.new("#{conf_file}-tmp")
    temp_file = tmp_file.path
    log "##### (mode #{mode.to_s(8)}) temp:#{temp_file} lens:#{cfg[:lens]}",3
    FileUtils.cp(conf_file, temp_file)
    aug.clear_transforms
    aug.transform(:lens => cfg[:lens], :incl => temp_file)
    aug.context = "/files/#{temp_file}"
    aug.load
    if cfg.key?(:apply)
        cfg[:apply].each do |cName, c|
            log "#---> #{cName} #{$verbose > 1 ? "with #{c}" : nil}"
            if @methods.key?(c[:method])
                @methods[c[:method]].(aug, c, cName)
            else
                puts "#ERR# Unknown method '#{c[:method]}'"
            end
        end
        begin
            log "##### saving #{temp_file}",1
            aug.save
        rescue Augeas::CommandExecutionError => err
            puts "#ERR# #{err}"
            err = aug.get("/augeas//error")
            puts "#ERR#  [error]:#{err}"
            err = aug.get("/augeas//error/lens")
            puts "#ERR#  [lens]:#{err}"
            err = aug.get("/augeas//error/last_matched")
            puts "#ERR#  [last_matched]:#{err}"
            err = aug.get("/augeas//error/next_not_matched")
            puts "#ERR#  [next_not_matched]:#{err}"
            err = aug.get("/augeas//error/path")
            puts "#ERR#  [path]:#{err}"
            err = aug.get("/augeas//error/pos")
            puts "#ERR#  [pos]:#{err}"
            err = aug.get("/augeas//error/line")
            puts "#ERR#  [line]:#{err}"
            err = aug.get("/augeas//error/char")
            puts "#ERR#  [char]:#{err}"
            err = aug.get("/augeas//error/message")
            puts "#ERR#  [message]:#{err}"
            next
        end
        if write
            conf_file_bak = conf_file + "-backup-" +  timestamp
            puts "#BAK# backup #{conf_file} #{conf_file_bak}"
            FileUtils.cp(conf_file, conf_file_bak)
            puts "#MOV# mv #{temp_file} #{conf_file}"
            FileUtils.mv(temp_file, conf_file)
            puts "#MSG# chmod #{mode.to_s(8)} #{conf_file}"
            FileUtils.chmod(mode, conf_file)
            puts "#MSG# chown #{stat.uid}.#{stat.gid} #{conf_file}"
            FileUtils.chown(stat.uid, stat.gid, conf_file)
        end
    end
end
