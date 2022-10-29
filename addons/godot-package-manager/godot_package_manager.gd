extends Reference

#region Error handling

const DEFAULT_ERROR := "Default error"
class Error:
	enum Code {
		NONE = 0,
		GENERIC,

		#region JSON handling

		INVALID_JSON,
		UNEXPECTED_JSON_FORMAT,

		#endregion

		#region Http requests

		INITIATE_CONNECT_TO_HOST_FAILURE,
		UNABLE_TO_CONNECT_TO_HOST,

		UNSUCCESSFUL_REQUEST,
		MISSING_RESPONSE,
		UNEXPECTED_STATUS_CODE,

		GET_REQUEST_FAILURE,

		#endregion

		#region Config

		FILE_OPEN_FAILURE,
		PARSE_FAILURE,
		UNEXPECTED_DATA,

		NO_PACKAGES,
		PROCESS_PACKAGES_FAILURE

		REMOVE_PACKAGE_DIR_FAILURE

		#endregion

		#region AdvancedExpression

		MISSING_SCRIPT,
		BAD_SCRIPT_TYPE,
		SCRIPT_COMPILE_FAILURE,

		#endregion
	}

	var _error: int
	var _description: String

	func _init(error: int, description: String = "") -> void:
		_error = error
		_description = description
	
	func _to_string() -> String:
		return "Code: %d\nName: %s\nDescription: %s" % [_error, error_name(), _description]

	func error_code() -> int:
		return _error

	func error_name() -> int:
		return Code.keys()[_error]

	func error_description() -> String:
		return _description

class PackageResult:
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

	static func ok(v = null) -> PackageResult:
		var res = PackageResult.new(OK)
		return PackageResult.new(v if v != null else OK)

	static func err(error_code: int = 1, description: String = "") -> PackageResult:
		return PackageResult.new(Error.new(error_code, description))

#endregion

class FailedPackages:
	var failed_package_log := [] # Log of failed packages and reasons
	var failed_packages := [] # Array of failed package names only

	func add(package_name: String, reason: String) -> void:
		failed_package_log.append("%s - %s" % [package_name, reason])
		failed_packages.append(package_name)

	func get_logs() -> String:
		failed_package_log.invert()
		return PoolStringArray(failed_package_log).join("\n")

	func has_logs() -> bool:
		return not failed_package_log.empty()
	
	func get_failed_packages() -> Array:
		return failed_packages.duplicate()

class Hooks:
	var _hooks := {} # Hook name: String -> AdvancedExpression

	func add(hook_name: String, advanced_expression: AdvancedExpression) -> void:
		_hooks[hook_name] = advanced_expression

	## Runs the given hook if it exists. Requires the containing GPM to be passed
	## since all scripts assume they have access to a `gpm` variable
	##
	## @param: gpm: Object - The containing GPM. Must be a valid `Object`
	## @param: hook_name: String - The name of the hook to run
	##
	## @return: Variant - The return value, if any. Will return `null` if the hook is not found
	func run(gpm: Object, hook_name: String):
		return _hooks[hook_name].execute([gpm]) if _hooks.has(hook_name) else null

#region Script/expression handling

class AdvancedExpression:
	class AbstractCode:
		var _cache := []
		
		func _to_string() -> String:
			return "%s\n%s" % [_get_name(), output()]
		
		func _get_name() -> String:
			return "AbstractCode"
		
		static func _build_string(list: Array) -> String:
			return PoolStringArray(list).join("")
		
		func tab(times: int = 1) -> AbstractCode:
			for i in times:
				_cache.append("\t")
			return self
		
		func newline() -> AbstractCode:
			_cache.append("\n")
			return self
		
		func add(text) -> AbstractCode:
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
		
		func clear_cache() -> AbstractCode:
			_cache.clear()
			return self
		
		func output() -> String:
			return _build_string(_cache)
		
		func raw_data() -> Array:
			return _cache

	class Variable extends AbstractCode:
		func _init(var_name: String, var_value: String = "") -> void:
			_cache.append("var %s = " % var_name)
			if not var_value.empty():
				_cache.append(var_value)
		
		func _get_name() -> String:
			return "Variable"
		
		func add(text) -> AbstractCode:
			_cache.append(str(text))
			
			return self
		
		func output() -> String:
			return "%s\n" % .output()

	class AbstractFunction extends AbstractCode:
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

#endregion

## A message that may be logged at any point during runtime
signal message_logged(text)

## Signifies the start of a package operation
signal operation_started(op_name, num_packages)
## Emitted when a package has started processing
signal operation_checkpoint_reached(package_name)
## Emitted when the package operation is complete
signal operation_finished()

#region Constants

const REGISTRY := "https://registry.npmjs.org"
const ADDONS_DIR := "res://addons"
const ADDONS_DIR_FORMAT := ADDONS_DIR + "/%s"
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

const DryRunValues := {
	"OK": "ok",
	"UPDATE": "packages_to_update",
	"INVALID": "packages_with_errors"
}

const CONNECTING_STATUS := [
	HTTPClient.STATUS_CONNECTING,
	HTTPClient.STATUS_RESOLVING
]
const SUCCESS_STATUS := [
	HTTPClient.STATUS_BODY,
	HTTPClient.STATUS_CONNECTED,
]

const HEADERS := [
	"User-Agent: GodotPackageManager/1.0 (you-win on GitHub)",
	"Accept: */*"
]

const PACKAGE_FILE := "godot.package"
const PackageKeys := {
	"PACKAGES": "packages",
	"HOOKS": "hooks",
	"VERSION": "version",
	"SCRIPTS": "scripts",
	"REQUIRED_WHEN": "required_when",
	"OPTIONAL_WHEN": "optional_when"
}
const LOCK_FILE := "godot.lock"
const LockFileKeys := {
	"VERSION": "version",
	"INTEGRITY": "integrity",
	"INDIRECT": "indirect",
	"DIRECTORY": "dir"
}

const NPM_PACKAGE_FILE := "package.json"
const NpmManifestKeys := {
	"VERSION": "version",
	"DIST": "dist",
	"INTEGRITY": "integrity",
	"TARBALL": "tarball"
}
const NpmPackageKeys := {
	"PACKAGES": "dependencies",
}

const ValidHooks := {
	"PRE_DRY_RUN": "pre_dry_run",
	"POST_DRY_RUN": "post_dry_run",

	"PRE_UPDATE": "pre_update",
	"POST_UPDATE": "post_update",
	
	"PRE_PURGE": "pre_purge",
	"POST_PURGE": "post_purge"
}

#endregion

###############################################################################
# Builtin functions                                                           #
###############################################################################

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Private functions                                                           #
###############################################################################

## Reads all relevant config files
## Empty or missing configs are not considered errors
##
## @return: PackageResult<Tuple<Dictionary, Dictionary>> - A tuple-like structure containing the relevant files
static func _read_all_configs() -> PackageResult:
	var package_file := {}

	var res := read_config(PACKAGE_FILE)
	if res.is_ok():
		package_file = res.unwrap()

	var lock_file := {}
	
	res = read_config(LOCK_FILE)
	if res.is_ok():
		lock_file = res.unwrap()

	return PackageResult.ok([package_file, lock_file])

static func _save_string(string: String, path: String) -> PackageResult:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)
	
	file.store_string(string)
	file.close()
	return PackageResult.ok()

static func _save_data(data: PoolByteArray, path: String) -> PackageResult:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)

	file.store_buffer(data)

	file.close()
	
	return PackageResult.ok()

static func _read_file_to_string(path: String) -> PackageResult:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)
	
	var t := PackageResult.ok(file.get_as_text())
	return (t)

static func _is_valid_new_package(lock_file: Dictionary, npm_manifest: Dictionary) -> bool:
	if lock_file.get(LockFileKeys.VERSION, "") == npm_manifest.get(NpmManifestKeys.VERSION, "__MISSING__"):
		return false

	if lock_file.get(LockFileKeys.INTEGRITY, "") == npm_manifest.get(NpmManifestKeys.DIST, {}).get(NpmManifestKeys.INTEGRITY, "__MISSING__"):
		return false

	return true

static func _json_to_dict(json_string: String) -> PackageResult:
	var parse_result := JSON.parse(json_string)
	if parse_result.error != OK:
		return PackageResult.err(Error.Code.INVALID_JSON)
	
	if typeof(parse_result.result) != TYPE_DICTIONARY:
		return PackageResult.err(Error.Code.UNEXPECTED_JSON_FORMAT)

	return PackageResult.ok(parse_result.result)

# Converts a package.json to a godot.package format
#
# @result: Dictionary
static func _npm_to_godot(npm: Dictionary) -> Dictionary:
	var new_d := {PackageKeys.PACKAGES: {}}
	var npm_deps: Dictionary = npm.get(NpmPackageKeys.PACKAGES, {})
	for pkg in npm_deps.keys():
		new_d[PackageKeys.PACKAGES][pkg] = {}
		new_d[PackageKeys.PACKAGES][pkg][PackageKeys.VERSION] = npm_deps[pkg]
	return new_d

# flattens a dictionary and returns a array of the values
static func _flatten(d: Dictionary) -> Array:
	var a := []
	_flatten_inner(d, a)
	return a

static func _flatten_inner(d: Dictionary, a: Array):
	for v in d.values():
		if v is Dictionary:
			_flatten_inner(v, a)
			continue
		a.append(v)


#region REST

## Send a GET request to a given host/path
##
## @param: host: String - The host to connect to
## @param: path: String - The host path
##
## @return: PackageResult[PoolByteArray] - The response body
static func _send_get_request(host: String, path: String) -> PackageResult:
	var http := HTTPClient.new()

	var err := http.connect_to_host(host, 443, true)
	if err != OK:
		return PackageResult.err(Error.Code.CONNECT_TO_HOST_FAILURE, host)

	while http.get_status() in CONNECTING_STATUS:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackageResult.err(Error.Code.UNABLE_TO_CONNECT_TO_HOST, host)

	err = http.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
	if err != OK:
		return PackageResult.err(Error.Code.GET_REQUEST_FAILURE, path)

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if not http.get_status() in SUCCESS_STATUS:
		return PackageResult.err(Error.Code.UNSUCCESSFUL_REQUEST, path)

	if http.get_response_code() != 200:
		return PackageResult.err(Error.Code.UNEXPECTED_STATUS_CODE, "%s - %d" % [path, http.get_response_code()])

	var body := PoolByteArray()

	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()

		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			yield(Engine.get_main_loop(), "idle_frame")
		else:
			body.append_array(chunk)

	return PackageResult.ok(body)

static func _request_npm_manifest(package_name: String, package_version: String) -> PackageResult:
	var res = yield(_send_get_request(REGISTRY, "%s/%s" % [package_name, package_version]), "completed")
	if res.is_err():
		return res

	var body: String = res.unwrap().get_string_from_utf8()
	var parse_res := _json_to_dict(body)
	if parse_res.is_err():
		return parse_res
	# var parse_res := JSON.parse(body)
	# if parse_res.error != OK or not parse_res.result is Dictionary:
	# 	return PackageResult.err(Error.Code.UNEXPECTED_DATA, "%s - Unexpected json" % package_name)

	# var npm_manifest: Dictionary = parse_res.result
	var npm_manifest: Dictionary = parse_res.unwrap()

	if not npm_manifest.has("dist") and not npm_manifest["dist"].has("tarball"):
		return PackageResult.err(Error.Code.UNEXPECTED_DATA, "%s - NPM manifest missing required fields" % package_name)

	return PackageResult.ok(npm_manifest)

#endregion

#region Directory utils

## Recursively finds all files in a directory. Nested directories are represented by further dicts
##
## @param: original_path: String - The absolute, root path of the directory. Used to strip out the full path
## @param: path: String - The current, absoulute search path
##
## @return: Dictionary<Dictionary> - The files + directories in the current `path`
##
## @example: original_path: /my/path/to/
##	{
##		"nested": {
##			"hello.gd": "/my/path/to/nested/hello.gd"
##		},
##		"file.gd": "/my/path/to/file.gd"
###	}
static func _get_files_recursive_inner(original_path: String, path: String) -> Dictionary:
	var r := {}
	
	var dir := Directory.new()
	if dir.open(path) != OK:
		printerr("Failed to open directory path: %s" % path)
		return r
	
	dir.list_dir_begin(true, false)
	
	var file_name := dir.get_next()
	
	while file_name != "":
		var full_path := dir.get_current_dir().plus_file(file_name)
		if dir.current_is_dir():
			r[path.replace(original_path, "").plus_file(file_name)] = _get_files_recursive_inner(original_path, full_path)
		else:
			r[file_name] = full_path
		
		file_name = dir.get_next()
	
	return r

# returns toplevel directory entrys
#
# @result PackageResult<PoolStringArray>
static func _walk_dir(path: String, dir_only := false) -> PackageResult:
	var files: PoolStringArray = []
	var dir := Directory.new()
	var e := dir.open(path)
	if e: return PackageResult.err(10, "Directory open failed")
	dir.list_dir_begin(true, false)  # list the directory
	var file_name := dir.get_next()  # get the next file
	while file_name != "":
		if dir_only:
			if dir.current_is_dir():
				files.append(path.plus_file(file_name))  # add the folder
		else:
			files.append(path.plus_file(file_name.split(".",true, 1)[0]))  # add the file
		file_name = dir.get_next()  # get the next file
	return PackageResult.ok(files)
	

static func compile_regex(src: String) -> RegEx:
	var r := RegEx.new()
	r.compile(src)
	return r

## Wrapper for _get_files_recursive(..., ...) omitting the `original_path` arg.
##
## @param: path: String - The path to search
##
## @return: Dictionary<Dictionary> - A recursively `Dictionary` of all files found at `path`
static func _get_files_recursive(path: String) -> Dictionary:
	return _get_files_recursive_inner(path, path)

## Removes a directory recursively
##
## @param: path: String - The path to remove
## @param: delete_base_dir: bool - Whether to remove the root directory at path as well
## @param: file_dict: Dictionary - The result of `_get_files_recursive` if available
##
## @return: int - The error code
static func _remove_dir_recursive(path: String, delete_base_dir: bool = true, file_dict: Dictionary = {}) -> int:
	var files := _get_files_recursive(path) if file_dict.empty() else file_dict
	
	var dir := Directory.new()
	
	for key in files.keys():
		var file_path: String = path.plus_file(key)
		var val = files[key]
		
		if val is Dictionary:
			if _remove_dir_recursive(file_path, false) != OK:
				printerr("Unable to remove_dir_recursive")
				return ERR_BUG
		
		if dir.remove(file_path) != OK:
			printerr("Unable to remove file at path: %s" % file_path)
			return ERR_BUG
	
	if delete_base_dir and dir.remove(path) != OK:
		printerr("Unable to remove file at path: %s" % path)
		return ERR_BUG
	
	return OK

#endregion

#region Scripts

static func _clean_text(text: String) -> PackageResult:
	var whitespace_regex := RegEx.new()
	whitespace_regex.compile("\\B(\\s+)\\b")

	var r := PoolStringArray()

	var split: PoolStringArray = text.split("\n")
	if split.empty():
		return PackageResult.err(Error.Code.MISSING_SCRIPT)
	
	var first_line := ""
	for i in split:
		first_line = i
		if not first_line.strip_edges().empty():
			break

	# The first line should not have any tabs at all, so any tabs there can be assumed
	# to also be uniformly applied to the other lines
	# It's also possible spaces are used instead of tabs, so check for spaces as well
	var regex_match := whitespace_regex.search(first_line)
	if regex_match == null:
		return PackageResult.ok(split)

	var empty_prefix: String = regex_match.get_string()

	for i in split:
		# We can guarantee that the string will always be empty and, after the first iteration,
		# will always have a proper new line character
		r.append(i.trim_prefix(empty_prefix))

	return PackageResult.ok(r)

## Build a script from a `String`
##
## @param: text: String - The code to build and compile
##
## @return: PackageResult<AdvancedExpression> - The compiled script
static func _build_script(text: String) -> PackageResult:
	var ae := AdvancedExpression.new()

	var clean_res := _clean_text(text)
	if clean_res.is_err():
		return clean_res

	var split: PoolStringArray = clean_res.unwrap()

	ae.runner.add_param("gpm")

	for line in split:
		ae.add(line)

	if ae.compile() != OK:
		return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, "_build_script")

	return PackageResult.ok(ae)

## Parse all hooks. Failures cause the entire function to short-circuit
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: PackageResult<Hooks> - The result of the operation
static func _parse_hooks(data: Dictionary) -> PackageResult:
	var hooks := Hooks.new()

	var file_hooks: Dictionary = data.get(PackageKeys.HOOKS, {})

	for key in file_hooks.keys():
		if not key in ValidHooks.values():
			printerr("Unrecognized hook %s" % key)
			continue

		var val = file_hooks[key]
		match typeof(val):
			TYPE_ARRAY:
				var res = _build_script(PoolStringArray(val).join("\n"))
				if res.is_err():
					return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())
			TYPE_DICTIONARY:
				var type = val.get("type", "")
				var value = val.get("value", "")
				if type == "script":
					var res = _build_script(value)
					if res.is_err():
						return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				elif type == "script_name":
					if not data[PackageKeys.SCRIPTS].has(value):
						return PackageResult.err(Error.Code.MISSING_SCRIPT, key)
					
					var res = _build_script(data[PackageKeys.SCRIPTS][value])
					if res.is_err():
						return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				else:
					return PackageResult.err(Error.Code.BAD_SCRIPT_TYPE, value)
			_:
				var res = _build_script(val)
				if res.is_err():
					return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())

	return PackageResult.ok(hooks)

#endregion

###############################################################################
# Public functions                                                            #
###############################################################################

## Emulates `tar xzf <filename> --strip-components=1 -C <output_dir>`
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: PackageResult[] - The result of the operation
static func xzf(file_path: String, output_path: String) -> PackageResult:
	var output := []
	OS.execute(
		"tar",
		[
			"xzf",
			ProjectSettings.globalize_path(file_path),
			"--strip-components=1",
			"-C",
			ProjectSettings.globalize_path(output_path)
		],
		true,
		output
	)

	# `tar xzf` should not produce any output
	if not output.empty() and not output.front().empty():
		printerr(output)
		return PackageResult.err(Error.Code.GENERIC, "Tar failed")

	return PackageResult.ok()

#region Config handling

## Reads a config file
##
## @param: file_name: String - Either the PACKAGE_FILE or the LOCK_FILE
##
## @return: PackageResult<Dictionary> - The contents of the config file
static func read_config(file_name: String) -> PackageResult:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return PackageResult.err(Error.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.READ) != OK:
		return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, file_name)

	var parse_result := JSON.parse(file.get_as_text())
	if parse_result.error != OK:
		return PackageResult.err(Error.Code.PARSE_FAILURE, file_name)

	# Closing to save on memory I guess
	file.close()

	var data = parse_result.result
	if not data is Dictionary:
		return PackageResult.err(Error.Code.UNEXPECTED_DATA, file_name)

	if file_name == PACKAGE_FILE and data.get(PackageKeys.PACKAGES, {}).empty():
		return PackageResult.err(Error.Code.NO_PACKAGES, file_name)

	return PackageResult.ok(data)

## Writes a `Dictionary` to a specified file_name in the project root
##
## @param: file_name: String - Either the `PACKAGE_FILE` or the `LOCK_FILE`
##
## @result: PackageResult<()> - The result of the operation
static func write_config(file_name: String, data: Dictionary) -> PackageResult:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return PackageResult.err(Error.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.WRITE) != OK:
		return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, file_name)

	file.store_string(JSON.print(data, "\t"))

	file.close()

	return PackageResult.ok()

#endregion

func print(text: String) -> void:
	print(text)
	emit_signal("message_logged", text)

## Reads the config files and returns the operation that would have been taken for each package
##
## @return: PackageResult<Dictionary> - The actions that would have been taken or OK
func dry_run() -> PackageResult:
	var res := _read_all_configs()
	if not res:
		return PackageResult.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: Hooks = res.unwrap()
	var pre_dry_run_res = hooks.run(self, ValidHooks.PRE_DRY_RUN)
	if typeof(pre_dry_run_res) == TYPE_BOOL and pre_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_DRY_RUN)
		return PackageResult.ok({DryRunValues.OK: true})

	var dir := Directory.new()

	emit_signal("operation_started", "dry run", package_file[PackageKeys.PACKAGES].size())
	
	var failed_packages := FailedPackages.new()
	var packages_to_update := []
	for package_name in package_file.get(PackageKeys.PACKAGES, {}).keys():
		emit_signal("operation_checkpoint_reached", package_name)
		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()
		var package_version := ""

		var data = package_file[PackageKeys.PACKAGES][package_name]
		if data is Dictionary:
			package_version = data.get(PackageKeys.VERSION, "")
			if package_version.empty():
				failed_packages.add(package_name, res.unwrap_err().to_string())
				continue
			# TODO handle `required_when` and `optional_when` here
		else:
			package_version = data

		res = yield(_request_npm_manifest(package_name, package_version), "completed")
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
			continue

		var npm_manifest: Dictionary = res.unwrap()

		if dir.dir_exists(dir_name):
			if lock_file.has(package_name) and \
					not _is_valid_new_package(lock_file[package_name], npm_manifest):
				continue
			
			packages_to_update.append(package_name)
	
	emit_signal("operation_finished")

	var post_dry_run_res = hooks.run(self, ValidHooks.POST_DRY_RUN)
	if typeof(post_dry_run_res) == TYPE_BOOL and post_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_DRY_RUN)
		return PackageResult.ok({DryRunValues.OK: true})

	return PackageResult.ok({
		DryRunValues.OK: packages_to_update.empty() and failed_packages.failed_package_log.empty(),
		DryRunValues.UPDATE: packages_to_update,
		DryRunValues.INVALID: failed_packages.failed_package_log
	})

var script_load_r := compile_regex("(pre)?load\\(\\\"([^)]+)\\\"\\)")
func _modify_script_loads(t: String, cwd: String) -> PackageResult:
	var offset := 0
	var F := File.new()
	for m in script_load_r.search_all(t):
		# m.strings[(the entire match), (the pre part), (group1)]
		var f: String = m.strings[2]
		if F.file_exists(f) or F.file_exists(cwd.plus_file(f)):
			continue
		var is_preload = m.strings[1] == "pre"
		var res := _modify_load(f, is_preload, cwd, ("preload" if is_preload else "load") + "(\"%s\")")
		if res.is_err():
			return res
		var p: String = res.unwrap()
		var tmp := t.left(m.get_start() + offset) + p + t.right(m.get_end() + offset)
		offset += len(tmp) - len(t) # offset
		t = tmp
	return PackageResult.ok(t)

var scene_load_r := compile_regex('\\[ext_resource path="([^"]+)"')
func _modify_scene_loads(t: String, cwd: String) -> PackageResult:
	var offset := 0
	var F := File.new()
	for m in scene_load_r.search_all(t):
		var f: String = m.strings[1]
		print(f)
		if F.file_exists(f) or F.file_exists(cwd.plus_file(f)):
			continue
		var res := _modify_load(f, false, cwd, '[ext_resource path="%s"')
		if res.is_err():
			return res
		var p: String = res.unwrap()
		var tmp := t.left(m.get_start() + offset) + p + t.right(m.get_end() + offset)
		offset += len(tmp) - len(t) # offset
		t = tmp
	return PackageResult.ok(t)

func _modify_load(path: String, is_preload: bool, cwd: String, f_str: String) -> PackageResult:
	var F := File.new()
	if path.begins_with("res://addons"):
		path = path.replace("res://addons", "")
	var split := path.split("/")
	var wanted_addon := split[1]
	var wanted_file := PoolStringArray(Array(split).slice(2, len(split)-1)).join("/")
	var res := read_config(LOCK_FILE)
	if res.is_err():
		return res
	var cfg: Dictionary = res.unwrap()
	var noscope_cfg: Dictionary = {}
	for pkg in cfg.keys():
		noscope_cfg[pkg.get_file()] = cfg[pkg]
	if wanted_addon in noscope_cfg:
		return PackageResult.ok(f_str % noscope_cfg[wanted_addon][LockFileKeys.DIRECTORY].plus_file(wanted_file))
	return PackageResult.err(Error.Code.GENERIC, "Could not find path for %s" % path)

# scan for load and preload funcs and have their paths modified
# - preload will be modified to use a relative path, unless the path would need to use `../`, in which case we defer to absolution
# - load will be modified to use an absolute path (they are not preprocessored, must be absolute)
func modify_packages() -> PackageResult:
	var res := _walk_dir(ADDONS_DIR, true)
	if res.is_err():
		return res
	var packages: Array = res.unwrap()
	var F := File.new()
	for pkgpath in packages:
		var pkgname: String = pkgpath.replace("res://addons/", "")
		if pkgname == "godot-package-manager":
			continue
		else:
			for f in _flatten(_get_files_recursive(pkgpath)):
				if ResourceLoader.exists(f):
					var ext: String = f.split(".")[-1]
					var modify_func: FuncRef

					if ext in ["gd", "gdscript"]:
						modify_func = funcref(self, "_modify_script_loads")
					elif ext in ["tscn"]:
						modify_func = funcref(self, "_modify_scene_loads")
					else:
						continue
					res = _read_file_to_string(f)

					if res.is_err():
						return res
					var file_contents: String = res.unwrap()
					res = modify_func.call_func(file_contents, f.get_base_dir())

					if res.is_err():
						return res
					var new_file_contents: String = res.unwrap()
					if file_contents != new_file_contents:
						res = _save_string(new_file_contents, f)
						if res.is_err():
							return res
	return PackageResult.ok()

# Downloads a package, used by `update()`
#
# @result: GDScriptFunctionState
func download_package(package_name: String, download_dir: String, package_file: Dictionary, lock_file: Dictionary, force: bool, failed_packages: FailedPackages, is_indirect := false) -> void:
	emit_signal("operation_checkpoint_reached", package_name)
	yield(Engine.get_main_loop(), "idle_frame") # return a GDScriptFunctionState
	var package_version := ""

	var data = package_file[PackageKeys.PACKAGES][package_name]
	if data is Dictionary:
		package_version = data.get(PackageKeys.VERSION, "")
		if package_version.empty():
			failed_packages.add(package_name, "Package version empty")
			return
		
		for n in [PackageKeys.REQUIRED_WHEN, PackageKeys.OPTIONAL_WHEN]:
			if data.has(n):
				var body
				var body_data = data[n]
				if body_data is Dictionary:
					var type = body_data.get("type", "")
					var value = body_data.get("value", "")
					if type == "script":
						body = value
					elif type == "script_name":
						if not package_file[PackageKeys.SCRIPTS].has(value):
							failed_packages.add(package_name, "Script does not exist %s" % value)
							return

						body = package_file[PackageKeys.SCRIPTS][value]
					else:
						# Invalid type, assume the entire block is bad
						failed_packages.add(package_name, "Invalid type %s, bailing out" % type)
						return
				else:
					body = body_data
				var res = _build_script(body if body is String else PoolStringArray(body).join("\n"))
				if res.is_err():
					failed_packages.add(package_name, "Failed to parse section %s" % n)
					return
				
				var execute_value = res.unwrap().execute([self])
				if typeof(execute_value) == TYPE_BOOL:
					match n:
						PackageKeys.REQUIRED_WHEN:
							if execute_value == false:
								emit_signal("message_logged", "Skipping package %s because of %s condition" %
										[package_name, n])
								return
						PackageKeys.OPTIONAL_WHEN:
							if execute_value == true:
								emit_signal("message_logged", "Skipping package %s because of %s condition" %
										[package_name, n])
								return
	else:
		package_version = data
	var res = yield(_request_npm_manifest(package_name, package_version), "completed")
	if not res or res.is_err():
		failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
		return

	var npm_manifest: Dictionary = res.unwrap()
	
	# Check against lockfile and determine whether to continue or not
	# If the directory does not exist, there's no need to do addtional checks
	var dir := Directory.new()
	if dir.dir_exists(download_dir):
		if not force:
			if (
				lock_file.has(package_name) and
				not _is_valid_new_package(lock_file[package_name], npm_manifest)
				):
				emit_signal("message_logged", "%s does not need to be updated\nSkipping %s" %
						[package_name, package_name])
				return

		if _remove_dir_recursive(ProjectSettings.globalize_path(download_dir)) != OK:
			failed_packages.add(package_name, "Unable to remove old files")
			return


	#region Download tarball

	res = yield(_send_get_request(REGISTRY, npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].replace(REGISTRY, "")), "completed")
	if not res or res.is_err():
		failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
		return
	
	var download_location: String = ADDONS_DIR_FORMAT % npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].get_file()
	var downloaded_file: PoolByteArray = res.unwrap()
	res = _save_data(downloaded_file, download_location)
	if not res or res.is_err():
		failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
		return

	#endregion

	if not dir.dir_exists(download_dir) and dir.make_dir_recursive(download_dir) != OK:
		failed_packages.add(package_name, "Unable to create directory")
		return
	
	res = xzf(download_location, download_dir)
	if not res or res.is_err():
		failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
		return
	
	if dir.remove(download_location) != OK:
		failed_packages.add(package_name, "Failed to remove tarball")
		return

	lock_file[package_name] = {
		LockFileKeys.VERSION: package_version,
		LockFileKeys.INTEGRITY: npm_manifest["dist"]["integrity"],
		LockFileKeys.INDIRECT: is_indirect,
		LockFileKeys.DIRECTORY: download_dir,
	}


	# TODO read package.json file of downloaded package and download dependencies
	var file := File.new()
	var npm_package_file_location := "%s/%s" % [download_dir, NPM_PACKAGE_FILE]
	if not file.file_exists(npm_package_file_location):
		failed_packages.add(package_name, "No npm package manifest found, unable to read metadata")
		return

	if file.open(npm_package_file_location, File.READ) != OK:
		failed_packages.add(package_name, "Unable to open npm package manifest, unable to read metadata")
		return
	
	res = _json_to_dict(file.get_as_text())
	if not res or res.is_err():
		failed_packages.add(package_name, "Unable to read npm package manifest")
		return

	var package: Dictionary = _npm_to_godot(res.unwrap())
	for package_name in package.get(PackageKeys.PACKAGES, {}).keys():
		var down_dir := DEPENDENCIES_DIR_FORMAT % [package_name.get_file(), package[PackageKeys.PACKAGES][package_name][PackageKeys.VERSION]]
		yield(download_package(package_name, down_dir,  package, lock_file, force, failed_packages, true), "completed")



## Reads the `godot.package` file and updates all packages. A `godot.lock` file is also written afterwards.
##
## @result: PackageResult<()> - The result of the operation
func update(force: bool = false) -> PackageResult:
	var res := _read_all_configs()
	if not res:
		return PackageResult.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: Hooks = res.unwrap()
	var pre_update_res = hooks.run(self, ValidHooks.PRE_UPDATE)
	if typeof(pre_update_res) == TYPE_BOOL and pre_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_UPDATE)
		return PackageResult.ok()

	var dir := Directory.new()
	
	emit_signal("operation_started", "update", package_file[PackageKeys.PACKAGES].size())
	
	# Used for compiling together all errors that may occur
	var failed_packages := FailedPackages.new()
	for package_name in package_file.get(PackageKeys.PACKAGES, {}).keys():
		yield(download_package(package_name, ADDONS_DIR_FORMAT % package_name.get_file(), package_file, lock_file, force, failed_packages), "completed")
	
	res = modify_packages()
	if res.is_err():
		printerr(res)
	emit_signal("operation_finished")
	
	var post_update_res = hooks.run(self, ValidHooks.POST_UPDATE)
	if typeof(post_update_res) == TYPE_BOOL and post_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_UPDATE)
		return PackageResult.ok()
	
	if failed_packages.has_logs():
		return PackageResult.err(Error.Code.PROCESS_PACKAGES_FAILURE, failed_packages.get_logs())

	res = write_config(LOCK_FILE, lock_file)
	if not res or res.is_err():
		return res if res else PackageResult.err(Error.Code.GENERIC, "Unable to write configs")
	
	return PackageResult.ok()

## Remove all packages listed in `godot.lock`
##
## @return: PackageResult<()> - The result of the operation
func purge() -> PackageResult:
	var res := _read_all_configs()
	if not res:
		return PackageResult.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
	if res.is_err():
		return res

	var configs: Array = res.unwrap()

	var package_file: Dictionary = configs[0]
	var lock_file: Dictionary = configs[1]

	res = _parse_hooks(package_file)
	if res.is_err():
		return res

	var hooks: Hooks = res.unwrap()
	var pre_purge_res = hooks.run(self, ValidHooks.PRE_PURGE)
	if typeof(pre_purge_res) == TYPE_BOOL and pre_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_PURGE)
		return PackageResult.ok()

	var dir := Directory.new()

	emit_signal("operation_started", "purge", lock_file.size())

	var failed_packages := FailedPackages.new()
	var completed_package_count: int = 0
	for package_name in lock_file.keys():
		emit_signal("operation_checkpoint_reached", package_name)
		var dir_name: String = lock_file[package_name][LockFileKeys.DIRECTORY]

		if dir.dir_exists(dir_name):
			if _remove_dir_recursive(ProjectSettings.globalize_path(dir_name)) != OK:
				failed_packages.add(package_name, "Unable to remove directory")
				continue
	
	emit_signal("operation_finished")

	var post_purge_res = hooks.run(self, ValidHooks.POST_PURGE)
	if typeof(post_purge_res) == TYPE_BOOL and post_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_PURGE)
		return PackageResult.ok()
	
	var keys_to_erase := []
	for key in lock_file.keys():
		if not key in failed_packages.failed_packages:
			keys_to_erase.append(key)
	
	for key in keys_to_erase:
		lock_file.erase(key)
	
	res = write_config(LOCK_FILE, lock_file)
	if res.is_err():
		return res

	return PackageResult.ok() if not failed_packages.has_logs() else \
			PackageResult.err(Error.Code.REMOVE_PACKAGE_DIR_FAILURE, failed_packages.get_logs())
