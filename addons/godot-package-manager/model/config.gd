extends RefCounted

const DEPENDENCY_KEY := "dependencies"

const Package := preload("./package.gd")
const Npm := preload("../npm.gd")

var packages := {}

var parse_error := ""

var _iter_values := []
var _iter_current: int = -1

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init() -> void:
	pass

func _iter_init(_arg: Variant) -> bool:
	_iter_current = 0
	_iter_values = packages.values()
	return _should_continue()

func _iter_next(_arg: Variant) -> bool:
	_iter_current += 1
	return _should_continue()

func _iter_get(_arg: Variant) -> Package:
	return _iter_values[_iter_current]

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

func _should_continue() -> bool:
	return packages.size() > _iter_current

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Parses the package file and finds all indirect dependencies.
##
## @param dict: Dictionary - List of dependencies from either a package file or manifest.
## @param direct_dep: Package - The direct dependency. Will be null if this package is
## the direct depedency.
##
## @return int - The error code.
func parse(dict: Dictionary, direct_dep: Package = null) -> int:
	for package_name in dict.keys():
		var package_version: String = dict[package_name]
		
		var response: Dictionary = await Npm.get_manifest(package_name, package_version)
		if response.is_empty():
			printerr("Unable to get manifest for %s@%s" % [package_name, package_version])
			return ERR_CANT_RESOLVE
		
		var root_package: Package = null
		if direct_dep == null:
			root_package = Package.new(package_name, package_version, false)
			add(root_package)
		else:
			root_package = direct_dep
			root_package.dependencies.push_back(Package.new(
				package_name, package_version, true
			))
		
		var dependencies: Dictionary = response.get(DEPENDENCY_KEY, {})
		if dependencies.size() > 0:
			var err := await parse(dependencies, root_package)
			if err != OK:
				return err
	
	return OK

## Add a package as a direct dependency. Does not allow duplicates.
##
## @param package: Package - The package to add.
##
## @return int - The error code.
func add(package: Package) -> int:
	if packages.has(package.name):
		return ERR_ALREADY_EXISTS
	
	packages[package.name] = package
	
	return OK
