require 'elecksee'

class Lxc
  # Helper modules
  module Helpers

    autoload :Copies, 'elecksee/helpers/copies'
    autoload :Options, 'elecksee/helpers/options'

    # @return [String] sudo command string
    def sudo
      Lxc.sudo
    end

    # Shellout wrapper
    #
    # @param cmd [String]
    # @param args [Hash]
    # @option args [Integer] :allow_failure_retry number of retries
    # @option args [Numeric] :timeout max execution time
    # @option args [TrueClass, FalseClass] :sudo use sudo
    # @option args [TrueClass, FalseClass] :allow_failure don't raise on error
    # @return [CommandResult]
    def run_command(cmd, args={})
      result = nil
      cmd_type = Lxc.shellout_helper
      unless(cmd_type)
        if(defined?(ChildProcess))
          cmd_type = :childprocess
        else
          cmd_type = :mixlib_shellout
        end
      end
      com_block = nil
      case cmd_type
      when :childprocess
        require 'tempfile'
        com_block = lambda{ child_process_command(cmd, args) }
      when :mixlib_shellout
        require 'mixlib/shellout'
        com_block = lambda{ mixlib_shellout_command(cmd, args) }
      else
        raise ArgumentError.new("Unknown shellout helper provided: #{cmd_type}")
      end
      result = defined?(Bundler) ? Bundler.with_clean_env{ com_block.call } : com_block.call
      result == false ? false : CommandResult.new(result)
    end

    # Shellout using childprocess
    #
    # @param cmd [String]
    # @param args [Hash]
    # @option args [Integer] :allow_failure_retry number of retries
    # @option args [Numeric] :timeout max execution time
    # @option args [TrueClass, FalseClass] :sudo use sudo
    # @option args [TrueClass, FalseClass] :allow_failure don't raise on error
    # @return [ChildProcess::AbstractProcess]
    def child_process_command(cmd, args)
      retries = args[:allow_failure_retry].to_i
      cmd = [sudo, cmd].join(' ') if args[:sudo]
      begin
        s_out = Tempfile.new('stdout')
        s_err = Tempfile.new('stderr')
        s_out.sync
        s_err.sync
        c_proc = ChildProcess.build(*Shellwords.split(cmd))
        c_proc.environment.merge('HOME' => detect_home)
        c_proc.io.stdout = s_out
        c_proc.io.stderr = s_err
        c_proc.start
        begin
          c_proc.poll_for_exit(args[:timeout] || 1200)
        rescue ChildProcess::TimeoutError
          c_proc.stop
        ensure
          raise CommandFailed.new("Command failed: #{cmd}", CommandResult.new(c_proc)) if c_proc.crashed?
        end
        c_proc
      rescue CommandFailed
        if(retries > 0)
          log.warn "LXC run command failed: #{cmd}"
          log.warn "Retrying command. #{args[:allow_failure_retry].to_i - retries} of #{args[:allow_failure_retry].to_i} retries remain"
          sleep(0.3)
          retries -= 1
          retry
        elsif(args[:allow_failure])
          false
        else
          raise
        end
      end
    end

    # Shellout using mixlib shellout
    #
    # @param cmd [String]
    # @param args [Hash]
    # @option args [Integer] :allow_failure_retry number of retries
    # @option args [Numeric] :timeout max execution time
    # @option args [TrueClass, FalseClass] :sudo use sudo
    # @option args [TrueClass, FalseClass] :allow_failure don't raise on error
    # @return [Mixlib::ShellOut]
    def mixlib_shellout_command(cmd, args)
      retries = args[:allow_failure_retry].to_i
      cmd = [sudo, cmd].join(' ') if args[:sudo]
      shlout = nil
      begin
        shlout = Mixlib::ShellOut.new(cmd,
          :logger => defined?(Chef) && defined?(Chef::Log) ? Chef::Log.logger : log,
          :live_stream => args[:livestream] ? STDOUT : nil,
          :timeout => args[:timeout] || 1200,
          :environment => {'HOME' => detect_home}
        )
        shlout.run_command
        shlout.error!
        shlout
      rescue Mixlib::ShellOut::ShellCommandFailed, CommandFailed, Mixlib::ShellOut::CommandTimeout => e
        if(retries > 0)
          log.warn "LXC run command failed: #{cmd}"
          log.warn "Retrying command. #{args[:allow_failure_retry].to_i - retries} of #{args[:allow_failure_retry].to_i} retries remain"
          sleep(0.3)
          retries -= 1
          retry
        elsif(args[:allow_failure])
          false
        else
          raise CommandFailed.new(e, CommandResult.new(shlout))
        end
      end
    end
    alias_method :command, :run_command

    # @return [Logger] logger instance
    def log
      if(defined?(Chef))
        Chef::Log
      else
        unless(@logger)
          require 'logger'
          @logger = Logger.new('/dev/null')
        end
        @logger
      end
    end

    # Detect HOME if environment variable is not set
    #
    # @param set_if_missing [TrueClass, FalseClass] set environment variable if missing
    # @return [String] value detected
    # @note if detection fails, first writeable path is used from /root or /tmp
    def detect_home(set_if_missing=false)
      if(ENV['HOME'] && Pathname.new(ENV['HOME']).absolute?)
        ENV['HOME']
      else
        home = File.directory?('/root') && File.writable?('/root') ? '/root' : '/tmp'
        if(set_if_missing)
          ENV['HOME'] = home
        end
        home
      end
    end

  end

  # Command failure class
  class CommandFailed < StandardError

    # @return [StandardError] original exception
    attr_accessor :original
    # @return [Object] command result
    attr_accessor :result

    # Create new instance
    #
    # @param orig [StandardError] original exception
    # @param result [Object] command result
    def initialize(orig, result=nil)
      @original = orig
      @result = result
      super(orig.to_s)
    end
  end

  # Command exceeded timeout
  class Timeout < CommandFailed
  end

  # Result of command
  class CommandResult

    # @return [Object] original result
    attr_reader :original
    # @return [IO] stdout of command
    attr_reader :stdout
    # @return [IO] stderr of command
    attr_reader :stderr

    # Create new instance
    #
    # @param result [Object] result of command
    def initialize(result)
      @original = result
      if(result.class.ancestors.map(&:to_s).include?('ChildProcess::AbstractProcess'))
        extract_childprocess
      elsif(result.class.to_s == 'Mixlib::ShellOut')
        extract_shellout
      elsif(result.class.to_s == 'Rye::Err' || result.class.to_s == 'Rye::Rap')
        extract_rye
      else
        raise TypeError.new("Unknown process result type received: #{result.class}")
      end
    end

    # Extract information from childprocess result
    def extract_childprocess
      original.io.stdout.rewind
      original.io.stderr.rewind
      @stdout = original.io.stdout.read
      @stderr = original.io.stderr.read
      original.io.stdout.delete
      original.io.stderr.delete
    end

    # Extract information from mixlib shellout result
    def extract_shellout
      @stdout = original.stdout
      @stderr = original.stderr
    end

    # Extract information from rye result
    def extract_rye
      @stdout = original.stdout.map(&:to_s).join("\n")
      @stderr = original.stderr.map(&:to_s).join("\n")
    end

  end
end
