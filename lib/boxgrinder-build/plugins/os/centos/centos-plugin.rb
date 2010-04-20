# JBoss, Home of Professional Open Source
# Copyright 2009, Red Hat Middleware LLC, and individual contributors
# by the @authors tag. See the copyright.txt in the distribution for a
# full listing of individual contributors.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 2.1 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'boxgrinder-build/plugins/os/base/rpm-based-os-plugin'

module BoxGrinder
  class CentOSPlugin < RPMBasedOSPlugin

    CENTOS_REPOS = {
            "5" => {
                    "base" => {
                            "mirrorlist" => "http://mirrorlist.centos.org/?release=#OS_VERSION#&arch=#ARCH#&repo=os"
                    },
                    "updates" => {
                            "mirrorlist" => "http://mirrorlist.centos.org/?release=#OS_VERSION#&arch=#ARCH#&repo=updates"
                    }
            }
    }

    def info
      {
              :name       => :centos,
              :full_name  => "CentOS",
              :versions   => ["5"]
      }
    end

    def build
      raise "Build cannot be started before the plugin isn't initialized" if @initialized.nil?

      adjust_partition_table

      disk = build_with_appliance_creator( CENTOS_REPOS )

      @log.info "Executing post-install steps..."

      customize( disk ) do |guestfs, guestfs_helper|
        # TODO: make sure we're mounting right partitions. What if we have more partitions?
        # e2label?

        root_partition = nil

        guestfs.list_partitions.each do |partition|
          guestfs_helper.mount_partition( partition, '/' )
          if guestfs.exists( '/sbin/e2label' ) != 0
            root_partition = partition
            break
          end
          guestfs.umount( partition )
        end

        guestfs.list_partitions.each do |partition|
          next if partition == root_partition
          guestfs_helper.mount_partition( partition, guestfs.sh( "/sbin/e2label #{partition}" ).chomp.strip )
        end

        kernel_version = guestfs.ls("/lib/modules").first

        @log.debug "Recreating initrd for #{kernel_version} kernel..."
        @log.debug guestfs.sh( "/sbin/mkinitrd -f -v --preload=mptspi /boot/initrd-#{kernel_version}.img #{kernel_version}" )
        @log.debug "Initrd recreated."
      end

      @log.info "Done."

      disk
    end


    # https://bugzilla.redhat.com/show_bug.cgi?id=466275
    def adjust_partition_table
      @appliance_config.hardware.partitions['/boot'] = { 'root' => '/boot', 'size' => '0.1' }
    end
  end
end