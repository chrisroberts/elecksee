require 'elecksee'

class Lxc
  # Clone existing containers
  class Clone

    include Helpers
    include Helpers::Options
    include Helpers::Copies

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

    # @return [Hash] original and new container instances
    attr_reader :lxcs

    # Create new instance
    #
    # @param args [Hash]
    # @option args [String] :original existing container name
    # @option args [String] :new new container name
    def initialize(args={})
      configure!(args)
      @lxcs = {}
      @lxcs[:original] = Lxc.new(original)
      @lxcs[:new] = Lxc.new(new_name)
      @created = []
      validate!
    end

    # Create the clone
    #
    # @return [Lxc] new clone
    def clone!
      begin
        copy_original
        update_naming(:no_config)
        apply_custom_addressing if ipaddress
        lxc
      rescue Exception
        @created.map(&:destroy)
        raise
      end
    end

    private

    alias_method :name, :new_name

    # @return [Lxc] new lxc instance
    def lxc
      lxcs[:new]
    end

    # Add to list of created items
    #
    # @param thing [Object] item created
    def created(thing)
      @created << thing
    end

    # Validate current state
    #
    # @return [TrueClass]
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
      true
    end

    # Create copy of original container
    #
    # @return [TrueClass]
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
      true
    end

    # Initialize container copy (base file copy)
    #
    # @return [TrueClass]
    def copy_init
      directory = Storage::CloneDirectory.new(lxcs[:new].name, :dir => File.dirname(lxcs[:original].path.to_s))
      created(directory)
      %w(config fstab).each do |file|
        command("cp '#{lxcs[:original].path.join(file)}' '#{directory.target_path}'", :sudo => true)
      end
      true
    end

    # Copy into file system directory
    #
    # @return [String] path to new rootfs
    def copy_fs
      directory = Storage::CloneDirectory.new(lxcs[:new].name, :dir => File.dirname(lxcs[:original].path.to_s))
      created(directory)
      command("rsync -ax '#{lxcs[:original].rootfs}/' '#{File.join(directory.target_path, 'rootfs')}/'", :sudo => true)
      File.join(directory.target_path, 'rootfs')
    end

    # Copy into new virtual block device
    #
    # @return [String] path to new rootfs
    def copy_vbd
      storage = Storage::VirtualDevice.new(lxcs[:new].name, :tmp_dir => '/opt/lxc-vbd')
      created(storage)
      command("rsync -ax '#{lxcs[:original].rootfs}/' '#{storage.target_path}/'", :sudo => true)
      storage.target_path
    end

    # Copy into new LVM partition
    #
    # @note not implemented
    # @todo implement
    def copy_lvm
      raise 'Not implemented'
    end

    # Copy into new btrfs subvolume snapshot
    #
    # @return [String] path to new rootfs
    # @todo remove on failure
    def copy_btrfs
      rootfs_path = lxcs[:new].path.join('rootfs')
      command("btrfs subvolume snapshot '#{lxcs[:original].rootfs}' '#{rootfs_path}'", :sudo => true)
      rootfs_path
    end
  end
end
