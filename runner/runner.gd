extends CanvasLayer

const Main := preload("res://addons/godot-package-manager/main.tscn")
const DummyPlugin := preload("res://runner/dummy_plugin.gd")

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	OS.center_window()
	
	var dummy_plugin := DummyPlugin.new()
	add_child(dummy_plugin)
	
	var main = Main.instance()
	main.plugin = dummy_plugin
	add_child(main)
	
	var theme = load("res://runner/main.theme")
	main.theme = theme

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Private functions                                                           #
###############################################################################

###############################################################################
# Public functions                                                            #
###############################################################################
