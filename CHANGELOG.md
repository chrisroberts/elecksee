## v1.0.22
* Update underlying implementation for execute
* Provide better info interpretation
* Scrub bundler environment variables if found

## v1.0.20
* Fix `LxcFileConfig` population when using `Chef::Resource` instance

## v1.0.18
* Use shellwords to properly break down commands
* Force hash type as required
* Return expected type on command failure
* Remove custom `run_command` and use helper based method instead

## v1.0.16
* Fix syntax bug in `Lxc::FileConfig` (thanks @mikerowehl)

## v1.0.14
* Remove rebase artifact because duh

## v1.0.12
* Allow access to ephemeral setup without creation (thanks @portertech)
* Add `#destroy` method to `Lxc` instances (thanks @portertech)

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
