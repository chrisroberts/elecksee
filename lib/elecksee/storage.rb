require 'elecksee'

class Lxc
  # Container storage backers
  module Storage

    autoload :CloneDirectory, 'elecksee/storage/overlay_directory'
    autoload :OverlayDirectory, 'elecksee/storage/overlay_directory'
    autoload :OverlayMount, 'elecksee/storage/overlay_mount'
    autoload :VirtualDevice, 'elecksee/storage/virtual_device'

  end
end
