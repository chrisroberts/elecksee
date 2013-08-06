## v1.0.10
* Add clone support
* Allow command passage to ephemeral nodes
* Update temp directories to be world accessible/readable
* Clean up and dry out some reusable bits

## v1.0.8
* Delete overlay directories using `sudo`

## v1.0.6
* Fix `sudo` issue on ephemeral creation (tmpdir)
* Allow multi-retry on info since false error can be encountered if container is in shutdown phase

## v1.0.4
* Removes vendored lxc cookbook
* Adds proper implementations for lxc and ephemerals

## v1.0.2
* Update Chef::Log usage to only apply when Chef is loaded

## v1.0.0
* Initial release
