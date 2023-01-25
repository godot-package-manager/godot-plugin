extends Window

@onready
var _logs: TextEdit = %Logs

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	popup_centered_ratio(0.5)
	
	close_requested.connect(func() -> void:
		queue_free()
	)
	visibility_changed.connect(func() -> void:
		close_requested.emit()
	)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Adds a log message to be displayed.
func add_log(text: String) -> void:
	_logs.text = ("%s\n%s" % [_logs.text, text]).strip_escapes()
