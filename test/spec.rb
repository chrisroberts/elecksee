require 'elecksee'

# Register our exit callback prior to loading minitest so
# our callback is executed after the tests are completed
Kernel.at_exit do
  print "Cleaning host system (destroying test containers)... "
  system('sudo lxc-unfreeze -n elecksee-tester-1')
  4.times do |i|
    system("sudo lxc-stop -n elecksee-tester-#{i} > /dev/null 2>&1")
    system("sudo lxc-destroy -n elecksee-tester-#{i}")
  end
  puts "DONE!"
end

require 'minitest/autorun'

# Setup some containers for testing
print "Preparing host system (creating test containers)... "
unless(system('sudo lxc-ls | grep "^elecksee-tester$" > /dev/null 2>&1'))
  unless(system('sudo lxc-create -n elecksee-tester -t ubuntu -- -r precise > /dev/null 2>&1'))
    raise 'Failed to create base testing container'
  end
end
4.times do |i|
  unless(system("sudo lxc-clone elecksee-tester elecksee-tester-#{i} > /dev/null 2>&1"))
    raise "Failed to create tester clone (interval #{i})"
  end
  unless(system("sudo lxc-start -d -n elecksee-tester-#{i} > /dev/null 2>&1"))
    raise "Failed to start tester clone (interval #{i})"
  end
end
puts "DONE!"

unless(system("sudo lxc-stop -n elecksee-tester-0 > /dev/null 2>&1"))
  raise 'Failed to stop elecksee-tester-0'
end
unless(system("sudo lxc-freeze -n elecksee-tester-1 > /dev/null 2>&1"))
  raise 'Failed to freeze elecksee-tester-1'
end

# Load specs!
Dir.glob(File.join(File.expand_path(File.dirname(__FILE__)), 'specs/*.rb')).each do |path|
  require path
end
