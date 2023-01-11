extends RefCounted

## Wrapper for an iterator over a list of packages.

const Package := preload("res://addons/godot-package-manager/model/package.gd")
const FileUtils := preload("res://addons/godot-package-manager/file_utils.gd")

const PACKAGE_FILE := "godot.package"
const LOCK_FILE := "godot.lock"

var _packages: Array[Package] = []

var _iter_current: int = 0

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _iter_init(_arg: Variant) -> bool:
	_iter_current = 0
	return _should_continue()

func _iter_next(_arg: Variant) -> bool:
	_iter_current += 1
	return _should_continue()

func _iter_get(_arg: Variant) -> Variant:
	return _packages[_iter_current]

func _to_string() -> String:
	return "PackageList %s" % str(_packages)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Helper function for determining if the iteratr should continue.
##
## @return bool - Whether or not the iterator should continue iterating.
func _should_continue() -> bool:
	return _packages.size() > _iter_current

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Reads a GPM config file at a given path.
##
## @param path: String - The path to a config file.
##
## @return Dictionary - The parsed contents. Will be empty if reading or parsing failed.
static func read_config(path: String) -> Dictionary:
	if not path.get_file() in [PACKAGE_FILE, LOCK_FILE]:
		return {}
	
	var data = JSON.parse_string(FileUtils.read_file_to_string(path))
	if not data is Dictionary:
		return {}
	
	return data

static func write_config(path: String, data: Dictionary) -> int:
	if not path.get_file() in [PACKAGE_FILE, LOCK_FILE]:
		return ERR_FILE_BAD_PATH
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ERR_FILE_CANT_WRITE
	
	file.store_string(JSON.stringify(data, "\t"))
	
	return OK

func lock() -> int:
	
	
	return OK

## Adds a package to the package list.
##
## @param package: Package - The package to add.
func append(package: Package) -> void:
	_packages.append(package)

## Gets the size of the internal package list.
##
## @return int - The amount of packages.
func size() -> int:
	return _packages.size()
