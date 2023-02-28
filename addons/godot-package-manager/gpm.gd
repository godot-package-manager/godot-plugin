extends RefCounted

## Godot Package Manager.
##
## Utility for managing Godot packages.
##
## Signals are only emitted in public functions. Otherwise, regular printerr(...) calls are used.

## A message that may be logged at any point during runtime.
signal message_logged(text: String)

## Emitted when any operation starts.
signal operation_started(operation_name: String)
## Emitted when a stage in a multi-stage operation is reached.
signal operation_checkpoint_reached(package_name: String, package_version: String)
## Emitted when any operation completes.
signal operation_finished()

## Path to the godot.package file.
const PACKAGE_CONFIG_PATH := "res://godot.package"
const ADDONS_DIR_FORMAT := "res://addons/%s"
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

const Config := preload("./model/config.gd")
const Package := preload("./model/package.gd")

var npm := preload("./npm.gd").new()
var net := preload("./net.gd").new()
var dir_utils := preload("./dir_utils.gd").new()
var file_utils := preload("./file_utils.gd").new()
#var dict_utils := preload("./dict_utils.gd").new()

## https://www.rfc-editor.org/rfc/rfc3986#appendix-B
## Use host ($1, $3) and path ($5, $6, $8)
var hostname_regex := RegEx.create_from_string(
	"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?")

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

static func _read_config() -> Config:
	var r := Config.new()
	
	var file := FileAccess.open(PACKAGE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		printerr("Unable to open config at path %s" % PACKAGE_CONFIG_PATH)
		return null
	
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		printerr(
			"Config should be Dictionary but was Array from config at %s" % PACKAGE_CONFIG_PATH)
		return null
	
	if await r.parse(data) != OK:
		printerr(r.parse_error)
		return null
	
	return r

func _get_host_path_pair(url: String) -> Dictionary:
	var r := hostname_regex.search(url)
	
	return {
		"host": "%s%s" % [r.get_string(1), r.get_string(3)],
		"path": "%s%s%s" % [r.get_string(5), r.get_string(6), r.get_string(8)]
	}

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Get the status of all packages registered in the config.
##
## @return Dictionary - Package name to a tree of inner Dictionaries representing the dep tree.
func status() -> Dictionary:
	operation_started.emit("Status")
	
	var r := {}
	
	var config := await _read_config()
	if config == null:
		message_logged.emit("Unable to read config")
		return r
	
	for package in config:
		var dep_data := {}
		for inner_package in package.dependencies:
			dep_data[inner_package.name] = inner_package.is_installed
		var package_data := {
			"installed": package.is_installed,
			"dependencies": dep_data
		}
		
		r[package.name] = package_data
	
	operation_finished.emit()
	
	return r

## Update a single package. If the package does not exist, a folder will be created for it.
## If the distribution hash matches the lockfile hash, then nothing will be changed on disk.
##
## @param package: Package - The package to update.
##
## @return int - The error code.
func update_package(package: Package) -> int:
	operation_started.emit("Update package %s@%s" % [package.name, package.version])
	
	var response := await npm.get_tarball_url(package.name, package.version)
	if response.is_empty():
		message_logged.emit("Could not get tarball url for %s@%s" % [
			package.name, package.version])
		return ERR_DOES_NOT_EXIST
	
	# TODO check compare tarball hash against lockfile
	
	var host_path_pair := _get_host_path_pair(response)
	
	var bytes := await net.get_request(host_path_pair.host, host_path_pair.path, [200])
	
	# TODO remove directory recursively if it already exists?
	
	var package_dir := ADDONS_DIR_FORMAT % package.unscoped_name() if not package.is_indirect else \
		DEPENDENCIES_DIR_FORMAT % [package.version, package.unscoped_name()]
	
	var err := DirAccess.make_dir_absolute(package_dir)
	if err != OK:
		message_logged.emit("Cannot create directory for package %s" % package.name)
		return err
	
	var tar_path := "%s/%s.tar.gz" % [package_dir, package.unscoped_name()]
	
	err = file_utils.save_bytes(tar_path, bytes)
	if err != OK:
		message_logged.emit("Cannot save bytes at %s for %s" % [tar_path, package.name])
		return err
	
	err = file_utils.xzf_native(tar_path, package_dir)
	if err != OK:
		message_logged.emit("Cannot untar package at %s for %s" % [tar_path, package.name])
		return err
	
	err = DirAccess.remove_absolute(tar_path)
	if err != OK:
		message_logged.emit("Cannot remove tar file at %s for %s" % [tar_path, package.name])
		return err
	
	return OK

func update_packages() -> int:
	operation_started.emit("Update packages")
	
	var config := await _read_config()
	if config == null:
		message_logged.emit("Unable to read config")
		return ERR_PARSE_ERROR
	
	for package in config:
		operation_checkpoint_reached.emit(package.name, package.version)
		var err := await update_package(package)
		if err != OK:
			return err
	
	return OK

func purge_package(package_name: String, package_version: String) -> int:
	operation_started.emit("Purge package %s@%s" % [package_name, package_version])
	
	return OK

func purge_packages() -> int:
	operation_started.emit("Purge packages")
	
	return OK
