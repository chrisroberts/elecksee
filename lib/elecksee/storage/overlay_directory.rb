require 'elecksee/helpers'

class Lxc
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
end
