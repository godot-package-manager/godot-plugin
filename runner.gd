extends CanvasLayer

const MainScene := preload("res://addons/godot-package-manager/gui/main.tscn")

var main: Node = null

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	main = MainScene.instantiate()
	main.plugin = self
	add_child(main)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Here to ensure compatibility.
func inject_tool(_node: Node) -> void:
	pass
