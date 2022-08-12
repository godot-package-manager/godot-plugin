extends SceneTree

#-----------------------------------------------------------------------------#
# Builtin functions                                                           #
#-----------------------------------------------------------------------------#

func _initialize() -> void:
	var gpm = preload("./godot_package_manager.gd").new()
	gpm.connect("operation_finished", self, "_on_finished")
	
	var call_func := ""
	
	var args := OS.get_cmdline_args()
	for arg in args:
		arg = (arg as String).lstrip("-").trim_prefix("package-")
		
		if arg in ["update", "purge"]:
			call_func = arg
			break
	
	if call_func.empty():
		printerr("No args passed, exiting")
		quit(1)
		return
	
	gpm.call(call_func)

#-----------------------------------------------------------------------------#
# Connections                                                                 #
#-----------------------------------------------------------------------------#

func _on_finished() -> void:
	quit()

#-----------------------------------------------------------------------------#
# Private functions                                                           #
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions                                                            #
#-----------------------------------------------------------------------------#
