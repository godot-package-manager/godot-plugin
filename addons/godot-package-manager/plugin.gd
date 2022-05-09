tool
extends EditorPlugin

const Main := preload("res://addons/godot-package-manager/main.tscn")

const TOOLBAR_NAME := "Package Manager"

var main

const PACKAGES_BUTTON_NAME := "Packages"
const PURGE_SUBMENU_NAME := "Purge"
var packages_button: MenuButton

var rtl: RichTextLabel

func _enter_tree():
#	main = Main.instance()
#	inject_tool(main)
	
#	add_control_to_bottom_panel(main, TOOLBAR_NAME)

	packages_button = MenuButton.new()
	packages_button.name = PACKAGES_BUTTON_NAME
	packages_button.text = PACKAGES_BUTTON_NAME
	
	var packages_popup: PopupMenu = packages_button.get_popup()
	packages_popup.add_item("Status")
	packages_popup.add_item("Update")
	packages_popup.add_submenu_item(PURGE_SUBMENU_NAME, PURGE_SUBMENU_NAME)
	
	packages_popup.connect("index_pressed", self, "_on_item_pressed")
	
	var purge_submenu := PopupMenu.new()
	purge_submenu.name = PURGE_SUBMENU_NAME
	purge_submenu.add_item("Confirm")
	
	purge_submenu.connect("index_pressed", self, "_on_purge")
	
	packages_popup.add_child(purge_submenu)
	
	var base_control := get_editor_interface().get_base_control()
	
	base_control.get_child(0).get_child(0).get_child(0).add_child(packages_button)
	
	rtl = get_editor_interface().get_base_control() \
			.get_child(0).get_child(1).get_child(1) \
			.get_child(1).get_child(0).get_child(0) \
			.get_child(1).get_child(0).get_child(0) \
			.get_child(1)

func _exit_tree():
	if main != null:
		remove_control_from_bottom_panel(main)
		main.free()
	if packages_button != null:
		packages_button.free()

#func enable_plugin():
#	make_bottom_panel_item_visible(main)

func _on_item_pressed(idx: int) -> void:
	pass

func _on_purge(_idx: int) -> void:
	print("Not yet implemented")
	pass

func inject_tool(node: Node) -> void:
	"""
	Inject `tool` at the top of the plugin script
	"""
	var script: Script = node.get_script().duplicate()
	script.source_code = "tool\n%s" % script.source_code
	script.reload(false)
	node.set_script(script)
