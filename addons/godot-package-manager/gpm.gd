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
signal operation_checkpoint_reached(package_name: String)
## Emitted when any operation completes.
signal operation_finished()

## Path to the godot.package file.
const PACKAGE_CONFIG_PATH := "res://godot.package"
const ADDONS_DIR := "res://addons"
const ADDONS_DIR_FORMAT := ADDONS_DIR + "/%s"
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

const Config := preload("./model/config.gd")
const Package := preload("./model/package.gd")

var npm := preload("./npm.gd").new()
var net := preload("./net.gd").new()
var dir_utils := preload("./dir_utils.gd").new()
var file_utils := preload("./file_utils.gd").new()
#var dict_utils := preload("./dict_utils.gd").new()

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

func update_package(package_name: String) -> int:
	operation_started.emit("Update package %s" % package_name)
	
	return OK

func update_packages() -> int:
	operation_started.emit("Update packages")
	
	var config := await _read_config()
	if config == null:
		message_logged.emit("Unable to read config")
		return ERR_PARSE_ERROR
	
	return OK

func purge_package(package_name: String) -> int:
	operation_started.emit("Purge package %s" % package_name)
	
	return OK

func purge_packages() -> int:
	operation_started.emit("Purge packages")
	
	return OK
