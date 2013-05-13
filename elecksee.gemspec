$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'elecksee/version'
Gem::Specification.new do |s|
  s.name = 'elecksee'
  s.version = Elecksee::VERSION.version
  s.summary = 'LXC helpers'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/chrisroberts/elecksee'
  s.description = 'LXC helpers'
  s.require_path = 'lib'
  s.executables = %w(lxc-awesome-ephemeral)
  s.add_dependency 'mixlib-shellout'
  s.add_dependency 'net-ssh'
  s.files = Dir['**/*']
end
