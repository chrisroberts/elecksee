require 'elecksee'
require 'securerandom'
require 'fileutils'
require 'tmpdir'
require 'tempfile'
require 'etc'

class Lxc
  # Create ephemeral containers
  class Ephemeral

    include Helpers
    include Helpers::Options
    include Helpers::Copies

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
    option :ssh_key, '-S', :string, :default => '/opt/hw-lxc-config/id_rsa', :aliases => 'ssh-key', :desc => 'Deprecated: Provided for compatibility'
    option :lxc_dir, '-L', :string, :default => '/var/lib/lxc', :aliases => 'lxc-dir', :desc => 'Directory of LXC store'
    option :tmp_dir, '-T', :string, :default => '/tmp/lxc/ephemerals', :aliases => 'tmp-dir', :desc => 'Directory of ephemeral temp files'
    option :ephemeral_command, '-C', :string, :aliases => 'command'

    # @return [String] name of container
    attr_reader :name
    # @return [TrueClass, FalseClass] enable CLI output
    attr_reader :cli
    # @return [String] hostname of container
    attr_reader :hostname
    # @return [String] path to container
    attr_reader :path
    # @return [Lxc] instance of ephemeral
    attr_reader :lxc
    # @return [Storage::OverlayDirectory, Storage::VirtualDevice]
    attr_reader :ephemeral_device
    # @return [Storage::OverlayMount]
    attr_reader :ephemeral_overlay
    # @return [Array<Storage::VirtualDevice]
    attr_reader :ephemeral_binds

    # Create new instance
    #
    # @param args [Hash]
    # @option args [TrueClass, FalseClass] :cli enable CLI output
    def initialize(args={})
      configure!(args)
      @cli = args[:cli]
      @path = command("mktemp -d -p #{lxc_dir} #{original}-XXXXXXXXXXXX", :sudo => true).stdout.strip
      command("chmod 0755 #{@path}", :sudo => true)
      @name = File.basename(@path)
      @hostname = @name.gsub(%r{[^A-Za-z0-9\-]}, '')
      @ephemeral_binds = []
      @lxc = nil
    end

    # Trap signals to force cleanup
    #
    # @return [TrueClass]
    def register_traps
      %w(TERM INT QUIT).each do |sig|
        Signal.trap(sig){ cleanup && raise }
      end
      true
    end

    # Write output to CLI
    #
    # @return [TrueClass, FalseClass]
    def cli_output
      if(cli)
        puts "New ephemeral container started. (#{name})"
        puts "    - Connect using: sudo ssh -i #{ssh_key} root@#{lxc.container_ip(10)}"
        true
      else
        false
      end
    end

    # Start the ephemeral container
    #
    # @return [TrueClass]
    # @note generally should not be called directly
    # @see start!
    def start_action
      begin
        lxc.start
        if(ephemeral_command)
          lxc.wait_for_state(:running)
          lxc.container_command(ephemeral_command)
        else
          cli_output
          lxc.wait_for_state(:stopped)
        end
      ensure
        cleanup
      end
      true
    end

    # Create the ephemeral container
    #
    # @return [TrueClass]
    def create!
      setup
      true
    end

    # Start the ephemeral container
    #
    # @param args [Symbol] argument list
    # @return [TrueClass]
    # @note use :fork to fork startup
    def start!(*args)
      setup
      if(daemon)
        if(args.include?(:fork))
          register_traps
          fork do
            start_action
          end
        elsif(args.include?(:detach))
          cmd = [sudo, shell_wrapper.path].compact.map(&:strip)
          process = ChildProcess.build(*cmd)
          process.detach = true
          process.start
          shell_wrapper.delete
        else
          register_traps
          Process.daemon
          start_action
        end
      else
        register_traps
        start_action
      end
      true
    end

    # Bash based wrapper script to start ephemeral and clean up
    # ephemeral resources on exit
    #
    # @return [Tempfile] wrapper script
    def shell_wrapper
      content = ['#!/bin/bash']
      content << 'scrub()' << '{'
      content << "umount #{ephemeral_overlay.target}"
      ephemeral_binds.map do |bind|
        unless(bind.device_path == :none)
          if(File.file?(bind.device_path))
            content << "rm #{bind.device_path}"
          elsif(File.directory?(bind.device_path))
            content << "rm -rf #{bind.device_path}"
          end
        end
        unless(bind.mount_path == :none)
          if(File.directory?(bind.mount_path))
            content << "rmdir #{bind.mount_path}"
          end
        end
      end
      case ephemeral_device
      when Storage::OverlayDirectory
        if(File.directory?(ephemeral_device.overlay_path))
          content << "rm -rf #{ephemeral_device.overlay_path}"
        end
      when Storage::VirtualDevice
        if(ephemeral_device.mounted?)
          content << "umount #{ephemeral_device.mount_path}"
        end
        unless(ephemeral_device.device_path == :none)
          if(File.file?(ephemeral_device.device_path))
            content << "rm #{ephemeral_device.device_path}"
          elsif(File.directory?(ephemeral_device.device_path))
            content << "rm -rf #{ephemeral_device.device_path}"
          end
        end
        unless(ephemeral_device.mount_path == :none)
          if(File.directory?(ephemeral_device.mount_path))
            content << "rmdir #{ephemeral_device.mount_path}"
          end
        end
      end
      if(lxc.path.to_path.split('/').size > 1)
        content << "rm -rf #{lxc.path.to_path}"
      end
      content << '}'
      content << 'trap scrub SIGTERM SIGINT SIGQUIT'
      content << "lxc-start -n #{lxc.name} -d"
      content << 'sleep 1'
      content << "lxc-wait -n #{lxc.name} -s STOPPED"
      content << 'scrub'
      tmp = Tempfile.new('elecksee')
      tmp.chmod(0700)
      tmp.puts content.join("\n")
      tmp.close
      tmp
    end

    # Stop container and cleanup ephemeral items
    #
    # @return [TrueClass, FalseClass]
    def cleanup
      lxc.stop if lxc.running?
      @ephemeral_overlay.unmount
      @ephemeral_binds.map(&:destroy)
      @ephemeral_device.destroy
      if(lxc.path.to_path.split('/').size > 1)
        command("rm -rf #{lxc.path.to_path}", :sudo => true)
        true
      else
        $stderr.puts "This path seems bad and I won't remove it: #{lxc.path.to_path}"
        false
      end
    end

    private

    # Setup the ephemeral container resources
    #
    # @return [TrueClass]
    def setup
      create
      build_overlay
      update_naming
      discover_binds
      apply_custom_networking if ipaddress
      true
    end

    # Create the overlay
    #
    # @return [TrueClass, FalseClass]
    def build_overlay
      if(directory)
        @ephemeral_device = Storage::OverlayDirectory.new(name, :tmp_dir => directory.is_a?(String) ? directory : tmp_dir)
      else
        @ephemeral_device = Storage::VirtualDevice.new(name, :size => device, :tmp_fs => !device, :tmp_dir => tmp_dir)
        @ephemeral_device.mount
      end
      @ephemeral_overlay = Storage::OverlayMount.new(
        :base => Lxc.new(original).rootfs.to_path,
        :overlay => ephemeral_device.target_path,
        :target => lxc.path.join('rootfs').to_path,
        :overlay_type => union
      )
      @ephemeral_overlay.mount
    end

    # Create the container
    #
    # @return [TrueClass]
    def create
      Dir.glob(File.join(lxc_dir, original, '*')).each do |o_path|
        next unless File.file?(o_path)
        command("cp #{o_path} #{File.join(path, File.basename(o_path))}", :sudo => true)
      end
      @lxc = Lxc.new(name)
      command("mkdir -p #{lxc.path.join('rootfs')}", :sudo => true)
      update_net_hwaddr
      true
    end

    # Discover any bind mounts defined
    #
    # @return [TrueClass]
    # @todo discovered binds for ephemeral are all tmpfs for
    #   now. should default to overlay mount, make virtual
    #   device and tmpfs optional
    def discover_binds
      contents = File.readlines(lxc.path.join('fstab')).each do |line|
        parts = line.split(' ')
        if(parts[3] == 'bind')
          source = parts.first
          target = parts[1].sub(%r{^.+rootfs/}, '')
          container_target = lxc.rootfs.join(target).to_path
          device = Storage::VirtualDevice.new(target.gsub('/', '_'), :tmp_fs => true)
          device.mount
          FileUtils.mkdir_p(container_target)
          ephemeral_binds << device
          if(union == 'overlayfs')
            "none #{container_target} overlayfs upperdir=#{device.mount_path},lowerdir=#{source} 0 0"
          else
            "none #{container_target} aufs br=#{device.mount_path}=rw:#{source}=ro,noplink 0 0"
          end
        else
          line
        end
      end
      # If bind option used, bind in for rw
      if(bind)
        command("mkdir -p #{lxc.rootfs.join(bind).to_path}", :sudo => true)
        contents << "#{bind} #{lxc.rootfs.join(bind)} none bind 0 0\n"
      end
      write_file(lxc.path.join('fstab'), contents.join)
      true
    end

  end
end
