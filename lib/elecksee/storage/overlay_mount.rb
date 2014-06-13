require 'elecksee'

class Lxc
  module Storage
    # Overlay mount backed storage
    class OverlayMount

      include Helpers

      # @return [String] base path to overlay
      attr_reader :base
      # @return [String] path to overlay storage
      attr_reader :overlay
      # @return [String] path to mount overlay
      attr_reader :target
      # @return [String] type of overlay to implement
      attr_reader :overlay_type

      # Create new instance
      #
      # @param args [Hash]
      # @option args [String] :base base path to overlay
      # @option args [String] :overlay path to overlay storage
      # @option args [String] :target path to mount overlay
      # @option args [String] :overlay_type type of overlay to implement
      # @note :overlay_type defaults to overlayfs
      def initialize(args={})
        validate!(args)
        @base = args[:base]
        @overlay = args[:overlay]
        @target = args[:target]
        @overlay_type = args[:overlay_type] || 'overlayfs'
      end

      # Mount the overlay
      #
      # @return [TrueClass, FalseClass]
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
        else
          false
        end
      end

      # @return [TrueClass, FalseClass]
      def mounted?
        command("mount").stdout.include?(target)
      end

      # Unmount the overlay
      #
      # @return [TrueClass, FalseClass]
      def unmount
        if(mounted?)
          command("umount #{target}", :sudo => true, :allow_failure => true)
          true
        else
          false
        end
      end

      private

      # Validate the provide arguments
      #
      # @param args [Hash]
      # @option args [String] :base
      # @option args [String] :overlay
      # @option args [String] :target
      # @return [TrueClass]
      def validate!(args)
        [:base, :overlay, :target].each do |required|
          unless(args[required])
            raise ArgumentError.new "Missing required argument: #{required}"
          end
          unless(File.directory?(args[required]))
            raise TypeError.new "Provided argument is not a valid directory for #{required}: #{args[required]}"
          end
        end
        true
      end

    end
  end
end
