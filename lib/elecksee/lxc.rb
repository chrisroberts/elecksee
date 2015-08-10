require 'elecksee'
require 'securerandom'
require 'shellwords'
require 'pathname'
require 'tmpdir'
require 'rye'

class Lxc

  # Pathname#join does not act like File#join when joining paths that
  # begin with '/', and that's dumb. So we'll make our own Pathname,
  # with a #join that uses File
  class Pathname < ::Pathname
    # Join arguments using ::File.join
    #
    # @param args [String] argument list
    # @return [String]
    def join(*args)
      self.class.new(::File.join(self.to_path, *args))
    end
  end

  include Helpers

  # @return [String] name of container
  attr_reader :name
  # @return [String] base path of container
  attr_reader :base_path
  # @return [String] path to dnsmasq lease file
  attr_reader :lease_file
  # @return [String] network device to use for ssh connection
  attr_reader :preferred_device
  # @return [String, NilClass] path to default ssh key
  attr_accessor :ssh_key
  # @return [String, NilClass] ssh password
  attr_accessor :ssh_password
  # @return [String, NilClass]  ssh user
  attr_accessor :ssh_user

  class << self

    include Helpers

    # @return [Truthy, String] use sudo when required (set to string for custom sudo command)
    attr_accessor :use_sudo
    # @return [String] base path for containers
    attr_accessor :base_path
    # @return [Symbol] :mixlib_shellout or :childprocess
    attr_accessor :shellout_helper
    # @return [String, NilClass] path to default ssh key
    attr_accessor :default_ssh_key
    # @return [String, NilClass] default ssh password
    attr_accessor :default_ssh_password
    # @return [String, NilClass] default ssh user
    attr_accessor :default_ssh_user
    # @return [Symbol] default command method
    attr_accessor :container_command_via

    # @return [String] sudo command
    def sudo
      case use_sudo
      when TrueClass
        'sudo '
      when String
        "#{use_sudo} "
      end
    end

    # @return [String] base path for containers
    def base_path
      @base_path || '/var/lib/lxc'
    end

    # Currently running container names
    #
    # @return [Array<String>]
    def running
      full_list[:running]
    end

    # Currently stopped container names
    #
    # @return [Array<String>]
    def stopped
      full_list[:stopped]
    end

    # Currently frozen container names
    #
    # @return [Array<String>]
    def frozen
      full_list[:frozen]
    end

    # Container currently exists
    #
    # @param name [String] name of container
    # @return [TrueClass, FalseClass]
    def exists?(name)
      list.include?(name)
    end

    # List of all containers
    #
    # @return [Array<String>] container names
    def list
      run_command('lxc-ls', :sudo => true).
        stdout.split(/\s/).map(&:strip).compact
    end

    # Information available for given container
    #
    # @param name [String] name of container
    # @return [Hash]
    def info(name)
      if(exists?(name))
        info = run_command("#{sudo}lxc-info -n #{name}", :allow_failure_retry => 3, :allow_failure => true)
      end
      if(info)
        Hash[
          info.stdout.split("\n").map do |string|
            string.split(': ').map(&:strip)
          end.map do |key, value|
            key = key.tr(' ', '_').downcase.to_sym
            if(key == :state)
              value = value.downcase.to_sym
            elsif(value.to_i.to_s == value)
              value = value.to_i
            end
            [key, value]
          end
        ]
      else
        Hash[:state, :unknown, :pid, -1]
      end
    end

    # Full list of containers grouped by state
    #
    # @return [Hash]
    def full_list
      res = {}
      list.each do |item|
        item_info = info(item)
        res[item_info[:state]] ||= []
        res[item_info[:state]] << item
      end
      res
    end

    # IP address is currently active
    #
    # @param ip [String]
    # @return [TrueClass, FalseClass]
    def connection_alive?(ip)
      %x{ping -c 1 -W 1 #{ip}}
      $?.exitstatus == 0
    end
  end

  # Create new instance
  #
  # @param name [String] container name
  # @param args [Hash]
  # @option args [String] :base_path path to container
  # @option args [String] :dnsmasq_lease_file path to lease file
  # @option args [String] :net_device network device within container for ssh connection
  # @option args [String] :ssh_key path to ssh key
  # @option args [String] :ssh_password ssh password
  # @option args [String] :ssh_user ssh user
  def initialize(name, args={})
    @name = name
    @base_path = args[:base_path] || self.class.base_path
    @lease_file = args[:dnsmasq_lease_file] || '/var/lib/misc/dnsmasq.leases'
    @preferred_device = args[:net_device]
    @ssh_key = args.fetch(:ssh_key, self.class.default_ssh_key)
    @ssh_password = args.fetch(:ssh_password, self.class.default_ssh_password)
    @ssh_user = args.fetch(:ssh_user, self.class.default_ssh_user)
  end

  # @return [TrueClass, FalseClass] container exists
  def exists?
    self.class.exists?(name)
  end

  # @return [TrueClass, FalseClass] container is currently running
  def running?
    self.class.info(name)[:state] == :running
  end

  # @return [TrueClass, FalseClass] container is currently stopped
  def stopped?
    self.class.info(name)[:state] == :stopped
  end

  # @return [TrueClass, FalseClass] container is currently frozen
  def frozen?
    self.class.info(name)[:state] == :frozen
  end

  # Current IP address of container
  #
  # @param retries [Integer] number of times to retry discovery
  # @param raise_on_fail [TrueClass, FalseClass] raise exception on failure
  # @return [String, NilClass] IP address
  # @note retries are executed on 3 second sleep intervals
  def container_ip(retries=0, raise_on_fail=false)
    (retries.to_i + 1).times do
      ip = info_detected_address ||
        proc_detected_address ||
        hw_detected_address ||
        leased_address ||
        lxc_stored_address
      if(ip.is_a?(Array))
        # Filter any found loopbacks
        ip.delete_if{|info| info[:device].start_with?('lo') }
        ip = ip.detect do |info|
          if(@preferred_device)
            info[:device] == @preferred_device
          else
            true
          end
        end
        ip = ip[:address] if ip
      end
      return ip if ip && self.class.connection_alive?(ip)
      log.warn "LXC IP discovery: Failed to detect live IP"
      sleep(3) if retries > 0
    end
    raise "Failed to detect live IP address for container: #{name}" if raise_on_fail
  end

  # Container address defined within the container's config file
  #
  # @return [String, NilClass] IP address
  def lxc_stored_address
    if(File.exists?(container_config))
      ip = File.readlines(container_config).detect{|line|
        line.include?('ipv4')
      }.to_s.split('=').last.to_s.strip
      if(ip.to_s.empty?)
        nil
      else
        log.info "LXC Discovery: Found container address via storage: #{ip}"
        ip
      end
    end
  end

  # Container address discovered via dnsmasq lease
  #
  # @return [String, NilClass] IP address
  def leased_address
    ip = nil
    if(File.exists?(@lease_file))
      leases = File.readlines(@lease_file).map{|line| line.split(' ')}
      leases.each do |lease|
        if(lease.include?(name))
          ip = lease[2]
        end
      end
    end
    if(ip.to_s.empty?)
      nil
    else
      log.info "LXC Discovery: Found container address via DHCP lease: #{ip}"
      ip
    end
  end

  # Container address discovered via info
  #
  # @return [String, NilClass] IP address
  def info_detected_address
    self.class.info(name)[:ip]
  end

  # Container address discovered via device
  #
  # @return [String, NilClass] IP address
  def hw_detected_address
    if(container_config.readable?)
      hw = File.readlines(container_config).detect{|line|
        line.include?('hwaddr')
      }.to_s.split('=').last.to_s.downcase
      if(File.exists?(container_config) && !hw.empty?)
        running? # need to do a list!
        ip = File.readlines('/proc/net/arp').detect{|line|
          line.downcase.include?(hw)
        }.to_s.split(' ').first.to_s.strip
        if(ip.to_s.empty?)
          nil
        else
          log.info "LXC Discovery: Found container address via HW addr: #{ip}"
          ip
        end
      end
    end
  end

  # Container address discovered via process
  #
  # @param base [String] path to netns
  # @return [String, NilClass] IP address
  def proc_detected_address(base='/run/netns')
    if(pid != -1)
      Dir.mktmpdir do |t_dir|
        name = File.basename(t_dir)
        path = File.join(base, name)
        system("#{sudo}mkdir -p #{base}")
        system("#{sudo}ln -s /proc/#{pid}/ns/net #{path}")
        res = %x{#{sudo}ip netns exec #{name} ip -4 addr show scope global | grep inet}
        system("#{sudo}rm -f #{path}")
        ips = res.split("\n").map do |line|
          parts = line.split(' ')
          {:address => parts[1].to_s.sub(%r{/.+$}, ''), :device => parts.last}
        end
        ips.empty? ? nil : ips
      end
    end
  end

  # @return [Pathname] path to container
  def container_path
    Pathname.new(@base_path).join(name)
  end
  alias_method :path, :container_path

  # @return [Pathname] path to configuration file
  def container_config
    container_path.join('config')
  end
  alias_method :config, :container_config

  # @return [Pathname] path to rootfs
  def container_rootfs
    if(File.exists?(config))
      r_path = File.readlines(config).detect do |line|
        line.start_with?('lxc.rootfs')
      end.to_s.split('=').last.to_s.strip
    end
    r_path.to_s.empty? ? container_path.join('rootfs') : Pathname.new(r_path)
  end
  alias_method :rootfs, :container_rootfs

  # Expand path within containers rootfs
  #
  # @param path [String] relative path
  # @return [Pathname] full path within container
  def expand_path(path)
    container_rootfs.join(path)
  end

  # @return [Symbol] current state
  def state
    self.class.info(name)[:state]
  end

  # @return [Integer, Symbol] process ID or :unknown
  def pid
    self.class.info(name)[:pid]
  end

  # Start the container
  #
  # @param args [Symbol] argument list (:no_daemon to foreground)
  # @return [self]
  def start(*args)
    if(args.include?(:no_daemon))
      run_command("lxc-start -n #{name}", :sudo => true)
    else
      run_command("lxc-start -n #{name} -d", :sudo => true)
      wait_for_state(:running)
    end
    self
  end

  # Stop the container
  #
  # @return [self]
  def stop
    run_command("lxc-stop -n #{name}", :allow_failure_retry => 3, :sudo => true)
    wait_for_state([:stopped, :unknown])
    self
  end

  # Freeze the container
  #
  # @return [self]
  def freeze
    run_command("lxc-freeze -n #{name}", :sudo => true)
    wait_for_state(:frozen)
    self
  end

  # Unfreeze the container
  #
  # @return [self]
  def unfreeze
    run_command("lxc-unfreeze -n #{name}", :sudo => true)
    wait_for_state(:running)
    self
  end

  # Shutdown the container
  #
  # @return [self]
  def shutdown
    # This block is for fedora/centos/anyone else that does not like lxc-shutdown
    if(running?)
      container_command('shutdown -h now')
      wait_for_state(:stopped, :timeout => 120)
      # If still running here, something is wrong
      if(running?)
        run_command("lxc-stop -n #{name}", :sudo => true)
        wait_for_state(:stopped, :timeout => 120)
        if(running?)
          raise "Failed to shutdown container: #{name}"
        end
      end
    end
    self
  end

  # Destroy the container
  #
  # @return [self]
  def destroy
    unless stopped?
      stop
    end
    run_command("lxc-destroy -n #{name}", :sudo => true)
    self
  end

  # Execute command within the container
  #
  # @param command [String] command to execute
  # @param opts [Hash] options passed to #tmp_execute_script
  # @return [CommandResult]
  # @note container must be stopped
  def execute(command, opts={})
    if(stopped?)
      cmd = Shellwords.split(command)
      result = nil
      begin
        tmp_execute_script(command, opts) do |script_path|
          result = run_command("lxc-execute -n #{name} -- #{script_path}", :sudo => true)
        end
      rescue => e
        if(e.result.stderr.downcase.include?('failed to find an lxc-init'))
          $stderr.puts "ERROR: Missing `lxc-init` installation on container (#{name}). Install lxc-init on container before using `#execute`!"
        end
        raise
      end
    else
      raise "Cannot execute against running container (#{name})"
    end
  end

  # Provide connection to running container
  #
  # @return [Rye::Box]
  def connection(args={})
    Rye::Box.new(args.fetch(:ip, container_ip(3)),
      :user => ssh_user,
      :password => ssh_password,
      :password_prompt => false,
      :keys => [ssh_key],
      :safe => false,
      :paranoid => false
    )
  end

  # Execute command within running container
  #
  # @param command [String]
  # @param args [Hash]
  # @option args [Integer] :timeout
  # @option args [TrueClass, FalseClass] :live_stream
  # @option args [TrueClass, FalseClass] :raise_on_failure
  # @return [CommandResult]
  def direct_container_command(command, args={})
    if(args.fetch(:run_as, Lxc.container_command_via).to_sym == :ssh)
      begin
        result = connection(args).execute command
        CommandResult.new(result)
      rescue Rye::Err => e
        if(args[:raise_on_failure])
          raise CommandFailed.new(
            "Command failed: #{command}",
            CommandResult.new(e)
          )
        else
          false
        end
      end
    else
      command(
        "lxc-attach -n #{name} -- #{command}",
        args.merge(:sudo => true)
      )
    end
  end
  alias_method :knife_container, :direct_container_command

  # Wait for container to reach given state
  #
  # @param desired_state [Symbol, Array<Symbol>]
  # @param args [Hash]
  # @option args [Integer] :timeout
  # @option args [Numeric] :sleep_interval
  # @return [self]
  def wait_for_state(desired_state, args={})
    args[:sleep_interval] ||= 1.0
    wait_total = 0.0
    desired_state = [desired_state].flatten.compact.map(&:to_sym)
    until(desired_state.include?(state) || (args[:timeout].to_i > 0 && wait_total.to_i > args[:timeout].to_i))
      sleep(args[:sleep_interval])
      wait_total += args[:sleep_interval]
    end
    self
  end

  # Write command to temporary file with networking enablement wrapper
  # and yield relative path
  #
  # @param command [String]
  # @param opts [Hash]
  # @options opts [TrueClass, FalseClass] enable networking
  # @yield block to execute
  # @yieldparam command_script [String] path to file
  # @return [Object] result of block
  def tmp_execute_script(command, opts)
    script_path = "tmp/#{SecureRandom.uuid}"
    File.open(rootfs.join(script_path), 'w') do |file|
      file.puts '#!/bin/sh'
      unless(opts[:networking] == false)
        file.write <<-EOS
/etc/network/if-pre-up.d/bridge > /dev/null 2>&1
ifdown eth0 > /dev/null 2>&1
ifup eth0 > /dev/null 2>&1
EOS
      end
      file.puts command
      file.puts "RESULT=$?"
      unless(opts[:networking] == false)
        file.puts "ifdown eth0 > /dev/null 2>&1"
      end
      file.puts "exit $RESULT"
    end
    FileUtils.chmod(0755, rootfs.join(script_path))
    begin
      yield "/#{script_path}"
    ensure
      FileUtils.rm(rootfs.join(script_path))
    end
  end

  # Run command within container
  #
  # @param cmd [String] command to run
  # @param retries [Integer] number of retry attempts
  # @return [CommandResult]
  # @note retries are over 1 second intervals
  def container_command(cmd, retries=1)
    begin
      detect_home(true)
      direct_container_command(cmd,
        :ip => container_ip(5),
        :live_stream => STDOUT,
        :raise_on_failure => true
      )
    rescue => e
      if(retries.to_i > 0)
        log.info "Encountered error running container command (#{cmd}): #{e}"
        log.info "Retrying command..."
        retries = retries.to_i - 1
        sleep(1)
        retry
      else
        raise e
      end
    end
  end

end

Lxc.default_ssh_key = [
  File.join(Dir.home, '.ssh', 'lxc_container_rsa'),
  '/opt/hw-lxc-config/id_rsa',
].detect{|key| File.exists?(key) }
Lxc.default_ssh_user = 'root'
Lxc.container_command_via = :attach

# Monkey
class Rye::Box
  def execute(*args, &block)
    method_missing(*args, &block)
  end
end
