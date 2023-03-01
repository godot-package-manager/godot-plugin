extends RefCounted

## Godot Package Manager.
##
## Utility for managing Godot packages. [br]
##
## Signals are only emitted in public functions. Otherwise, regular [method @GlobalScope.printerr]
## calls are used. The [code]update_*[/code] and [code]purge_*[/code] methods are for operating on
## single packages or all packages.

## A message that may be logged at any point during runtime. [br]
##
## Params: [br]
## [param text]: [String] - The message.
signal message_logged(text: String)

## Emitted when any operation starts. [br]
##
## Params: [br]
## [param operation_name]: [String] - The name of the operation that was started.
signal operation_started(operation_name: String)
## Emitted when a stage in a multi-stage operation is reached. [br]
##
## Params: [br]
## [param package_name]: [String] - The name of the package.
## [param package_version]: [String] - The version of the package.
signal operation_checkpoint_reached(package_name: String, package_version: String)
## Emitted when any operation completes. [br]
##
## Params: [br]
## [param operation_name]: [String] - The name of the operation that was finished.
signal operation_finished(operation_name: String)

## Path to the [code]godot.package[/code] file.
const PACKAGE_CONFIG_PATH := "res://godot.package"
const ADDONS_DIR_FORMAT := "res://addons/%s"
# TODO move this into a constant file?
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

## A config object.
const Config := preload("./model/config.gd")
## A package object.
const Package := preload("./model/package.gd")

var npm := preload("./npm.gd").new()
var net := preload("./net.gd").new()
var dir_utils := preload("./dir_utils.gd").new()
var file_utils := preload("./file_utils.gd").new()
#var dict_utils := preload("./dict_utils.gd").new()

## [url]https://www.rfc-editor.org/rfc/rfc3986#appendix-B[/url] [br]
## Use host ($1, $3) and path ($5, $6, $8).
var _hostname_regex := RegEx.create_from_string(
	"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
)

var _script_regex := RegEx.create_from_string(
	"(pre)?load\\(\\\"([^)]+)\\\"\\)"
)
var _tres_regex := RegEx.create_from_string(
	"\\[ext_resource path=\"([^\"]+)\""
)

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Try and read a package config file from [constant PACKAGE_CONFIG_PATH]. [br]
##
## Returns: [br]
## [param Config] - The parsed [constant Config] or [code]null[/code] if there was an error.
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
	var r := _hostname_regex.search(url)
	
	return {
		"host": "%s%s" % [r.get_string(1), r.get_string(3)],
		"path": "%s%s%s" % [r.get_string(5), r.get_string(6), r.get_string(8)]
	}

## Calculates the sha1 sum for the [param actual] bytes and compares it against the expected value.
## [br]
##
## Params: [br]
## [param actual]: [PackedByteArray] - The bytes to caluclate a sha1 sum for. [br]
## [param expected]: [String] - The expected sha1 sum. [br]
##
## Returns: [br]
## [param bool] - Whether the calculated sha1 matches the expected sha1 sum.
func _valid_sha1sum(actual: PackedByteArray, expected: String) -> bool:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(actual)
	
	return ctx.finish().hex_encode() == expected

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Get the status of all packages registered in the config. [br]
##
## Returns: [br]
## [param Dictionary] - Package name to a tree of inner [Dictionary]s representing
## the dependency tree.
func status() -> Dictionary:
	var operation_name := "Status"
	
	operation_started.emit(operation_name)
	
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
	
	operation_finished.emit(operation_name)
	
	return r

## Update a single package. If the package does not exist, a folder will be created for it.
## If the distribution hash matches the lockfile hash, then nothing will be changed on disk. [br]
##
## Params: [br]
## [param package]: [constant Package] - The package to update. [br]
##
## Return: [br]
## [param int] - The error code.
func update_package(package: Package) -> int:
	var operation_name := "Update package %s@%s" % [package.name, package.version]
	
	operation_started.emit(operation_name)
	
	var response := await npm.get_tarball_info(package.name, package.version)
	if response.is_error:
		message_logged.emit("Could not get tarball info for %s@%s" % [
			package.name, package.version
		])
		return ERR_DOES_NOT_EXIST
	
	# TODO check compare tarball shasum against lockfile
	
	var host_path_pair := _get_host_path_pair(response.url)
	
	var bytes := await net.get_request(host_path_pair.host, host_path_pair.path, [200])
	
	if not _valid_sha1sum(bytes, response.shasum):
		message_logged.emit("Sha1 sums do not match for %s@%s. This might be dangerous" % [
			package.name, package.version
		])
		return ERR_FILE_CORRUPT
	
	var package_dir := ADDONS_DIR_FORMAT % package.unscoped_name() if not package.is_indirect else \
		DEPENDENCIES_DIR_FORMAT % [package.version, package.unscoped_name()]
	
	if DirAccess.dir_exists_absolute(package_dir):
		message_logged.emit("%s already exists, removing recursively" % package_dir)
		
		var err := dir_utils.remove_dir_recursive(package_dir)
		if err != OK:
			message_logged.emit("Cannot remove directory recursively %s" % package_dir)
			return err
	
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
	
	for dep in package.dependencies:
		err = await update_package(dep)
		if err != OK:
			message_logged.emit("Unable to download indirect dependency %s@%s for %s@%s" % [
				dep.name, dep.version,
				package.name, package.version
			])
	
	# TODO fix paths for all dependencies
	if not package.is_indirect:
		pass
	else:
		pass
	
	operation_finished.emit(operation_name)
	
	return OK

## Updates all packages listed in the package file. [br]
##
## Returns: [br]
## [param int] - The error code.
func update_packages() -> int:
	var operation_name := "Update packages"
	
	operation_started.emit(operation_name)
	
	var config := await _read_config()
	if config == null:
		message_logged.emit("Unable to read config")
		return ERR_PARSE_ERROR
	
	for package in config:
		operation_checkpoint_reached.emit(package.name, package.version)
		var err := await update_package(package)
		if err != OK:
			return err
	
	operation_finished.emit(operation_name)
	
	return OK

## Remove any unused indirect dependencies. [br]
##
## Returns: [br]
## [param int] - The error code.
func clean() -> int:
	var operation_name := "Clean packages"
	
	operation_started.emit(operation_name)
	
	operation_finished.emit(operation_name)
	
	return OK

## Removes a package from the filesystem. Only works for direct dependencies. [br]
##
## Params: [br]
## [param package_name]: String - The name of the package to remove. [br]
##
## Returns: [br]
## [param int] - The error code.
func purge_package(package_name: String) -> int:
	var operation_name := "Purge package %s" % package_name
	
	operation_started.emit(operation_name)
	
	operation_finished.emit(operation_name)
	
	return OK

## Remove all packages and indirect dependencies. [br]
##
## Returns: [br]
## [param int] - The error code.
func purge_packages() -> int:
	var operation_name := "Purge packages"
	
	operation_started.emit(operation_name)
	
	operation_finished.emit(operation_name)
	
	return OK
