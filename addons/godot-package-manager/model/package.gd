extends RefCounted

var name := ""
var version := ""

var is_indirect := false

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
## can contain an "@" character.
func unscoped_name() -> String:
	return name.get_file()
