# -------------------------------------------------------------------------- #
# Copyright 2015-2026, StorPool (storpool.com)                               #
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

module OneBEX

    module Exporters

        # StorPool exporter. Serves a StorPool snapshot that the StorPool TM
        # prebackup attached read-only on this host, reading the block device
        # directly. Full exports only.
        #
        # Transfer hash attributes used by this exporter:
        #   Read:
        #     :transfer_id - unique transfer identifier used for logs
        #     :source      - /dev/storpool-byid/<snapshot globalId>
        #     :disk        - the interactive_exports.json entry
        #                    (mode, size in MiB)
        #   Written:
        #     :io          - open read-only descriptor of the source
        #     :size        - source size in bytes
        #     :format      - always raw
        class StorPool

            MIB = 1024 * 1024

            def initialize(config:, logger:)
                @config = config
                @logger = logger
            end

            def start(xfr)
                disk = xfr[:disk] || {}
                mode = (disk['mode'] || 'full').to_s.downcase

                unless mode == 'full'
                    raise "StorPool exporter supports full exports only (mode: #{mode})"
                end

                source = xfr[:source].to_s

                raise 'Missing StorPool source' if source.empty?

                unless File.blockdev?(source) || File.file?(source)
                    raise "StorPool source #{source} is not a block device"
                end

                io = File.open(source, 'rb')
                io.seek(0, IO::SEEK_END)

                xfr[:io]     = io
                xfr[:size]   = io.pos
                xfr[:format] = 'raw'

                expected = disk['size'].to_i * MIB

                if expected > 0 && expected != xfr[:size]
                    @logger.warn(
                        "StorPool source #{source} is #{xfr[:size]} bytes, " \
                        "the export entry says #{expected}"
                    )
                end

                @logger.info(
                    "Starting StorPool exporter for #{xfr[:transfer_id]}: " \
                    "#{source} (#{xfr[:size]} bytes)"
                )

                true
            rescue StandardError => e
                @logger.error(
                    "Failed to start StorPool transfer #{xfr[:transfer_id]}: " \
                    "#{e.message}"
                )

                close(xfr)

                raise
            end

            # One allocated extent. StorPool exposes no allocation map and the
            # device does not answer SEEK_HOLE, so every byte is reported as data.
            def blocks(xfr)
                [
                    {
                        :start  => 0,
                        :length => xfr[:size],
                        :dirty  => true,
                        :zero   => false,
                        :hole   => false
                    }
                ]
            end

            def data(xfr, range)
                offset = range[:start].to_i
                length = range[:length].to_i

                raise "Invalid read range: #{range}" if length <= 0

                if offset + length > xfr[:size]
                    raise "Read range #{range} beyond the end of #{xfr[:transfer_id]}"
                end

                buf = xfr[:io].pread(length, offset)

                unless buf && buf.bytesize == length
                    raise "Short read on #{xfr[:transfer_id]}: " \
                          "#{buf.to_s.bytesize} of #{length} bytes at #{offset}"
                end

                buf
            end

            # The snapshot stays attached until the TM postbackup detaches it.
            def finish(xfr, force: false)
                close(xfr)

                true
            end

            def info(xfr)
                {
                    :SIZE   => (xfr[:size] + MIB - 1) / MIB,
                    :FORMAT => xfr[:format]
                }
            end

            private

            def close(xfr)
                io = xfr.delete(:io)

                io.close if io && !io.closed?
            rescue StandardError => e
                @logger.warn("Error closing #{xfr[:transfer_id]}: #{e.message}")
            end

        end

    end

end

OneBEX::Exporters.register('storpool', OneBEX::Exporters::StorPool)
