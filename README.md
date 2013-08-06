# Elecksee

An LXC library for Ruby

## Usage

```ruby
require 'elecksee/lxc'

lxc = Lxc.new('container')
lxc.start unless lxc.running?
```

## Included

* Container inspect and interaction (`Lxc`)
* Container cloning (`Lxc::Clone`)
* Ephemeral containers (`Lxc::Ephemeral`)

### Notes

This library is currently tested on ubuntu platforms >= 12.04

# Info

* Repository: https://github.com/chrisroberts/elecksee.git