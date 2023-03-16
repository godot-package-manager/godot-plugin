extends VBoxContainer

var plugin: Node = null
var gpm: GodotPackageManager = null

@onready
var search_element: LineEdit = %Search
@onready
var results_element: VBoxContainer = %Results

const DEBOUNCE_TICKS: int = 1000
var _last_debounce_ticks: int = Time.get_ticks_msec()

## Needed to prevent DOSing NPM if someone were to mash the enter key.
var _last_search_text := ""

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _ready() -> void:
	var search_bar := %Search as LineEdit
	search_bar.text_changed.connect(func(text: String) -> void:
		var new_ticks := Time.get_ticks_msec()
		if new_ticks - _last_debounce_ticks > 1000:
			_search_npm(text)
		_last_debounce_ticks = Time.get_ticks_msec()
	)
	search_bar.text_submitted.connect(func(text: String) -> void:
		_last_debounce_ticks = Time.get_ticks_msec()
		
		_search_npm(text)
	)

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

func _search_npm(text: String) -> void:
	if text == _last_search_text:
		return
	_last_search_text = text
	
	var results: Array[Dictionary] = await GodotPackageManager.Npm.search(text)
	
	for i in results:
		var data: Dictionary = i.get("package", {})
		if data.is_empty():
			printerr("Received empty data from npm search: %s" % text)
			continue
		
		

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

