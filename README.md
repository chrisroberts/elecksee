# Elecksee

This is a simple library for interacting with LXC. It relies on
LXC tools being installed on the system to properly function.
It is extracted from the Chef LXC cookbook, so poke around there

## Usage

```ruby

require 'elecksee/lxc'

lxc = Elecksee::Lxc.new('my-container')
p lxc.info
```

## Awesome

Awesome ephemerals lets you create ephemeral nodes with different
overlays for the rootfs. Since tmpfs will place a size restriction
on ephemerals based on current memory available, this provides a
simple workaround. Currently supported is a raw temporary directory
on the host, or a VBD that defaults to 2GB.

### Using temporary directory

```
$ lxc-awesome-ephemeral -o ubuntu -d -z /tmp/lxc-roots
```

### Using VBD

```
$ lxc-awesome-ephemeral -o ubuntu -d -D 2000
```

This will create a 2GB virtual block device for the container
to use for the overlay.

Note
----

Overlays are not persistent (thus ephemeral) and will be automatically
cleaned up when the container has reached a stop state.

# Info

* Repository: https://github.com/chrisroberts/elecksee.git