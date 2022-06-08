
const GPM_PATH = "res://addons/godot-package-manager/classes/"
const ERROR = "error.gd"
const ERROR_PATH = GPM_PATH + ERROR

class Error extends "res://addons/godot-package-manager/classes/error.gd".Error:
    pass

class Result:
	var _value
	var _error: Error

	func _init(v) -> void:
		if not v is Error:
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

	func unwrap_err() -> Error:
		return _error

	func expect(text: String):
		if is_err():
			printerr(text)
			return null
		return _value

	func or_else(val):
		return _value if is_ok() else val

	static func ok(v = null) -> Result:
		var res = Result.new(OK)
		return Result.new(v if v != null else OK)

	static func err(error_code: int = 1, description: String = "") -> Result:
		return Result.new(Error.new(error_code, description))