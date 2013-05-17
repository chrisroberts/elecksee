require File.expand_path(File.join(File.dirname(__FILE__), 'lxc.rb'))
require 'securerandom'
require 'fileutils'
require 'tmpdir'

class Lxc

  class Ephemeral

    include Helpers

    NAME_FILES = %w(fstab config)
    HOSTNAME_FILES = %w(
      rootfs/etc/hostname
      rootfs/etc/hosts
      rootfs/etc/sysconfig/network
      rootfs/etc/sysconfig/network-scripts/ifcfg-eth0
    )
    
    class << self
      attr_reader :options
      
      def option(name, short, type, args={})
        @options ||= {}
        @options[name] = args.merge(:short => short, :type => type)
        instance_eval do
          attr_accessor name.to_sym
        end
      end
    end

    option :original, '-o', :string, :required => true, :desc => 'Original container name'
    option :ipaddress, '-I', :string, :desc => 'Custom IP address'
    option :gateway, '-G', :string, :desc => 'Custom gateway'
    option :netmask, '-N', :string, :default => '255.255.255.0', :desc => 'Custom netmask'
    option :device, '-D', :integer, :desc => 'Create VBD for overlay of size {SIZE}M'
    option :directory, '-z', :boolean, :desc => 'Use host based directory for overlay'
    option :union, '-U', :string, :desc => 'Overlay FS to use (overlayfs or aufs)'
    option :daemon, '-d', :boolean, :desc => 'Run as a daemon'
    option :bind, '-b', :string, :desc => 'Bind provided directory (non-ephemeral)'
    option :user, '-u', :string, :desc => 'Deprecated: Provided for compatibility'
    option :ssh_key, '-S', :string, :aliases => 'ssh-key', :desc => 'Deprecated: Provided for compatibility'
    option :lxc_dir, '-L', :string, :default => '/var/lib/lxc', :aliases => 'lxc-dir', :desc => 'Directory of LXC store'
    option :tmp_dir, '-T', :string, :default => '/tmp/lxc/ephemerals', :aliases => 'tmp-dir', :desc => 'Directory of ephemeral temp files'

    attr_reader :name
    attr_reader :cli
    attr_reader :hostname
    attr_reader :path
    attr_reader :lxc
    attr_reader :ephemeral_device
    attr_reader :ephemeral_overlay
    attr_reader :ephemeral_binds

    def initialize(args={})
      configure!(args)
      @cli = args[:cli]
      @path = Dir.mktmpdir(File.join(lxc_dir, original))
      @name = File.basename(@path)
      @hostname = @name.gsub(%r{[^A-Za-z0-9\-]}, '')
      @ephemeral_binds = []
      @lxc = nil
    end

    def register_traps
      %w(TERM INT QUIT).each do |sig|
        Signal.trap(sig){ cleanup }
      end
    end
    
    def start!(*args)
      register_traps
      setup
      if(cli)
        puts 'New ephemeral container started.'
        puts "    - Connect using: sudo lxc-console -n #{name}"
      end
      if(daemon)
        if(args.include?(:fork))
          fork do
            lxc.start
            lxc.wait_for_state(:stopped)
            cleanup
          end
        else
          Process.daemon
          lxc.start
          lxc.wait_for_state(:stopped)
          cleanup
        end
      else
        lxc.start
        lxc.wait_for_state(:stopped)
        cleanup
      end
    end

    def cleanup
      lxc.stop
      @ephemeral_overlay.unmount
      @ephemeral_binds.map(&:destroy)
      @ephemeral_device.destroy
      FileUtils.rm_rf(lxc.path.to_path)
      true
    end

    private

    def configure!(args)
      self.class.options.each do |name, opts|
        argv = args.detect{|k,v| (Array(opts[:aliases]) + Array(opts[:short]) + [name]).include?(k)}
        argv = argv.last if argv
        argv ||= opts[:default]
        if(argv)
          check_type!(name, argv, opts[:type])
          self.send("#{name}=", argv)
        else
          if(opts[:required])
            raise ArgumentError.new "Missing required argument: #{name}"
          end
        end
      end
      if(ipaddress && gateway.nil?)
        self.gateway = ipaddress.sub(%r{\d+$}, '1')
      end
    end

    def check_type!(arg_name, val, type)
      valid = false
      case type
      when :string
        valid = val.is_a?(String)
      when :boolean
        valid = val.is_a?(TrueClass) || val.is_a?(FalseClass)
      when :integer
        valid = val.is_a?(Numeric)
      end
      raise ArgumentError.new "Invalid type provided for #{arg_name}. Expecting value type of: #{type.inspect} Got: #{val.class} -  #{val}" unless valid
    end

    def setup
      create
      discover_binds
      build_overlay
      apply_custom_networking if ipaddress
      update_naming
    end

    def build_overlay
      if(directory)
        @ephemeral_device = OverlayDirectory.new(name, :tmp_dir => directory.is_a?(String) ? directory : nil)
      else
        @ephemeral_device = VirtualDevice.new(name, :size => device, :tmp_fs => !device)
        @ephemeral_device.mount
      end
      @ephemeral_overlay = OverlayMount.new(
        :base => Lxc.new(original).rootfs.to_path,
        :overlay => ephemeral_device.target_path,
        :target => lxc.rootfs.to_path,
        :overlay_type => union
      )
      @ephemeral_overlay.mount
    end

    def create
      Dir.glob(File.join(lxc_dir, original, '*')).each do |o_path|
        next unless File.file?(o_path)
        FileUtils.copy(o_path, File.join(path, File.basename(o_path)))
      end
      @lxc = Lxc.new(name)
      contents = File.readlines(lxc.config)
      File.open(lxc.config, 'w') do |file|
        contents.each do |line|
          if(line.strip.start_with?('lxc.network.hwaddr'))
            file.write "00:16:3e#{SecureRandom.hex(3).gsub(/(..)/, ':\1')}"
          else
            file.write line
          end
        end
      end
    end

    # TODO: Discovered binds for ephemeral are all tmpfs for now.
    def discover_binds
      contents = File.readlines(lxc.path.join('fstab'))
      File.open(lxc.path.join('fstab'), 'w') do |file|
        contents.each do |line|
          parts = line.split(' ')
          if(parts[3] == 'bind')
            source = parts.first
            target = parts[1].sub(%r{^.+rootfs/}, '')
            container_target = lxc.rootfs.join(target).to_path
            device = VirtualDevice.new(target.gsub('/', '_'), :tmp_fs => true)
            device.mount
            FileUtils.mkdir_p(container_target)
            ephemeral_binds << device
            if(union == 'overlayfs')
              file.write "none #{container_target} overlayfs upperdir=#{device.mount_path},lowerdir=#{source} 0 0"
            else
              file.write "none #{container_target} aufs br=#{device.mount_path}=rw:#{source}=ro,noplink 0 0"
            end
          else
            file.write line
          end
        end
        # If bind option used, bind in for rw
        if(bind)
          FileUtils.mkdir_p(lxc.rootfs.join(bind).to_path)
          file.write "#{bind} #{lxc.rootfs.join(bind)} none bind 0 0"
        end
      end
    end
    
    def update_naming
      NAME_FILES.each do |file|
        next unless File.exists?(lxc.path.join(file))        
        contents = File.read(lxc.path.join(file))
        File.open(lxc.path.join(file), 'w') do |new_file|
          new_file.write contents.gsub(original, name)
        end
      end
      HOSTNAME_FILES.each do |file|
        next unless File.exists?(lxc.path.join(file))
        contents = File.read(lxc.path.join(file))
        File.open(lxc.path.join(file), 'w') do |new_file|
          new_file.write contents.gsub(original, hostname)
        end
      end
    end

    def el_platform?
      lxc.rootfs.join('etc/redhat-release').exist?
    end
    
    def apply_custom_networking
      if(el_platform?)
        File.open(@lxc.rootfs.join('etc/sysconfig/network-scripts/ifcfg-eth0'), 'w') do |file|
          file.write <<-EOF
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
        end
        File.open(@lxc.rootfs.join('etc/sysconfig/network'), 'w') do |file|
          file.write <<-EOF
NETWORKING=yes
HOSTNAME=#{hostname}
EOF
        end
        File.open(@lxc.rootfs.join('etc/rc.local'), 'w') do |file|
          file.puts "hostname #{hostname}"
        end
      else
        File.open(@lxc.rootfs.join('etc/network/interfaces'), 'w') do |file|
          file.write <<-EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
address #{ipaddress}
netmask #{netmask}
gateway #{gateway}
EOF
        end
      end
    end

    class OverlayMount

      include Helpers
      
      attr_reader :base
      attr_reader :overlay
      attr_reader :target
      attr_reader :overlay_type
      
      def initialize(args={})
        validate!(args)
        @base = args[:base]
        @overlay = args[:overlay]
        @target = args[:target]
        @overlay_type = args[:overlay_type] || 'overlayfs'
      end

      def mount
        unless(mounted?)
          case overlay_type
          when 'aufs'
            cmd = "mount -t aufs -o br=#{overlay}=rw:#{base}=ro,noplink none #{target}"
          when 'overlayfs'
            cmd = "mount -t overlayfs -oupperdir=#{overlay},lowerdir=#{base} none #{target}"
          else
            raise "Invalid overlay type provided: #{overlay_type}"
          end
          command(cmd)
          true
        end
      end

      def mounted?
        command("mount").stdout.include?(target)
      end
      
      def unmount
        if(mounted?)
          command("umount #{target}")
          true
        end
      end

      private

      def validate!(args)
        [:base, :overlay, :target].each do |required|
          unless(args[required])
            raise ArgumentError.new "Missing required argument: #{required}"
          end
          unless(File.directory?(args[required]))
            raise TypeError.new "Provided argument is not a valid directory for #{required}: #{args[required]}"
          end
        end
      end
    end
    
    class OverlayDirectory
      
      attr_reader :name
      attr_reader :tmp_dir

      def initialize(name, args={})
        @name = name
        @tmp_dir = args[:tmp_dir] || '/tmp/lxc/ephemerals'
        create
      end

      def overlay_path
        File.join(tmp_dir, 'virt-overlays', name)
      end
      alias_method :target_path, :overlay_path

      def create
        unless(File.directory?(overlay_path))
          FileUtils.mkdir_p(overlay_path)
        end
      end

      def destroy
        FileUtils.rm_rf(overlay_path) if File.directory?(overlay_path)
      end
        
    end
    
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
          command("mount -t #{fs_type}#{mount_options} #{device_path} #{mount_path}")
          true
        end
      end

      def unmount
        if(mounted?)
          command("umount #{mount_path}")
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
end
