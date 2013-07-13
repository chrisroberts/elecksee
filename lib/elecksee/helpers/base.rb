class Lxc
  class CommandFailed < StandardError
  end

  module Helpers
  
    def sudo
      Lxc.sudo
    end
    
    # Simple helper to shell out
    def run_command(cmd, args={})
      retries = args[:allow_failure_retry].to_i
      cmd = [sudo, cmd].join(' ') if args[:sudo]
      begin
        shlout = Mixlib::ShellOut.new(cmd, 
          :logger => defined?(Chef) ? Chef::Log.logger : log,
          :live_stream => args[:livestream] ? STDOUT : nil,
          :timeout => args[:timeout] || 1200,
          :environment => {'HOME' => detect_home}
        )
        shlout.run_command
        shlout.error!
        shlout
      rescue Mixlib::ShellOut::ShellCommandFailed, CommandFailed, Mixlib::ShellOut::CommandTimeout
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
