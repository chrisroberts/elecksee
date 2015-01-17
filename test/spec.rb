require 'elecksee'
require 'childprocess'

Lxc.default_ssh_password = 'fubar'

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
unless(system('echo root:fubar | sudo chroot /var/lib/lxc/elecksee-tester/rootfs chpasswd'))
  raise 'Failed to set base testing container password'
end
system('sudo cp /etc/resolv.conf /var/lib/lxc/elecksee-tester/rootfs/etc/resolv.conf')
unless(system('sudo chroot /var/lib/lxc/elecksee-tester/rootfs apt-get -qq update > /dev/null 2>&1'))
  raise 'Failed update local apt repo cache'
end
system('sudo bash -c \'echo "USE_LXC_BRIDGE=false" > /var/lib/lxc/elecksee-tester/rootfs/etc/default/lxc\'')
system('sudo chroot /var/lib/lxc/elecksee-tester/rootfs apt-get install lxc --no-install-recommends -y -q --force-yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" > /dev/null 2>&1')
4.times do |i|
  unless(system("sudo lxc-clone -o elecksee-tester -n elecksee-tester-#{i} > /dev/null 2>&1"))
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
