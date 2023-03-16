@tool
extends EditorPlugin

const MainScene := preload("res://addons/godot-package-manager/gui/main.tscn")

const PLUGIN_NAME := "Packages"

var main: Node = null

func _enter_tree() -> void:
	main = MainScene.instantiate()
	inject_tool(main)
	main.plugin = self
	
	get_editor_interface().get_editor_main_screen().add_child(main)
	main.visible = false

func _exit_tree() -> void:
	if main != null:
		main.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main != null:
		main.visible = visible

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("ResourcePreloader", "EditorIcons")

## Take any non-tool script and runtime-reload it to work as a tool script.
func inject_tool(node: Node) -> void:
	var script: GDScript = node.get_script().duplicate()
	script.source_code = "@tool\n%s" % script.source_code
	script.reload(false)
	
	node.set_script(script)
