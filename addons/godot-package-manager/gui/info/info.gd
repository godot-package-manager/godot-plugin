extends VBoxContainer

const Package := GodotPackageManager.Model.Package

const PackageInfo := preload("res://addons/godot-package-manager/gui/info/package_info.tscn")

var plugin: Node = null
var gpm: GodotPackageManager = null

@onready
var packages := %Packages

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	%WriteChanges.pressed.connect(func() -> void:
		pass
	)
	%ResetChanges.pressed.connect(func() -> void:
		update(gpm.config.packages.values(), gpm.lock_file.packages)
	)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

func _clear() -> void:
	for i in packages.get_children():
		i.free()

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

func update(packages: Array, shas: Dictionary) -> void:
	_clear()
	
	for package in packages:
		var package_info := PackageInfo.instantiate()
		plugin.inject_tool(package_info)
		self.packages.add_child(package_info)
		
		package_info.package_name.text = package.name
		package_info.version.text = package.version
		package_info.installed.button_pressed = package.is_installed
		
		package_info.extra_data["indirect"] = package.is_indirect
		package_info.extra_data["dependencies"] = package.dependencies.map(func(p: Package) -> String:
			return "%s@%s" % [p.name, p.version]
		)
		package_info.extra_data["sha"] = shas.get(package.name, "Not found in lock file.")
		
		package_info.update_tooltip()
