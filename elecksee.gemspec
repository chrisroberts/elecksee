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
  s.add_dependency 'bogo'
  s.add_dependency 'attribute_struct'
  s.add_dependency 'childprocess'
  s.add_dependency 'rye'
  s.files = Dir['{bin,lib}/**/**/*'] + %w(elecksee.gemspec README.md CHANGELOG.md LICENSE CONTRIBUTING.md)
end
