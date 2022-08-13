extends SceneTree

#-----------------------------------------------------------------------------#
# Builtin functions                                                           #
#-----------------------------------------------------------------------------#


func _initialize() -> void:
	var gpm = preload("./godot_package_manager.gd").new()
	gpm.connect("operation_finished", self, "_on_finished")
	gpm.connect("message_logged", self, "_on_message_logged")
	gpm.connect("operation_started", self, "_on_operation_started")

	var call_func := ""

	var args := OS.get_cmdline_args()
	for arg in args:
		arg = (arg as String).lstrip("-").trim_prefix("package-")

		if arg in ["update", "purge"]:
			call_func = arg
			break

	if call_func.empty():
		printerr("No action specified")
		quit(1)
		return

	gpm.call(call_func)


#-----------------------------------------------------------------------------#
# Connections                                                                 #
#-----------------------------------------------------------------------------#

func _on_operation_started(op_name: String, num_packages: int) -> void:
	print("Operation started: %s (%d packages)" % [op_name, num_packages])


func _on_finished() -> void:
	print("Finished!")
	quit(0)


func _on_message_logged(message: String) -> void:
	print(message)

#-----------------------------------------------------------------------------#
# Private functions                                                           #
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions                                                            #
#-----------------------------------------------------------------------------#
