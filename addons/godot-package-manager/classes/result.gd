class_name GPMResult

# const Error = preload("res://addons/godot-package-manager/classes/error.gd")

var _value
var _error: GPMError

func _init(v) -> void:
    if not v is GPMError:
        _value = v
    else:
        _error = v

func _to_string() -> String:
    if is_err():
        return "ERR: %s" % str(_error)
    else:
        return "OK: %s" % str(_value)

func is_ok() -> bool:
    return not is_err()

func is_err() -> bool:
    return _error != null

func unwrap():
    return _value

func unwrap_err() -> GPMError:
    return _error

func expect(text: String):
    if is_err():
        printerr(text)
        return null
    return _value

func or_else(val):
    return _value if is_ok() else val

