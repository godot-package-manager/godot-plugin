extends HBoxContainer

var extra_data := {}

@onready
var package_name := %PackageName
@onready
var version := %Version
@onready
var installed := %Installed
@onready
var delete := %Delete

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

func update_tooltip() -> void:
	var hint := ""
	for key in extra_data.keys():
		var val = extra_data[key]
		hint = ("%s\n%s - %s" % [hint, key, str(val)])
	
	hint = hint.strip_edges()
	
	for i in [self, package_name, version, installed]:
		i.tooltip_text = hint

func should_delete() -> bool:
	return delete.button_pressed
