%w(
  helpers/base helpers/options helpers/copies lxc
  storage/overlay_directory storage/overlay_mount
  storage/virtual_device
).each do |path|
  require "elecksee/#{path}"
end

class Lxc
  class Clone

    include Helpers
    include Helpers::Options

    option :original, '-o', :string, :required => true, :desc => 'Original container name', :aliases => 'orig'
    option :new_name, '-n', :string, :required => true, :desc => 'New container name', :aliases => 'new'
    option :snapshot, '-s', :boolean, :desc => 'Make new rootfs a snapshot of original'
    option :fssize, '-L', :string, :desc => 'Size of new file system', :default => '2G'
    option :vgname, '-v', :string, :desc => 'LVM volume group name', :default => 'lxc'
    option :lvprefix, '-p', :string, :desc => 'LVM volume name prefix'
    option :fstype, '-t', :string, :desc => 'New container file system', :default => 'ext4'
    option :device, '-D', :integer, :desc => 'Make copy in VBD of {SIZE}M'
    option :ipaddress, '-I', :string, :desc => 'Custom IP address'
    option :gateway, '-G', :string, :desc => 'Custom gateway'
    option :netmask, '-N', :string, :default => '255.255.255.0', :desc => 'Custom netmask'

    # Hash containing original and new container instances
    attr_reader :lxcs
    
    def initialize(args={})
      configure!(args)
      @lxcs = {}
      @lxcs[:original] = Lxc.new(original)
      @lxcs[:new] = Lxc.new(new_name)
      validate!
    end

    def clone!
      copy_original
      update_naming
      apply_custom_addressing if ipaddress
      lxcs[:new]
    end
    
    private

    # Returns new lxc instance
    def lxc
      lxcs[:new]
    end

    def validate!
      unless(lxcs[:original].exists?)
        raise "Requested `original` container does not exist (#{original})"
      end
      if(lxcs[:new].exists?)
        raise "Requested `new` container already exists (#{new_name})"
      end
      if(lxcs[:original].running?)
        raise "Requested `original` container is current running (#{original})"
      end
    end

    def copy_original
      copy_init
      if(device)
        rootfs_dir = copy_vbd
      elsif(File.stat(lxcs[:original].path.to_s).blockdev?)
        rootfs_dir = copy_lvm
      elsif(command("btrfs subvolume list '#{lxcs[:original].path}'", :allow_failure => true))
        rootfs_dir = copy_btrfs
      else
        rootfs_dir = copy_fs
      end
      update_rootfs(rootfs_dir)
    end

    def copy_init
      directory = CloneDirectory.new(lxcs[:new].name, :dir => File.dirname(lxcs[:original].path.to_s))
      %w(config fstab).each do |file|
        command("cp '#{lxcs[:original].path.join(file)}' '#{directory.target_path}'", :sudo => true)
      end
    end

    def copy_fs
      directory = CloneDirectory.new(lxcs[:new].name, :dir => File.dirname(lxcs[:original].path.to_s))
      command("rsync -ax '#{lxcs[:original].rootfs}/' '#{File.join(directory.target_path, 'rootfs')}/'", :sudo => true)
      File.join(directory.target_path, 'rootfs')
    end

    def copy_vbd
      storage = VirtualDevice.new(lxcs[:new].name, :tmp_dir => '/opt/lxc-vbd')
      command("rsync -ax '#{lxcs[:original].rootfs}/' '#{storage.target_path}/'", :sudo => true)
      storage.target_path
    end

    def copy_lvm
      raise 'Not implemented'
    end

    def copy_btrfs
      rootfs_path = lxcs[:new].path.join('rootfs')
      command("btrfs subvolume snapshot '#{lxcs[:original].rootfs}' '#{rootfs_path}'", :sudo => true)
      rootfs_path
    end
  end
end
