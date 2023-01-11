extends PanelContainer

## Main GUI for the plugin. Screens are instantiated manually since they need to be transformed
## into tool scripts.

const NpmSearch := preload("res://addons/godot-package-manager/gui/npm_search.tscn")
const NPM_SEARCH_NAME := "NPM Search"

var plugin: Node = null
var gpm := preload("res://addons/godot-package-manager/gpm.gd").new()

@onready
var edit_config_button: Button = %EditConfig
@onready
var package_status_button: Button = %PackageStatus
@onready
var update_packages_button: Button = %UpdatePackages
@onready
var clear_packages_button: Button = %ClearPackages

@onready
var screens: TabContainer = %Screens

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	edit_config_button.pressed.connect(func() -> void:
		pass
	)
	package_status_button.pressed.connect(func() -> void:
		pass
	)
	update_packages_button.pressed.connect(func() -> void:
		pass
	)
	clear_packages_button.pressed.connect(func() -> void:
		pass
	)
	
	var npm_search := NpmSearch.instantiate()
	plugin.inject_tool(npm_search)
	npm_search.name = NPM_SEARCH_NAME
	
	screens.add_child(npm_search)
	
	var sadf = preload("res://addons/godot-package-manager/model/package.gd").new()
	var asdf = preload("res://addons/godot-package-manager/model/package_list.gd").new()
	
	# TODO testing
#	var body: Dictionary = await gpm.npm.get_manifest(gpm.net, "@sometimes_youwin/gut", "7.3.0")
#	print("received body")
#	print(body)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#
