require 'elecksee/version'
require 'elecksee/lxc'

# LXC interface
class Lxc
  autoload :Clone, 'elecksee/clone'
  autoload :Ephemeral, 'elecksee/ephemeral'
  autoload :Helpers, 'elecksee/helpers'
  autoload :CommandFailed, 'elecksee/helpers'
  autoload :Timeout,'elecksee/helpers'
  autoload :CommandResult, 'elecksee/helpers'
  autoload :Storage, 'elecksee/storage'
end
