extends "res://addons/godot-package-manager/model/package_list.gd"

const GPM := preload("res://addons/godot-package-manager/gpm.gd")

var _gpm: GPM = null

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init(gpm: GPM) -> void:
	_gpm = gpm

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#



#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

func update() -> int:
	
	
	return OK
