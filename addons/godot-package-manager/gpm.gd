class_name GodotPackageManager
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
const LOCK_FILE_PATH := "res://package.lock"
const ADDONS_DIR_FORMAT := "res://addons/%s"
# TODO move this into a constant file?
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

const Model := preload("./model/model.gd")

const Npm := preload("./npm.gd")
const Net := preload("./net.gd")
const DirUtils := preload("./dir_utils.gd")
const FileUtils := preload("./file_utils.gd")

## [url]https://www.rfc-editor.org/rfc/rfc3986#appendix-B[/url] [br]
## Use host ($1, $3) and path ($5, $6, $8).
var _hostname_regex := RegEx.create_from_string(
	"^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
)

var _script_regex := RegEx.create_from_string(
	"load\\(\\\"([^)]+)\\\"\\)"
)
var _tres_regex := RegEx.create_from_string(
	"\\[ext_resource path=\"([^\"]+)\""
)

var config: Model.Config = null
var _config_sha1sum := ""
var lock_file: Model.LockFile = null

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init() -> void:
	config = await _read_config()
	if config == null:
		config = Model.Config.new()
		FileUtils.save_string(PACKAGE_CONFIG_PATH, config.to_string())
	
	_config_sha1sum = FileUtils.sha1sum_file(PACKAGE_CONFIG_PATH)
	
	lock_file = _read_lock_file()
	if lock_file == null:
		lock_file = Model.LockFile.new({})
		FileUtils.save_string(LOCK_FILE_PATH, lock_file.to_string())
	
	for package_name in lock_file.packages:
		if not config.packages.has(package_name):
			# TODO this is probably an indirect dependency. Need to figure out a way to track
			# whether those are installed
			continue
		
		# TODO should probably check for the actual directory as well instead of just assuming
		# the lock file is correct
		config.packages[package_name].is_installed = true

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Try and read a package config file from [constant PACKAGE_CONFIG_PATH]. [br]
##
## Returns: [br]
## [param Config] - The parsed [constant Config] or [code]null[/code] if there was an error.
static func _read_config() -> Model.Config:
	var r := Model.Config.new()
	
	var file := FileAccess.open(PACKAGE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		printerr("Unable to open config at path %s" % PACKAGE_CONFIG_PATH)
		return null
	
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		printerr(
			"Config should be a Dictionary but was Array from config at %s" % PACKAGE_CONFIG_PATH)
		return null
	
	if await r.parse(data) != OK:
		printerr(r.parse_error)
		return null
	
	return r

static func _read_lock_file() -> Model.LockFile:
	var file := FileAccess.open(LOCK_FILE_PATH, FileAccess.READ)
	if file == null:
		printerr("Unable to open lock file at path %s" % LOCK_FILE_PATH)
		return null
	
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		printerr("Lock file should be a Dictionary but it was not %s" % LOCK_FILE_PATH)
		return null
	
	return Model.LockFile.new(data)

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
static func _valid_sha1sum(actual: PackedByteArray, expected: String) -> bool:
	return FileUtils.sha1sum_bytes(actual) == expected

# TODO removed typed array since that causes an invalid type error (even though the type is valid)
## Scans files for relative/absolute file paths and remaps them if necessary. [br]
##
## Params: [br]
## [param paths]: [Dictionary] - A list of file paths from [constant DirUtils]. [br]
## [param deps]: [Array] - A list of valid dependencies for the current function. These will be
## used when remapping paths, since we need to know which files are valid dependencies. [br]
##
## Returns: [br]
## [param int] - The error code.
func _fix_file_paths(paths: Dictionary, deps: Array) -> int:
	for val in paths.values():
		match typeof(val):
			TYPE_STRING: # StringName not handled since that should be impossible
				var regex: RegEx = null
				match val.get_extension().to_lower():
					"gd":
						regex = _script_regex
					"tres", "tscn":
						regex = _tres_regex
					_:
						message_logged.emit("Unhandled file extension for file: %s" % val)
						continue
				
				var err := FileUtils.fix_path(regex, val, deps)
				if err != OK:
					message_logged.emit("Error %d occurred while fixing paths for file %s" % [
						err, val])
			TYPE_DICTIONARY:
				return _fix_file_paths(val, deps)
			_:
				message_logged.emit("Unexpected value found while fixing file paths: %s" % str(val))
	
	return OK

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
	
	var config: Model.Config = null
	
	# Only re-read the config if it has been modified
	if FileUtils.sha1sum_file(PACKAGE_CONFIG_PATH) == _config_sha1sum:
		config = self.config
	else:
		config = await _read_config()
		if config == null:
			message_logged.emit("Unable to read config")
			return r
		_config_sha1sum = FileUtils.sha1sum_file(PACKAGE_CONFIG_PATH)
		
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
func update_package(package: Model.Package) -> int:
	var operation_name := "Update package %s@%s" % [package.name, package.version]
	
	operation_started.emit(operation_name)
	
	var response := await Npm.get_tarball_info(package.name, package.version)
	if response.is_error:
		message_logged.emit("Could not get tarball info for %s@%s" % [
			package.name, package.version
		])
		return ERR_DOES_NOT_EXIST
	
	var host_path_pair := _get_host_path_pair(response.url)
	
	var tarball_bytes := await Net.get_request(host_path_pair.host, host_path_pair.path, [200])
	
	if not _valid_sha1sum(tarball_bytes, response.shasum):
		message_logged.emit("Sha1 sums do not match for %s@%s. This might be dangerous" % [
			package.name, package.version
		])
		return ERR_FILE_CORRUPT
	
	if lock_file.has(package.name, response.shasum):
		operation_finished.emit("Package already exists with the correct shasum: %s - %s" % [
			package.name, response.shasum
		])
		return OK
	
	var package_dir := ADDONS_DIR_FORMAT % package.unscoped_name() if not package.is_indirect else \
		DEPENDENCIES_DIR_FORMAT % [package.version, package.unscoped_name()]
	
	package.install_dir = package_dir
	
	if DirAccess.dir_exists_absolute(package_dir):
		message_logged.emit("%s already exists, removing recursively" % package_dir)
		
		var err := DirUtils.remove_dir_recursive(package_dir)
		if err != OK:
			message_logged.emit("Cannot remove directory recursively %s" % package_dir)
			return err
	
	var err := DirAccess.make_dir_absolute(package_dir)
	if err != OK:
		message_logged.emit("Cannot create directory for package %s" % package.name)
		return err
	
	var tar_path := "%s/%s.tar.gz" % [package_dir, package.unscoped_name()]
	
	err = FileUtils.save_bytes(tar_path, tarball_bytes)
	if err != OK:
		message_logged.emit("Cannot save bytes at %s for %s" % [tar_path, package.name])
		return err
	
	err = FileUtils.xzf_native(tar_path, package_dir)
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
			return err
	
	err = _fix_file_paths(DirUtils.get_files_recursive(package_dir), package.dependencies)
	if err != OK:
		message_logged.emit("Error %d occurred while fixing file paths for package %s" % [
			err, package.name
		])
	
	package.is_installed = true
	lock_file.add(package.name, response.shasum)
	
	operation_finished.emit(operation_name)
	
	return OK

## Updates all packages listed in the package file. [br]
##
## Returns: [br]
## [param int] - The error code.
func update_packages() -> int:
	var operation_name := "Update packages"
	
	operation_started.emit(operation_name)
	
	var config: Model.Config = null
	
	# Only re-read the config if it has been modified
	if FileUtils.sha1sum_file(PACKAGE_CONFIG_PATH) == _config_sha1sum:
		config = self.config
	else:
		config = await _read_config()
		if config == null:
			message_logged.emit("Unable to read config")
			return ERR_FILE_CANT_READ
		_config_sha1sum = FileUtils.sha1sum_file(PACKAGE_CONFIG_PATH)
	
	for package in config:
		operation_checkpoint_reached.emit(package.name, package.version)
		var err := await update_package(package)
		if err != OK:
			return err
	
	var err := FileUtils.save_string(LOCK_FILE_PATH, lock_file.to_string())
	if err != OK:
		message_logged.emit("Failed to save lock file with error code %d" % err)
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
	
	# TODO stub
	
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
	
	# TODO stub
	
	operation_finished.emit(operation_name)
	
	return OK

## Remove all packages and indirect dependencies. [br]
##
## Returns: [br]
## [param int] - The error code.
func purge_packages() -> int:
	var operation_name := "Purge packages"
	
	operation_started.emit(operation_name)
	
	# TODO stub
	
	operation_finished.emit(operation_name)
	
	return OK
