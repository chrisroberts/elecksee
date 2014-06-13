# Elecksee

An LXC library for Ruby

## Basic usage

```ruby
require 'elecksee'

lxc = Lxc.new('container')
lxc.start unless lxc.running?
```

## Permissions

Root access is required for most operations. This library can
be utilized from a root user but is built to use sudo as required.
To enable sudo, use:

```ruby
Lxc.use_sudo = true
```

If you require a custom sudo for things like rvm, use:

```ruby
Lxc.use_sudo = 'rvmsudo'
```

## What's in the box

### Lxc

Container inspection and interaction. Will provide state
information about the container as well as providing an
interaction interface for running commands within the
container and changing its state (stop, start, freeze, thaw).

```ruby
my_lxc = Lxc.new('my_container')
puts "Address: #{my_lxc.container_ip}"
puts "State: #{my_lxc.state}"
```

### Lxc::Ephemeral

Create ephemeral containers from existing stopped containers. Utilizes
an overlay filesystem to leave original container untouched. All ephemeral
resources are removed once the container is halted.

### Lxc::Clone

Make clones of existing stopped containers. Allows for utilizing optional
storage backends like full copies, overlay directories, virtual block
device or fs specific like btrfs snapshots.

### Notes

This library is currently tested on ubuntu platforms >= 12.04

# Info

* Repository: https://github.com/chrisroberts/elecksee.git