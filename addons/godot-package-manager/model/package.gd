extends RefCounted

var name := ""
var version := ""

var download_dir := ""

var is_installed := false
var is_indirect := false

var dependencies := []

var npm_manifest := {}

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

func normalize() -> int:
	
	
	return OK

## 
func unscoped_name() -> String:
	return name.get_file()
