class_name GPMAdvancedExpression

class GPMAbstractCode:
	var _cache := []
	
	func _to_string() -> String:
		return "%s\n%s" % [_get_name(), output()]
	
	func _get_name() -> String:
		return "GPMAbstractCode"
	
	static func _build_string(list: Array) -> String:
		return PoolStringArray(list).join("")
	
	func tab(times: int = 1) -> GPMAbstractCode:
		for i in times:
			_cache.append("\t")
		return self
	
	func newline() -> GPMAbstractCode:
		_cache.append("\n")
		return self
	
	func add(text) -> GPMAbstractCode:
		match typeof(text):
			TYPE_STRING:
				tab()
				_cache.append(text)
				newline()
			TYPE_ARRAY:
				_cache.append_array(text)
			_:
				push_error("Invalid type for add: %s" % str(text))
		
		return self
	
	func clear_cache() -> GPMAbstractCode:
		_cache.clear()
		return self
	
	func output() -> String:
		return _build_string(_cache)
	
	func raw_data() -> Array:
		return _cache

class Variable extends GPMAbstractCode:
	func _init(var_name: String, var_value: String = "") -> void:
		_cache.append("var %s = " % var_name)
		if not var_value.empty():
			_cache.append(var_value)
	
	func _get_name() -> String:
		return "Variable"
	
	func add(text) -> GPMAbstractCode:
		_cache.append(str(text))
		
		return self
	
	func output() -> String:
		return "%s\n" % .output()

class AbstractFunction extends GPMAbstractCode:
	var _function_def := ""
	var _params := []
	
	func _get_name() -> String:
		return "AbstractFunction"
	
	func _construct_params() -> String:
		var params := []
		params.append("(")
		
		for i in _params:
			params.append(i)
			params.append(",")
		
		# Remove the last comma
		if params.size() > 1:
			params.pop_back()
		
		params.append(")")
		
		return PoolStringArray(params).join("") if not params.empty() else ""
	
	func add_param(text: String) -> AbstractFunction:
		if _params.has(text):
			push_error("Tried to add duplicate param %s" % text)
		else:
			_params.append(text)
		
		return self
	
	func output() -> String:
		var params = _construct_params()
		var the_rest = _build_string(_cache)
		return "%s%s" % [_function_def % _construct_params(), _build_string(_cache)]

class Function extends AbstractFunction:
	func _init(text: String) -> void:
		_function_def = "func %s%s:" % [text, "%s"]
		# Always add a newline into the cache
		newline()
	
	func _get_name() -> String:
		return "Function"

class Runner extends AbstractFunction:
	func _init() -> void:
		_function_def = "func %s%s:" % [RUN_FUNC, "%s"]
		# Always add a newline into the cache
		newline()
	
	func _get_name() -> String:
		return "Runner"

const RUN_FUNC := "__runner__"

var variables := []
var functions := []
var runner := Runner.new()

var gdscript: GDScript

func _to_string() -> String:
	return _build_source(variables, functions, runner)

static func _build_source(v: Array, f: Array, r: Runner) -> String:
	var source := ""
	
	for i in v:
		source += i.output()
	
	for i in f:
		source += i.output()
	
	source += r.output()
	
	return source

static func _create_script(v: Array, f: Array, r: Runner) -> GDScript:
	var s := GDScript.new()
	
	var source := ""
	
	for i in v:
		source += i.output()
	
	for i in f:
		source += i.output()
	
	source += r.output()
	
	s.source_code = source
	
	return s

func add_variable(variable_name: String, variable_value: String = "") -> Variable:
	var variable := Variable.new(variable_name, variable_value)
	
	variables.append(variable)
	
	return variable

func add_function(function_name: String) -> Function:
	var function := Function.new(function_name)
	
	functions.append(function)
	
	return function

func add(text: String = "") -> Runner:
	if not text.empty():
		runner.add(text)
	
	return runner

func add_raw(text: String) -> Runner:
	var split := text.split(";")
	for i in split:
		runner.add(i)
	
	return runner

func tab(amount: int = 1) -> Runner:
	runner.tab(amount)
	
	return runner

func newline() -> Runner:
	runner.newline()
	
	return runner

func compile() -> int:
	gdscript = _create_script(variables, functions, runner)
	
	return gdscript.reload()

func execute(params: Array = []):
	return gdscript.new().callv(RUN_FUNC, params)

func clear() -> void:
	gdscript = null
	
	variables.clear()
	functions.clear()
	runner = Runner.new()