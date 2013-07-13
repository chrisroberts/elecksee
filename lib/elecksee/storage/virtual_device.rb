require 'elecksee/helpers/base'

class Lxc
  
  class VirtualDevice

    include Helpers
    
    attr_reader :name
    attr_reader :tmp_dir
    attr_reader :size
    attr_reader :tmp_fs
    attr_reader :fs_type
    
    def initialize(name, args={})
      @name = name
      @tmp_dir = args[:tmp_dir] || '/tmp/lxc/ephemerals'
      @size = args[:size] || 2000
      @fs_type = args[:fs_type] || 'ext4'
      @tmp_fs = !!args[:tmp_fs]
      @fs_type = 'tmpfs' if @tmp_fs
      create
    end

    def device_path
      tmp_fs ? 'none' : File.join(tmp_dir, 'virt-imgs', name)
    end

    def mount_path
      File.join(tmp_dir, 'virt-mnts', name)
    end
    alias_method :target_path, :mount_path

    def create
      make_directories!
      unless(tmp_fs)
        command("dd if=/dev/zero of=#{@device_path} bs=1k seek=#{sive}k count=1 > /dev/null")
        command("echo \"y\" | mkfs -t #{fs_type} #{size} > /dev/null")
      end
    end

    def mounted?
      command("mount").stdout.include?(mount_path)
    end
    
    def mount
      unless(mounted?)
        command("mount -t #{fs_type}#{mount_options} #{device_path} #{mount_path}", :sudo => true)
        true
      end
    end

    def unmount
      if(mounted?)
        command("umount #{mount_path}", :sudo => true)
        true
      end
    end

    def destroy
      unmount
      File.delete(device_path) if File.file?(device_path)
      FileUtils.rm_rf(device_path) if File.directory?(device_path)
      FileUtils.rmdir(mount_path) if File.directory?(mount_path)
    end

    private

    def mount_options
      ' -o loop' unless tmp_fs
    end
    
    def make_directories!
      [device_path, mount_path].each do |path|
        unless(File.directory?(path))
          FileUtils.mkdir_p(path)
        end
      end
    end
  end
end
