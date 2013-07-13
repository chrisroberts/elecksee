require 'elecksee/helpers/base'

class Lxc
  class OverlayDirectory
    
    attr_reader :name
    attr_reader :tmp_dir

    include Helpers
    
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
      if(File.directory?(overlay_path))
        command("rm -rf #{overlay_path}", :sudo => true)
      end
    end
    
  end

  # Clone directory does the same as the overlay, just in
  # a persistent place
  class CloneDirectory < OverlayDirectory
    def initialize(name, args={})
      args[:tmp_dir] = args[:dir] if args[:dir]
      args[:tmp_dir] || '/var/lib/lxc'
      super
    end

    def overlay_path
      File.join(tmp_dir, name)
    end
  end
end
