extends RefCounted

## Package name -> sha1sum
var packages := {}

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init(initial_data: Dictionary) -> void:
	packages = initial_data.duplicate()

func _to_string() -> String:
	return JSON.stringify(packages, "\t")

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Wrapper for adding packages to the lock file. [br]
##
## Params: [br]
## [param package_name]: [String] - The name of the package. [br]
## [param sha1sum]: [String] - The sha1sum of the package tarball.
func add(package_name: String, sha1sum: String) -> void:
	packages[package_name] = sha1sum

## Wrapper for checking if a given package and sha1sum exist. [br]
##
## Params: [br]
## [param package_name]: [String] - The name of the package. [br]
## [param sha1sum]: [String] - The sha1sum of the package tarball. [br]
##
## Returns: [br]
## [param bool] - If the given package/sha1sum pair exist in the lock file.
func has(package_name: String, sha1sum: String) -> bool:
	if not packages.has(package_name):
		return false
	
	if packages[package_name] != sha1sum:
		return false
	
	return true
