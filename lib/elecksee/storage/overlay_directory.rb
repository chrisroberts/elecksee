require 'elecksee'

class Lxc
  module Storage
    # Overlay directory backed storage
    class OverlayDirectory

      # @return [String] storage name (usually container name)
      attr_reader :name
      # @return [String] path to temporary directory
      attr_reader :tmp_dir

      include Helpers

      # Create new instance
      #
      # @param name [String] storage name (usually container name)
      # @param args [Hash]
      # @option args [String] :tmp_dir path to temporary directory
      def initialize(name, args={})
        @name = name
        @tmp_dir = args[:tmp_dir] || '/tmp/lxc/ephemerals'
        create
      end

      # @return [String] path to overlay directory
      def overlay_path
        File.join(tmp_dir, 'virt-overlays', name)
      end
      alias_method :target_path, :overlay_path

      # Create the storage
      #
      # @return [TrueClass, FalseClass]
      def create
        unless(File.directory?(overlay_path))
          command("mkdir -p #{overlay_path}", :sudo => true)
          true
        else
          false
        end
      end

      # Destroy the storage
      #
      # @return [TrueClass, FalseClass]
      def destroy
        if(File.directory?(overlay_path))
          command("rm -rf #{overlay_path}", :sudo => true)
          true
        else
          false
        end
      end

    end

    # Clone directory does the same as the overlay, just in
    # a persistent location
    class CloneDirectory < OverlayDirectory

      # Create new instance
      #
      # @param name [String] name of storage (usually container name)
      # @param args [Hash]
      # @option args [String] :dir persistent storage path
      def initialize(name, args={})
        args[:tmp_dir] = args[:dir] if args[:dir]
        args[:tmp_dir] || '/var/lib/lxc'
        super
      end

      # @return [String]
      def overlay_path
        File.join(tmp_dir, name)
      end
      alias_method :target_path, :overlay_path
    end

  end
end
