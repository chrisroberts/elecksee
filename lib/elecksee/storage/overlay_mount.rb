require 'elecksee/helpers/base'

class Lxc
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
        command(cmd, :sudo => true)
        true
      end
    end

    def mounted?
      command("mount").stdout.include?(target)
    end
    
    def unmount
      if(mounted?)
        command("umount #{target}", :sudo => true, :allow_failure => true)
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
end
