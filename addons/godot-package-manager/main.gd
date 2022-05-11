extends PanelContainer

var plugin

var gpm = preload("res://addons/godot-package-manager/godot_package_manager.gd").new()

const PURGE_TEXT := "Purge"
const CONFIRM_TEXT := "Confirm"
var purge_button: Button

var status: TextEdit

###############################################################################
# Builtin functions                                                           #
###############################################################################

func _ready() -> void:
	gpm.connect("operation_started", self, "_on_operation_started")
	gpm.connect("message_logged", self, "_on_message_logged")
	gpm.connect("operation_checkpoint_reached", self, "_on_operation_checkpoint_reached")
	gpm.connect("operation_finished", self, "_on_update_finished")
	
	status = $VBoxContainer/Status
	
	var edit_package_button := $VBoxContainer/HBoxContainer/EditPackage as Button
	edit_package_button.hint_tooltip = "Edit the godot.package file"
	edit_package_button.connect("pressed", self, "_on_edit_package")
	
	var status_button := $VBoxContainer/HBoxContainer/Status as Button
	status_button.hint_tooltip = "Get the current package status"
	status_button.connect("pressed", self, "_on_status")
	
	var update_button := $VBoxContainer/HBoxContainer/Update as Button
	update_button.hint_tooltip = "Update all packages, skipping packages if they are up-to-date"
	update_button.connect("pressed", self, "_on_update", [false])
	
	var force_update_button := $VBoxContainer/HBoxContainer/ForceUpdate as Button
	force_update_button.hint_tooltip = "Update all packages, deleting them if they already exist"
	force_update_button.connect("pressed", self, "_on_update", [true])
	
	var clear_button := $VBoxContainer/HBoxContainer/Clear as Button
	clear_button.hint_tooltip = "Clear the console"
	clear_button.connect("pressed", self, "_on_clear", [status])
	
	purge_button = $VBoxContainer/HBoxContainer/Purge as Button
	purge_button.hint_tooltip = "Delete all local packages"
	purge_button.connect("pressed", self, "_on_purge")
	purge_button.connect("mouse_exited", self, "_on_purge_reset")

###############################################################################
# Connections                                                                 #
###############################################################################

#region Edit godot.package

func _on_edit_package() -> void:
	var popup := WindowDialog.new()
	popup.window_title = "Editing res://%s" % gpm.PACKAGE_FILE
	popup.anchor_bottom = 1.0
	popup.anchor_right = 1.0
	popup.connect("modal_closed", self, "_delete", [popup])
	popup.connect("popup_hide", self, "_delete", [popup])
	
	var vbox := VBoxContainer.new()
	vbox.anchor_bottom = 1.0
	vbox.anchor_right = 1.0
	vbox.margin_left = 10
	vbox.margin_right = -10
	vbox.margin_top = 10
	vbox.margin_bottom = -10
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var text_edit := TextEdit.new()
	text_edit.draw_tabs = true
	text_edit.draw_spaces = true
	text_edit.show_line_numbers = true
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_edit)
	
	var status_bar := Label.new()
	vbox.add_child(status_bar)
	
	var save_bar := HBoxContainer.new()
	save_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var save_button := Button.new()
	save_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	save_button.connect("pressed", self, "_save_edit_package", [popup, status_bar, text_edit])
	save_button.text = "Save"
	
	save_bar.add_child(save_button)
	
	var discard_button := Button.new()
	discard_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	discard_button.text = "Discard changes"
	discard_button.connect("pressed", self, "_delete", [popup])
	
	save_bar.add_child(discard_button)
	
	vbox.add_child(save_bar)
	
	popup.add_child(vbox)
	
	plugin.get_editor_interface().get_base_control().add_child(popup)
	popup.popup_centered_ratio()
	
	var file := File.new()
	if file.open(gpm.PACKAGE_FILE, File.READ) != OK:
		_log("No res://%s file found, creating new file" % gpm.PACKAGE_FILE)
		return
	
	text_edit.text = file.get_as_text()

func _delete(node: Node) -> void:
	node.queue_free()

func _save_edit_package(node: Node, status_bar: Label, text_edit: TextEdit) -> void:
	var parse_res := JSON.parse(text_edit.text)
	if parse_res.error != OK:
		var message: String = "Syntax error detected\nLine: %d\nError: %s" % [parse_res.error_line, parse_res.error_string]
		status_bar.text = message
		_log(message)
		return
	
	if not parse_res.result is Dictionary:
		var message: String = "%s must be a Dictionary" % gpm.PACKAGE_FILE
		status_bar.text = message
		_log(message)
		return
	
	var file := File.new()
	if file.open(gpm.PACKAGE_FILE, File.WRITE) != OK:
		_log("Unable to open %s for writing" % gpm.PACKAGE_FILE)
		return
	
	file.store_string(text_edit.text)
	
	file.close()
	
	_log("%s saved successfully" % gpm.PACKAGE_FILE)
	node.queue_free()

#endregion

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

func _on_clear(text_edit: TextEdit) -> void:
	text_edit.text = ""

func _on_purge() -> void:
	if purge_button.text == PURGE_TEXT:
		purge_button.text = CONFIRM_TEXT
	else:
		_log("Purging all downloaded packages")
		gpm.purge()

func _on_purge_reset() -> void:
	purge_button.text = PURGE_TEXT

func _on_message_logged(text: String) -> void:
	_log(text)

#region Update

func _on_operation_started(operation: String, num_packages: int) -> void:
	_log("Running %s for %d packages" % [operation, num_packages])

func _on_operation_checkpoint_reached(package_name: String) -> void:
	_log("Processing %s" % package_name)

func _on_update_finished() -> void:
	plugin.get_editor_interface().get_resource_filesystem().scan()
	_log("Finished")

#endregion

###############################################################################
# Private functions                                                           #
###############################################################################

func _log(text: String) -> void:
	status.text = "%s%s\n" % [status.text, text]
	status.cursor_set_line(status.get_line_count())

###############################################################################
# Public functions                                                            #
###############################################################################
