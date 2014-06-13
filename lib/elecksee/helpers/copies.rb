require 'elecksee'
require 'tempfile'

class Lxc
  module Helpers
    # Container related file copy helpers
    module Copies
      # Files requiring name updates
      NAME_FILES = %w(fstab config)
      # Files requiring hostname updates
      HOSTNAME_FILES = %w(
        rootfs/etc/hostname
        rootfs/etc/hosts
        rootfs/etc/sysconfig/network
        rootfs/etc/sysconfig/network-scripts/ifcfg-eth0
      )

      # Update the rootfs
      #
      # @param rootfs_path [String] new rootfs path
      # @return [TrueClass]
      def update_rootfs(rootfs_path)
        contents = File.readlines(lxc.config.to_s).map do |line|
          if(line.start_with?('lxc.rootfs'))
            "lxc.rootfs = #{rootfs_path}\n"
          else
            line
          end
        end.join
        write_file(lxc.config, contents)
        true
      end

      # Update network hardware address
      #
      # @return [TrueClass]
      def update_net_hwaddr
        contents = File.readlines(lxc.config).map do |line|
          if(line.start_with?('lxc.network.hwaddr'))
            parts = line.split('=')
            "#{parts.first.strip} = 00:16:3e#{SecureRandom.hex(3).gsub(/(..)/, ':\1')}\n"
          else
            line
          end
        end.join
        write_file(lxc.config, contents)
        true
      end

      # Write file
      #
      # @param path [String]
      # @param contents [String, Array<String>]
      # @return [TrueClass]
      def write_file(path, contents)
        contents = contents.join if contents.is_a?(Array)
        tmp = Tempfile.new('lxc-copy')
        tmp.write(contents)
        tmp.close
        command("cp #{tmp.path} #{path}", :sudo => true)
        tmp.unlink
        command("chmod 0644 #{path}", :sudo => true)
        true
      end

      # Update container names and host names
      #
      # @param args [Symbol] argument list
      # @return [TrueClass]
      # @note use :no_$FILE where $FILE is the basename to skip
      def update_naming(*args)
        NAME_FILES.each do |file|
          next unless File.exists?(lxc.path.join(file))
          next if args.include?("no_#{file}".to_sym)
          contents = File.read(lxc.path.join(file)).gsub(original, name)
          write_file(lxc.path.join(file), contents)
        end
        HOSTNAME_FILES.each do |file|
          next unless File.exists?(lxc.path.join(file))
          next if args.include?("no_#{file.split('/').last}".to_sym)
          contents = File.read(lxc.path.join(file)).gsub(original, name)
          write_file(lxc.path.join(file), contents)
        end
        true
      end

      # Container is Enterprise linux (redhat)
      #
      # @return [TrueClass, FalseClass]
      def el_platform?
        lxc.rootfs.join('etc/redhat-release').exist?
      end

      # Apply custom networking files depending on platform
      #
      # @return [TrueClass]
      def apply_custom_networking
        if(el_platform?)
          path = lxc.rootfs.join('etc/sysconfig/network-scripts/ifcfg-eth0')
          content = <<-EOF
DEVICE=eth0
BOOTPROTO=static
NETMASK=#{netmask}
IPADDR=#{ipaddress}
ONBOOT=yes
TYPE=Ethernet
USERCTL=yes
PEERDNS=yes
IPV6INIT=no
GATEWAY=#{gateway}
EOF
          write_file(path, content)
          path = lxc.rootfs.join('etc/sysconfig/network')
          content = <<-EOF
NETWORKING=yes
HOSTNAME=#{hostname}
EOF
          write_file(path, content)
          write_file(lxc.rootfs.join('etc/rc.local'), "hostname #{hostname}\n")
        else
          path = lxc.rootfs.join('etc/network/interfaces')
          content = <<-EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
address #{ipaddress}
netmask #{netmask}
gateway #{gateway}
EOF
          write_file(path, content)
        end
        true
      end
    end
  end
end
