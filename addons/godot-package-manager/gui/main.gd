extends PanelContainer

## Main GUI for the plugin. Screens are instantiated manually since they need to be transformed
## into tool scripts.

## Emitted when the GUI status has been updated.
signal status_updated(text: String)

const EditConfig := preload("res://addons/godot-package-manager/gui/edit_config.tscn")
const Logs := preload("res://addons/godot-package-manager/gui/logs.tscn")

const NpmSearch := preload("res://addons/godot-package-manager/gui/npm_search.tscn")
const NPM_SEARCH_NAME := "NPM Search"

var plugin: Node = null
var gpm := preload("res://addons/godot-package-manager/gpm.gd").new()

@onready
var _screens: TabContainer = %Screens

@onready
var _status: RichTextLabel = %Status

var _logs: Array[String] = []
const MAX_LOGS: int = 50
var _log_popup: Window = null

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	%EditConfig.pressed.connect(func() -> void:
		var popup := EditConfig.instantiate()
		plugin.inject_tool(popup)
		
		add_child(popup)
	)
	%PackageStatus.pressed.connect(func() -> void:
		pass
	)
	%UpdatePackages.pressed.connect(func() -> void:
		pass
	)
	%ClearPackages.pressed.connect(func() -> void:
		var popup := ConfirmationDialog.new()
		var p_label := popup.get_label()
		p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		popup.dialog_text = "Clear all local packages? (No undo!)"
		
		add_child(popup)
		popup.popup_centered_ratio(0.5)
		
		popup.visibility_changed.connect(func() -> void:
			popup.queue_free()
		)
		popup.confirmed.connect(func() -> void:
			# TODO stub
			pass
		)
		popup.cancelled.connect(func() -> void:
			popup.hide()
		)
	)
	%PluginLogs.pressed.connect(func() -> void:
		_show_logs_popup()
	)
	
	_status.gui_input.connect(func(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		if not event.double_click:
			return
		
		_show_logs_popup()
	)
	
	var npm_search := NpmSearch.instantiate()
	plugin.inject_tool(npm_search)
	npm_search.name = NPM_SEARCH_NAME
	
	_screens.add_child(npm_search)
	
	# TODO testing
#	var body: Dictionary = await gpm.npm.get_manifests(gpm.net, "@sometimes_youwin/gut")
#	var body: Array = await gpm.npm.search("verbal expressions")
#	print(JSON.stringify(body, "\t"))
	
#	var body: Dictionary = await gpm.npm.get_manifest("@sometimes_youwin/verbal-expressions", "1.0.1")
#	print(JSON.stringify(body, "\t"))
	
#	var config := gpm.Config.new()
#	await config.parse({
#		"@sometimes_youwin/verbal-expressions": "1.0.1"
#	})
#
#	print("finished parsing")
#
#	for i in config:
#		print(i)
	
	var data := await gpm.update_packages()

#	var regex := RegEx.create_from_string("(pre)?load\\(\\\"([^)]+)\\\"\\)")
#	for m in regex.search_all("""
#extends Node
#
#const Whatever := preload("res://some/path/here.gd")
#
#func _ready() -> void:
#	pass
#	""".strip_edges()):
#		print(m.strings)
	
	update_status("Ready!")

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Shows a log popup containing the most recent logs. Note that logs are cleared according
## the the [code]MAX_LOGS[/code] constant.
func _show_logs_popup() -> void:
	if (_log_popup != null) and is_instance_valid(_log_popup):
		_log_popup.move_to_foreground()
		return
	
	_log_popup = Logs.instantiate()
	plugin.inject_tool(_log_popup)
	
	add_child(_log_popup)
	
	for i in self._logs:
		_log_popup.add_log(i)
	
	self.status_updated.connect(func(text: String) -> void:
		_log_popup.add_log(text)
	)

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Update the status element with an added timestamp. The message + timestamp are also
## added to the log history.
func update_status(something: Variant) -> void:
	var datetime := Time.get_datetime_dict_from_system()
	var text := "%02d-%02d-%04d_%02d:%02d:%02d %s" % [
		datetime.day,
		datetime.month,
		datetime.year,
		datetime.hour,
		datetime.minute,
		datetime.second,
		str(something)
	]
	_status.text = text
	status_updated.emit(text)
	
	_logs.push_back(text)
	if _logs.size() > MAX_LOGS:
		_logs.pop_front()
