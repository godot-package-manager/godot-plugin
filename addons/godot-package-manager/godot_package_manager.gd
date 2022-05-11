extends Reference

#region Error handling

const DEFAULT_ERROR := "Default error"
class Error:
	enum Code {
		NONE = 0,
		GENERIC,

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
const ADDONS_DIR_FORMAT := "res://addons/%s"

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
	"INTEGRITY": "integrity"
}

const NpmManifestKeys := {
	"VERSION": "version",
	"DIST": "dist",
	"INTEGRITY": "integrity",
	"TARBALL": "tarball"
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
## @return: Result<Tuple<Dictionary, Dictionary>> - A tuple-like structure containing the relevant files
static func _read_all_configs() -> Result:
	var package_file := {}

	var res := read_config(PACKAGE_FILE)
	if res.is_ok():
		package_file = res.unwrap()

	var lock_file := {}
	
	res = read_config(LOCK_FILE)
	if res.is_ok():
		lock_file = res.unwrap()

	return Result.ok([package_file, lock_file])

static func _save_data(data: PoolByteArray, path: String) -> Result:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		return Result.err(Error.Code.FILE_OPEN_FAILURE, path)

	file.store_buffer(data)

	file.close()
	
	return Result.ok()

static func _is_valid_new_package(lock_file: Dictionary, npm_manifest: Dictionary) -> bool:
	if lock_file.get(LockFileKeys.VERSION, "") == npm_manifest.get(NpmManifestKeys.VERSION, "__MISSING__"):
		return false

	if lock_file.get(LockFileKeys.INTEGRITY, "") == npm_manifest.get(NpmManifestKeys.DIST, {}).get(NpmManifestKeys.INTEGRITY, "__MISSING__"):
		return false

	return true

#region REST

## Send a GET request to a given host/path
##
## @param: host: String - The host to connect to
## @param: path: String - The host path
##
## @return: Result[PoolByteArray] - The response body
static func _send_get_request(host: String, path: String) -> Result:
	var http := HTTPClient.new()

	var err := http.connect_to_host(host, 443, true)
	if err != OK:
		return Result.err(Error.Code.CONNECT_TO_HOST_FAILURE, host)

	while http.get_status() in CONNECTING_STATUS:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return Result.err(Error.Code.UNABLE_TO_CONNECT_TO_HOST, host)

	err = http.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
	if err != OK:
		return Result.err(Error.Code.GET_REQUEST_FAILURE, path)

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if not http.get_status() in SUCCESS_STATUS:
		return Result.err(Error.Code.UNSUCCESSFUL_REQUEST, path)

	if http.get_response_code() != 200:
		return Result.err(Error.Code.UNEXPECTED_STATUS_CODE, "%s - %d" % [path, http.get_response_code()])

	var body := PoolByteArray()

	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()

		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			yield(Engine.get_main_loop(), "idle_frame")
		else:
			body.append_array(chunk)

	return Result.ok(body)

static func _request_npm_manifest(package_name: String, package_version: String) -> Result:
	var res = yield(_send_get_request(REGISTRY, "%s/%s" % [package_name, package_version]), "completed")
	if res.is_err():
		return res

	var body: String = res.unwrap().get_string_from_utf8()
	var parse_res := JSON.parse(body)
	if parse_res.error != OK or not parse_res.result is Dictionary:
		return Result.err(Error.Code.UNEXPECTED_DATA, "%s - Unexpected json" % package_name)

	var npm_manifest: Dictionary = parse_res.result

	if not npm_manifest.has("dist") and not npm_manifest["dist"].has("tarball"):
		return Result.err(Error.Code.UNEXPECTED_DATA, "%s - NPM manifest missing required fields" % package_name)

	return Result.ok(npm_manifest)

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

static func _clean_text(text: String) -> Result:
	var whitespace_regex := RegEx.new()
	whitespace_regex.compile("\\B(\\s+)\\b")

	var r := PoolStringArray()

	var split: PoolStringArray = text.split("\n")
	if split.empty():
		return Result.err(Error.Code.MISSING_SCRIPT)
	
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
		return Result.ok(split)

	var empty_prefix: String = regex_match.get_string()

	for i in split:
		# We can guarantee that the string will always be empty and, after the first iteration,
		# will always have a proper new line character
		r.append(i.trim_prefix(empty_prefix))

	return Result.ok(r)

## Build a script from a `String`
##
## @param: text: String - The code to build and compile
##
## @return: Result<AdvancedExpression> - The compiled script
static func _build_script(text: String) -> Result:
	var ae := AdvancedExpression.new()

	var clean_res := _clean_text(text)
	if clean_res.is_err():
		return clean_res

	var split: PoolStringArray = clean_res.unwrap()

	ae.runner.add_param("gpm")

	for line in split:
		ae.add(line)

	if ae.compile() != OK:
		return Result.err(Error.Code.SCRIPT_COMPILE_FAILURE, "_build_script")

	return Result.ok(ae)

## Parse all hooks. Failures cause the entire function to short-circuit
##
## @param: data: Dictionary - The entire package dictionary
##
## @return: Result<Hooks> - The result of the operation
static func _parse_hooks(data: Dictionary) -> Result:
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
					return Result.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())
			TYPE_DICTIONARY:
				var type = val.get("type", "")
				var value = val.get("value", "")
				if type == "script":
					var res = _build_script(value)
					if res.is_err():
						return Result.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				elif type == "script_name":
					if not data[PackageKeys.SCRIPTS].has(value):
						return Result.err(Error.Code.MISSING_SCRIPT, key)
					
					var res = _build_script(data[PackageKeys.SCRIPTS][value])
					if res.is_err():
						return Result.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				else:
					return Result.err(Error.Code.BAD_SCRIPT_TYPE, value)
			_:
				var res = _build_script(val)
				if res.is_err():
					return Result.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
				hooks.add(key, res.unwrap())

	return Result.ok(hooks)

#endregion

###############################################################################
# Public functions                                                            #
###############################################################################

## Emulates `tar xzf <filename> --strip-components=1 -C <output_dir>`
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: Result[] - The result of the operation
static func xzf(file_path: String, output_path: String) -> Result:
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
		return Result.err(Error.Code.GENERIC, "Tar failed")

	return Result.ok()

#region Config handling

## Reads a config file
##
## @param: file_name: String - Either the PACKAGE_FILE or the LOCK_FILE
##
## @return: Result<Dictionary> - The contents of the config file
static func read_config(file_name: String) -> Result:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return Result.err(Error.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.READ) != OK:
		return Result.err(Error.Code.FILE_OPEN_FAILURE, file_name)

	var parse_result := JSON.parse(file.get_as_text())
	if parse_result.error != OK:
		return Result.err(Error.Code.PARSE_FAILURE, file_name)

	# Closing to save on memory I guess
	file.close()

	var data = parse_result.result
	if not data is Dictionary:
		return Result.err(Error.Code.UNEXPECTED_DATA, file_name)

	if file_name == PACKAGE_FILE and data.get(PackageKeys.PACKAGES, {}).empty():
		return Result.err(Error.Code.NO_PACKAGES, file_name)

	return Result.ok(data)

## Writes a `Dictionary` to a specified file_name in the project root
##
## @param: file_name: String - Either the `PACKAGE_FILE` or the `LOCK_FILE`
##
## @result: Result<()> - The result of the operation
static func write_config(file_name: String, data: Dictionary) -> Result:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return Result.err(Error.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.WRITE) != OK:
		return Result.err(Error.Code.FILE_OPEN_FAILURE, file_name)

	file.store_string(JSON.print(data, "\t"))

	file.close()

	return Result.ok()

#endregion

func print(text: String) -> void:
	print(text)
	emit_signal("message_logged", text)

## Reads the config files and returns the operation that would have been taken for each package
##
## @return: Result<Dictionary> - The actions that would have been taken or OK
func dry_run() -> Result:
	var res := _read_all_configs()
	if not res:
		return Result.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
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
		return Result.ok({DryRunValues.OK: true})

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
		return Result.ok({DryRunValues.OK: true})

	return Result.ok({
		DryRunValues.OK: packages_to_update.empty() and failed_packages.failed_package_log.empty(),
		DryRunValues.UPDATE: packages_to_update,
		DryRunValues.INVALID: failed_packages.failed_package_log
	})

## Reads the `godot.package` file and updates all packages. A `godot.lock` file is also written afterwards.
##
## @result: Result<()> - The result of the operation
func update(force: bool = false) -> Result:
	var res := _read_all_configs()
	if not res:
		return Result.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
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
		return Result.ok()

	var dir := Directory.new()
	
	emit_signal("operation_started", "update", package_file[PackageKeys.PACKAGES].size())
	
	# Used for compiling together all errors that may occur
	var failed_packages := FailedPackages.new()
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
			
			# Keep track of whether we should skip to the next item
			# Used to break out of inner for-loop and continue to next item
			# in outer for-loop
			var should_skip := false
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
								should_skip = true
								break

							body = package_file[PackageKeys.SCRIPTS][value]
						else:
							# Invalid type, assume the entire block is bad
							failed_packages.add(package_name, "Invalid type %s, bailing out" % type)
							should_skip = true
							break
					else:
						body = body_data
					res = _build_script(body if body is String else PoolStringArray(body).join("\n"))
					if res.is_err():
						failed_packages.add(package_name, "Failed to parse section %s" % n)
						should_skip = true
						break
					
					var execute_value = res.unwrap().execute([self])
					if typeof(execute_value) == TYPE_BOOL:
						match n:
							PackageKeys.REQUIRED_WHEN:
								if execute_value == false:
									emit_signal("message_logged", "Skipping package %s because of %s condition" %
											[package_name, n])
									should_skip = true
							PackageKeys.OPTIONAL_WHEN:
								if execute_value == true:
									emit_signal("message_logged", "Skipping package %s because of %s condition" %
											[package_name, n])
									should_skip = true

					if should_skip:
						break
			if should_skip:
				continue
		else:
			package_version = data

		res = yield(_request_npm_manifest(package_name, package_version), "completed")
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
			continue

		var npm_manifest: Dictionary = res.unwrap()

		# Check against lockfile and determine whether to continue or not
		# If the directory does not exist, there's no need to do addtional checks
		if dir.dir_exists(dir_name):
			if not force:
				if lock_file.has(package_name) and \
						not _is_valid_new_package(lock_file[package_name], npm_manifest):
					emit_signal("message_logged", "%s does not need to be updated\nSkipping %s" %
							[package_name, package_name])
					continue

			if _remove_dir_recursive(ProjectSettings.globalize_path(dir_name)) != OK:
				failed_packages.add(package_name, "Unable to remove old files")
				continue

		#region Download tarball

		res = yield(_send_get_request(REGISTRY, npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].replace(REGISTRY, "")), "completed")
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
			continue

		var download_location: String = ADDONS_DIR_FORMAT % npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].get_file()
		var downloaded_file: PoolByteArray = res.unwrap()
		res = _save_data(downloaded_file, download_location)
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
			continue

		#endregion

		if not dir.dir_exists(dir_name):
			if dir.make_dir_recursive(dir_name) != OK:
				failed_packages.add(package_name, "Unable to create directory")
				continue
		
		res = xzf(download_location, dir_name)
		if not res or res.is_err():
			failed_packages.add(package_name, res.unwrap_err().to_string() if res else DEFAULT_ERROR)
			continue
		
		if dir.remove(download_location) != OK:
			failed_packages.add(package_name, "Failed to remove tarball")
			continue

		lock_file[package_name] = {
			LockFileKeys.VERSION: package_version,
			LockFileKeys.INTEGRITY: npm_manifest["dist"]["integrity"]
		}
	
	emit_signal("operation_finished")
	
	var post_update_res = hooks.run(self, ValidHooks.POST_UPDATE)
	if typeof(post_update_res) == TYPE_BOOL and post_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_UPDATE)
		return Result.ok()
	
	if failed_packages.has_logs():
		return Result.err(Error.Code.PROCESS_PACKAGES_FAILURE, failed_packages.get_logs())

	res = write_config(LOCK_FILE, lock_file)
	if not res or res.is_err():
		return res if res else Result.err(Error.Code.GENERIC, "Unable to write configs")

	return Result.ok()

## Remove all packages listed in `godot.lock`
##
## @return: Result<()> - The result of the operation
func purge() -> Result:
	var res := _read_all_configs()
	if not res:
		return Result.err(Error.Code.GENERIC, "Unable to read configs, bailing out")
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
		return Result.ok()

	var dir := Directory.new()

	emit_signal("operation_started", "purge", lock_file.size())

	var failed_packages := FailedPackages.new()
	var completed_package_count: int = 0
	for package_name in lock_file.keys():
		emit_signal("operation_checkpoint_reached", package_name)
		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()

		if dir.dir_exists(dir_name):
			if _remove_dir_recursive(ProjectSettings.globalize_path(dir_name)) != OK:
				failed_packages.add(package_name, "Unable to remove directory")
				continue
	
	emit_signal("operation_finished")

	var post_purge_res = hooks.run(self, ValidHooks.POST_PURGE)
	if typeof(post_purge_res) == TYPE_BOOL and post_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_PURGE)
		return Result.ok()
	
	var keys_to_erase := []
	for key in lock_file.keys():
		if not key in failed_packages.failed_packages:
			keys_to_erase.append(key)
	
	for key in keys_to_erase:
		lock_file.erase(key)
	
	res = write_config(LOCK_FILE, lock_file)
	if res.is_err():
		return res

	return Result.ok() if not failed_packages.has_logs() else \
			Result.err(Error.Code.REMOVE_PACKAGE_DIR_FAILURE, failed_packages.get_logs())
