extends PanelContainer

var gpm = preload("res://addons/godot-package-manager/godot_package_manager.gd").new()

const PURGE_TEXT := "Purge"
const CONFIRM_TEXT := "Confirm"
var purge_button: Button

var status: TextEdit

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	gpm.connect("update_started", self, "_on_update_started")
	gpm.connect("update_checkpoint", self, "_on_update_checkpoint")
	gpm.connect("update_finshed", self, "_on_update_finished")
	
	purge_button = $VBoxContainer/HBoxContainer/Purge
	status = $VBoxContainer/Status
	
	$VBoxContainer/HBoxContainer/Status.connect("pressed", self, "_on_status")
	$VBoxContainer/HBoxContainer/Update.connect("pressed", self, "_on_update")
	purge_button.connect("pressed", self, "_on_purge")
	purge_button.connect("mouse_exited", self, "_on_purge_reset")

###############################################################################
# Connections                                                                 #
###############################################################################

func _on_status() -> void:
	_log("Not yet implemented")

func _on_update() -> void:
	var res = yield(gpm.update(), "completed")
	_log(res.to_string())

func _on_purge() -> void:
	if purge_button.text == PURGE_TEXT:
		purge_button.text = CONFIRM_TEXT
	else:
		_log("Not yet implemented")

func _on_purge_reset() -> void:
	purge_button.text = PURGE_TEXT

func _on_update_started(num_packages: int) -> void:
	_log("Running Godot Package Manager for %d packages" % num_packages)

func _on_update_checkpoint(num: int) -> void:
	_log("Package #%d complete" % num)

func _on_update_finished() -> void:
	_log("Godot Package Manager update completed")

###############################################################################
# Private functions                                                           #
###############################################################################

func _log(text: String) -> void:
	status.text = "%s%s\n" % [status.text, text]

###############################################################################
# Public functions                                                            #
###############################################################################
