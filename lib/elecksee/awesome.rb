module Elecksee
  class Awesome
    class << self
      def run!
        path = File.expand_path(
          File.join(
            File.dirname(__FILE__), 'vendor/lxc/files/default/lxc-awesome-ephemeral'
          )
        )
        exec("/bin/bash #{path} #{ARGV.join(' ')}")
      end
    end
  end
end
