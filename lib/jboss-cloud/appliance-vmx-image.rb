require 'rake/tasklib'
require 'rexml/document'

module JBossCloud

  class ApplianceVMXImage < Rake::TaskLib

    def initialize( config )

      @config                 = config
      appliance_build_dir     = "#{Config.get.dir_build}/appliances/#{@config.arch}/#{@config.name}"
      @appliance_xml_file     = "#{appliance_build_dir}/#{@config.name}.xml"

      if File.exists?( "#{JBossCloud::Config.get.dir_src}/base.vmdk" )
        @base_vmdk_file = "#{JBossCloud::Config.get.dir_src}/base.vmdk"
      else
        @base_vmdk_file = "#{JBossCloud::Config.get.dir_base}/src/base.vmdk"
      end

      if File.exists?( "#{JBossCloud::Config.get.dir_src}/base.vmx" )
        @base_vmx_file = "#{JBossCloud::Config.get.dir_src}/base.vmx"
      else
        @base_vmx_file = "#{JBossCloud::Config.get.dir_base}/src/base.vmx"
      end

      define
    end

    def define
      define_precursors
    end

    # returns value of cylinders, heads and sector for selected disk size (in MB)
    def generate_scsi_chs(disk_size)

      gb_sectors = 2097152
      
      if disk_size == 1024
        h = 128
        s = 32
      else
        h = 255
        s = 63
      end

      c = disk_size / 1024 * gb_sectors / (h*s)
      total_sectors = gb_sectors * disk_size / 1024

      return [ c, h, s, total_sectors ]
    end

    def change_vmdk_values( type )
      vmdk_data = File.open( @base_vmdk_file ).read

      c, h, s, total_sectors = generate_scsi_chs( @config.disk_size )

      is_enterprise = type.eql?("vmfs")

      vmdk_data.gsub!( /#NAME#/ , @config.name )
      vmdk_data.gsub!( /#TYPE#/ , type )
      vmdk_data.gsub!( /#EXTENT_TYPE#/ , is_enterprise ? "VMFS" : "FLAT" )
      vmdk_data.gsub!( /#NUMBER#/ , is_enterprise ? "" : "0" )
      vmdk_data.gsub!( /#HW_VERSION#/ , is_enterprise ? "4" : "3" )
      vmdk_data.gsub!( /#CYLINDERS#/ , c.to_s )
      vmdk_data.gsub!( /#HEADS#/ , h.to_s )
      vmdk_data.gsub!( /#SECTORS#/ , s.to_s )
      vmdk_data.gsub!( /#TOTAL_SECTORS#/ , total_sectors.to_s )
      
      vmdk_data
    end

    def change_common_vmx_values
      vmx_data = File.open( @base_vmx_file ).read

      # replace version with current jboss cloud version
      vmx_data.gsub!( /#VERSION#/ , JBossCloud::Config.get.version_with_release )
      # change name
      vmx_data.gsub!( /#NAME#/ , @config.name )
      # and summary
      vmx_data.gsub!( /#SUMMARY#/ , @config.summary )
      # replace guestOS informations to: linux or otherlinux-64, this seems to be the savests values
      vmx_data.gsub!( /#GUESTOS#/ , "#{@config.arch == "x86_64" ? "otherlinux-64" : "linux"}" )
      # memory size
      vmx_data.gsub!( /#MEM_SIZE#/ , @config.mem_size.to_s )
      # memory size
      vmx_data.gsub!( /#VCPU#/ , @config.vcpu.to_s )
      # network name
      vmx_data += "\nethernet0.networkName = \"#{@config.network_name}\""

      vmx_data
    end

    def create_hardlink_to_disk_image( vmware_raw_file )
      base_raw_file = File.dirname( @appliance_xml_file ) + "/#{@config.name}-sda.raw"

      # Hard link RAW disk to VMware destination folder
      FileUtils.ln( base_raw_file , vmware_raw_file ) if ( !File.exists?( vmware_raw_file ) || File.new( base_raw_file ).mtime > File.new( vmware_raw_file ).mtime )
    end

    def define_precursors
      super_simple_name                    = File.basename( @config.name, '-appliance' )
      vmware_personal_output_folder        = File.dirname( @appliance_xml_file ) + "/vmware/personal"
      vmware_personal_vmx_file             = vmware_personal_output_folder + "/" + File.basename( @appliance_xml_file, ".xml" ) + '.vmx'
      vmware_personal_vmdk_file            = vmware_personal_output_folder + "/" + File.basename( @appliance_xml_file, ".xml" ) + '.vmdk'
      vmware_personal_raw_file             = vmware_personal_output_folder + "/#{@config.name}-sda.raw"
      vmware_enterprise_output_folder      = File.dirname( @appliance_xml_file ) + "/vmware/enterprise"
      vmware_enterprise_vmx_file           = vmware_enterprise_output_folder + "/" + File.basename( @appliance_xml_file, ".xml" ) + '.vmx'
      vmware_enterprise_vmdk_file          = vmware_enterprise_output_folder + "/" + File.basename( @appliance_xml_file, ".xml" ) + '.vmdk'
      vmware_enterprise_raw_file           = vmware_enterprise_output_folder + "/#{@config.name}-sda.raw"

      file "#{@appliance_xml_file}.vmx-input" => [ @appliance_xml_file ] do
        doc = REXML::Document.new( File.read( @appliance_xml_file ) )
        name_elem = doc.root.elements['name']
        name_elem.attributes[ 'version' ] = "#{JBossCloud::Config.get.version_with_release}"
        description_elem = doc.root.elements['description']
        if ( description_elem.nil? )
          description_elem = REXML::Element.new( "description" )
          description_elem.text = "#{@config.name} Appliance\n Version: #{JBossCloud::Config.get.version_with_release}"
          doc.root.insert_after( name_elem, description_elem )
        end
        # update xml the file according to selected build architecture
        arch_elem = doc.elements["//arch"]
        arch_elem.text = @config.arch
        File.open( "#{@appliance_xml_file}.vmx-input", 'w' ) {|f| f.write( doc ) }
      end

      desc "Build #{super_simple_name} appliance for VMware personal environments (Server/Workstation/Fusion)"
      task "appliance:#{@config.name}:vmware:personal" => [ "#{@appliance_xml_file}.vmx-input" ] do
        FileUtils.mkdir_p vmware_personal_output_folder

        # link disk image
        create_hardlink_to_disk_image( vmware_personal_raw_file )

        # create .vmx file
        File.new( vmware_personal_vmx_file , "w" ).puts( change_common_vmx_values )

        # create disk descriptor file
        File.new( vmware_personal_vmdk_file, "w" ).puts( change_vmdk_values( "monolithicFlat" ) )
      end

      desc "Build #{super_simple_name} appliance for VMware enterprise environments (ESX/ESXi)"
      task "appliance:#{@config.name}:vmware:enterprise" => [ @appliance_xml_file ] do
        FileUtils.mkdir_p vmware_enterprise_output_folder

        # link disk image
        create_hardlink_to_disk_image( vmware_enterprise_raw_file )

        # create .vmx file
        File.new( vmware_enterprise_vmx_file , "w" ).puts( change_common_vmx_values )

        # create disk descriptor file
        File.new( vmware_enterprise_vmdk_file, "w" ).puts( change_vmdk_values( "vmfs" ) )
      end

      #desc "Build #{super_simple_name} appliance for VMware"
      #task "appliance:#{@config.name}:vmware" => [ "appliance:#{@config.name}:vmware:personal", "appliance:#{@config.name}:vmware:enterprise" ]
    end
  end
end