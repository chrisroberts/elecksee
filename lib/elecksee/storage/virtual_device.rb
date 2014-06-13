require 'elecksee'

class Lxc
  module Storage
    # Virtual device backed storage
    class VirtualDevice

      include Helpers

      # @return [String] storage name (usually container name)
      attr_reader :name
      # @return [String] path to temporary directory
      attr_reader :tmp_dir
      # @return [Integer] device size
      attr_reader :size
      # @return [TrueClass, FalseClass] use tmpfs
      attr_reader :tmp_fs
      # @return [String] file system to format (defaults ext4)
      attr_reader :fs_type

      # Create new instance
      #
      # @param name [String] generally container name
      # @param args [Hash]
      # @option args [String] :tmp_dir temporary directory
      # @option args [Integer] :size size of device
      # @option args [String] :fs_type file system to format
      # @option args [TrueClass, FalseClass] :tmp_fs
      def initialize(name, args={})
        @name = name
        @tmp_dir = args[:tmp_dir] || '/tmp/lxc/ephemerals'
        @size = args[:size] || 2000
        @fs_type = args[:fs_type] || 'ext4'
        @tmp_fs = !!args[:tmp_fs]
        @fs_type = 'tmpfs' if @tmp_fs
        create
      end

      # @return [String] path to device
      def device_path
        tmp_fs ? :none : File.join(tmp_dir, 'virt-imgs', name)
      end

      # @return [String] path to mount
      def mount_path
        File.join(tmp_dir, 'virt-mnts', name)
      end
      alias_method :target_path, :mount_path

      # Create the storage
      #
      # @return [TrueClass, FalseClass]
      def create
        make_directories!
        unless(tmp_fs)
          command("dd if=/dev/zero of=#{@device_path} bs=1k seek=#{sive}k count=1 > /dev/null")
          command("echo \"y\" | mkfs -t #{fs_type} #{size} > /dev/null")
          true
        else
          false
        end
      end

      # @return [TrueClass, FalseClass] device currently mounted
      def mounted?
        command("mount").stdout.include?(mount_path)
      end

      # @return [TrueClass, FalseClass] mount device
      def mount
        unless(mounted?)
          command("mount -t #{fs_type}#{mount_options} #{device_path} #{mount_path}", :sudo => true)
          true
        else
          false
        end
      end

      # @return [TrueClass, FalseClass] unmount device
      def unmount
        if(mounted?)
          command("umount #{mount_path}", :sudo => true)
          true
        else
          false
        end
      end

      # Destroy the storage device
      #
      # @return [TrueClass]
      def destroy
        unmount
        unless(device_path == :none)
          File.delete(device_path) if File.file?(device_path)
          FileUtils.rm_rf(device_path) if File.directory?(device_path)
        end
        unless(mount_path == :none)
          if(File.directory?(mount_path))
            FileUtils.rmdir(mount_path)
          end
        end
        true
      end

      private

      # @return [String] options for device mount
      def mount_options
        ' -o loop' unless tmp_fs
      end

      # Create required directories
      #
      # @return [TrueClass]
      def make_directories!
        [device_path, mount_path].each do |path|
          next if path == :none
          unless(File.directory?(path))
            FileUtils.mkdir_p(path)
          end
        end
        true
      end

    end
  end
end
