#!/usr/bin/env -S godot --no-window --script

#Must inherit from SceneTree according to https://docs.godotengine.org/en/latest/tutorials/editor/command_line_tutorial.html#running-a-script
extends SceneTree

signal finished

const GPM_PATH = "addons/godot-package-manager/"
const GPM_MAIN_SCRIPT = "godot_package_manager.gd"
const GPM_CONFIG = "godot.package"

var gpm: GPM = load("res://"+GPM_PATH+GPM_MAIN_SCRIPT).new()

func _init():
	#connecting signals
	var _connect_res = null

	_connect_res = gpm.connect("operation_started", self, "_on_operation_started")
	_connect_res = gpm.connect("message_logged", self, "_on_message_logged")
	_connect_res = gpm.connect("operation_checkpoint_reached", self, "_on_operation_checkpoint_reached")
	_connect_res = gpm.connect("operation_finished", self, "_on_update_finished")
	
	#Separate main function should simplify
	main()
	
func main():
	_log("Entrering main function")
	_log("TBD: parse arguments")
	var res = gpm.read_config(GPM_CONFIG)
	gpm.update()
	

#-------

###############################################################################
# Signals processing
###############################################################################


func _on_status() -> void:
	_log("Getting package status")
	var res = yield(gpm.dry_run(), "completed")
	if res.is_ok():
		var data: Dictionary = res.unwrap()
		if data.get(gpm.DryRunValues.OK, false):
			_log("All packages okay, no update required")
			return
		
		if not data.get(gpm.DryRunValues.UPDATE, []).empty():
			_log("Packages to update:")
			for i in data[gpm.DryRunValues.UPDATE]:
				_log(i)
		if not data.get(gpm.DryRunValues.INVALID, []).empty():
			_log("Invalid packages:")
			for i in data[gpm.DryRunValues.INVALID]:
				_log(i)
	else:
		_log(res.unwrap_err().to_string())

func _on_update(force: bool) -> void:
	_log("Updating all valid packages")
	var res = yield(gpm.update(force), "completed")
	if res.is_ok():
		_log("Update successful")
	else:
		_log(res.unwrap_err().to_string())

func _on_clear(_text_edit: TextEdit) -> void:
	_log("_on_clear")
	# text_edit.text = ""

func _on_purge() -> void:
	# if purge_button.text == PURGE_TEXT:
	# 	purge_button.text = CONFIRM_TEXT
	# else:
	_log("Purging all downloaded packages")
	gpm.purge()

func _on_purge_reset() -> void:
	_log("_on_purge_reset")
	# purge_button.text = PURGE_TEXT

func _on_message_logged(text: String) -> void:
	_log(text)

#region Update

func _on_operation_started(operation: String, num_packages: int) -> void:
	_log("Running %s for %d packages" % [operation, num_packages])

func _on_operation_checkpoint_reached(package_name: String) -> void:
	_log("Processing %s" % package_name)

func _on_update_finished() -> void:
	_log("_on_update_finished")
	_log("Finished")
	quit()

###############################################################################
# Private functions                                                           #
###############################################################################

func _log(text) -> void:
	print(text)


###############################################################################
# Public functions                                                            #
###############################################################################
