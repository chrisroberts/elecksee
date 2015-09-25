## v2.0.4
* Always scrub environment variables prior to execution on attach

## v2.0.2
* Disable spawn by default
* Use attach by default
* Fix typing issue around string manipulations

## v2.0.0
* [fix] Use sudo helper when cloning
* [enhancement] Disable retry on ephemeral command
* [enhancement] Dynamic parsing/generation of configuration files
* [fix] Do not register traps when executing inline
* [fix] Synchronize childprocess access to prevent race

_WARNING: Updated configuration file handling may cause breakage_

## v1.1.8
* Add `include` support for file config

## v1.1.6
* Check for unknown state when stopping (ephemerals final state is :unknown)
* Force Rye to proxy method_missing correctly on free form commands

## v1.1.4
* Only stop container on cleanup if container is running
* Add flag for selection of using ssh or attach to run commands

## v1.1.2
* Provide direct access to `Rye::Box`
* Add alternate ephemeral init using bash wrapper for cleanup

## v1.1.0
* Update all documentation to yardoc
* Group classes into logical namespaces
* Define expected returns for methods
* Remove calls to lxc-shutdown (not always available)
* Always attempt in container halt prior to lxc-stop
* Use lxc-ls for container listing to prevent permission issues
* Use the Rye library under the hood for container connects
* Use ChildProcess for shelling out

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
