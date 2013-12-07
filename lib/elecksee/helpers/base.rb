require 'shellwords'

class Lxc
  class CommandFailed < StandardError
    attr_accessor :original, :result
    def initialize(orig, result=nil)
      @original = orig
      @result = result
      super(orig.to_s)
    end
  end

  class Timeout < CommandFailed
  end

  class CommandResult
    attr_reader :original, :stdout, :stderr
    def initialize(result)
      @original = result
      if(result.class.ancestors.map(&:to_s).include?('ChildProcess::AbstractProcess'))
        extract_childprocess
      elsif(result.class.to_s == 'Mixlib::ShellOut')
        extract_shellout
      else
        raise TypeError.new("Unknown process result type received: #{result.class}")
      end
    end

    def extract_childprocess
      original.io.stdout.rewind
      original.io.stderr.rewind
      @stdout = original.io.stdout.read
      @stderr = original.io.stderr.read
      original.io.stdout.delete
      original.io.stderr.delete
    end

    def extract_shellout
      @stdout = original.stdout
      @stderr = original.stderr
    end
  end

  module Helpers

    def sudo
      Lxc.sudo
    end

    # Simple helper to shell out
    def run_command(cmd, args={})
      cmd_type = Lxc.shellout_helper
      unless(cmd_type)
        if(defined?(ChildProcess))
          cmd_type = :childprocess
        else
          cmd_type = :mixlib_shellout
        end
      end
      case cmd_type
      when :childprocess
        require 'tempfile'
        result = child_process_command(cmd, args)
      when :mixlib_shellout
        require 'mixlib/shellout'
        result = mixlib_shellout_command(cmd, args)
      else
        raise ArgumentError.new("Unknown shellout helper provided: #{cmd_type}")
      end
      result == false ? false : CommandResult.new(result)
    end

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

    def command(*args)
      run_command(*args)
    end

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

    # Detect HOME environment variable. If not an acceptable
    # value, set to /root or /tmp
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
end
