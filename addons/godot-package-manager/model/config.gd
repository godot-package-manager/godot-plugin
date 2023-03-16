extends RefCounted

## The package config file for [GodotPackageManager].

const DEPENDENCY_KEY := "dependencies"

const Package := GodotPackageManager.Model.Package
const Npm := GodotPackageManager.Npm

## Package name -> Package
var packages := {}

var _iter_values := []
var _iter_current: int = -1

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _iter_init(_arg: Variant) -> bool:
	_iter_current = 0
	_iter_values = packages.values()
	return _should_continue()

func _iter_next(_arg: Variant) -> bool:
	_iter_current += 1
	return _should_continue()

func _iter_get(_arg: Variant) -> Package:
	return _iter_values[_iter_current]

func _to_string() -> String:
	var r := {}
	for package in packages.values():
		r[package.name] = package.version
	
	return JSON.stringify(r, "\t")

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

func _should_continue() -> bool:
	return packages.size() > _iter_current

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Parses the package file and finds all indirect dependencies. [br]
##
## Params: [br]
## [param dict]: [Dictionary] - List of dependencies from either a package file or manifest. [br]
## [param direct_dep]: [constant Package] - The direct dependency. Will be null if this package is
## the direct depedency. [br]
##
## Returns: [br]
## [param int] - The error code.
func parse(dict: Dictionary, direct_dep: Package = null) -> int:
	for package_name in dict.keys():
		var package_version: String = dict[package_name]
		
		var response: Dictionary = await Npm.get_manifest(package_name, package_version)
		if response.is_empty():
			printerr("Unable to get manifest for %s@%s" % [package_name, package_version])
			return ERR_CANT_RESOLVE
		
		var root_package: Package = null
		if direct_dep == null: # This is the direct dependency
			root_package = Package.new(package_name, package_version, false)
			add(root_package)
		else: # Otherwise, it is an indirect dependency
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

## Add a package as a direct dependency. Does not allow duplicates. [br]
##
## Params: [br]
## [param package]: [constant Package] - The package to add.
##
## Returns: [br]
## [param int] - The error code.
func add(package: Package) -> int:
	if packages.has(package.name):
		return ERR_ALREADY_EXISTS
	
	packages[package.name] = package
	
	return OK
