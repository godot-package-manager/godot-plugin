extends RefCounted

## The full, scoped name of the package.
var name := ""
## The version of the package. Cannot be an integer since versions are usually in format x.x.x .
var version := ""
## If the package is explicitly listed in the package file. Indirect depedencies are
## dependencies of packages listed in the package file.
var is_indirect := false

## If the package has been downloaded and processed.
var is_installed := false
## The directly the package was installed into. Only important for indirect dependencies.
var install_dir := ""

## [Array] of [Package]. Flattened dependency structure.
var dependencies := []

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init(name: String, version: String, is_indirect: bool) -> void:
	self.name = name
	self.version = version
	self.is_indirect = is_indirect

func _to_string() -> String:
	return "[%s: %s@%s]" % ["Package" if not is_indirect else "Indirect", name, version]

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Get the name without the scope. Necessary for creating directories since the scope
## can contain an "@" character. [br]
##
## Returns: [br]
## [param String] - The unscoped name.
func unscoped_name() -> String:
	return name.get_file()
