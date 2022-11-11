extends Reference

#region NPM utils

class NPMUtils:
	# Converts a package.json to a godot.package format
	#
	# @result: Dictionary
	static func npm_to_godot(npm: Dictionary) -> Dictionary:
		var new_d := {PackageKeys.PACKAGES: {}}
		var npm_deps: Dictionary = npm.get(NpmPackageKeys.PACKAGES, {})
		for pkg in npm_deps.keys():
			new_d[PackageKeys.PACKAGES][pkg] = npm_deps[pkg]
		return new_d

	static func get_package_file(package_name: String, ver: String) -> PackageResult:
		var res: PackageResult = yield(
			NetUtils.send_get_request("https://cdn.jsdelivr.net", "npm/%s@%s/package.json" % [package_name, ver]),
			"completed"
		)
		if res.is_err():
			return res
		res = Utils.json_to_dict(res.unwrap().get_string_from_utf8())
		if res.is_err():
			return res
		return PackageResult.ok(res.unwrap())

	static func get_package_file_godot(package_name: String, ver: String) -> PackageResult:
		var res: PackageResult = yield(get_package_file(package_name, ver), "completed")
		if res.is_err():
			return res
		return PackageResult.ok(npm_to_godot(res.unwrap()))


#endregion


#region misc utils
class Utils:
	# flattens a dictionary and returns a array of the values
	static func flatten(d: Dictionary) -> Array:
		var a := []
		_flatten_inner(d, a)
		return a


	static func _flatten_inner(d: Dictionary, a: Array) -> void:
		for v in d.values():
			if v is Dictionary:
				_flatten_inner(v, a)
				continue
			a.append(v)
	
	static func compile_regex(src: String) -> RegEx:
		var r := RegEx.new()
		r.compile(src)
		return r

	static func remove_start(string: String, remove: String) -> String:
		if string.begins_with(remove):
			return string.substr(len(remove))
		return string

	static func json_to_dict(json_string: String) -> PackageResult:
		var parse_result := JSON.parse(json_string)
		if parse_result.error != OK:
			return PackageResult.err(Error.Code.INVALID_JSON)

		if typeof(parse_result.result) != TYPE_DICTIONARY:
			return PackageResult.err(Error.Code.UNEXPECTED_JSON_FORMAT)

		return PackageResult.ok(parse_result.result)

	static func insert(t: String, insertion: String, begin: int, end: int) -> String:
		return t.left(begin) + insertion + t.right(end)

#endregion

#region Network utils

class NetUtils:
	## Send a GET request to a given host/path
	##
	## @param: host: String - The host to connect to
	## @param: path: String - The host path
	##
	## @return: PackageResult[PoolByteArray] - The response body
	static func send_get_request(host: String, path: String) -> PackageResult:
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


#endregion

#region Directory utils


class DirUtils:
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
				r[path.replace(original_path, "").plus_file(file_name)] = _get_files_recursive_inner(
					original_path, full_path
				)
			else:
				r[file_name] = full_path

			file_name = dir.get_next()

		return r

	## Wrapper for _get_files_recursive(..., ...) omitting the `original_path` arg.
	##
	## @param: path: String - The path to search
	##
	## @return: Dictionary<Dictionary> - A recursively `Dictionary` of all files found at `path`
	static func get_files_recursive(path: String) -> Dictionary:
		return _get_files_recursive_inner(path, path)

	## Removes a directory recursively
	##
	## @param: path: String - The path to remove
	## @param: delete_base_dir: bool - Whether to remove the root directory at path as well
	## @param: file_dict: Dictionary - The result of `_get_files_recursive` if available
	##
	## @return: int - The error code
	static func remove_dir_recursive(path: String, delete_base_dir: bool = true, file_dict: Dictionary = {}) -> int:
		var files := DirUtils.get_files_recursive(path) if file_dict.empty() else file_dict

		for key in files.keys():
			var file_path: String = path.plus_file(key)
			var val = files[key]

			if val is Dictionary:
				if DirUtils.remove_dir_recursive(file_path, false) != OK:
					printerr("Unable to remove_dir_recursive")
					return ERR_BUG

			if OS.move_to_trash(ProjectSettings.globalize_path(file_path)) != OK:
				printerr("Unable to remove file at path: %s" % file_path)
				return ERR_BUG

		if delete_base_dir and OS.move_to_trash(ProjectSettings.globalize_path(path)) != OK:
			printerr("Unable to remove file at path: %s" % path)
			return ERR_BUG

		return OK


#endregion

#region File utils


class FileUtils:
	static func save_string(string: String, path: String) -> PackageResult:
		var file := File.new()
		if file.open(path, File.WRITE) != OK:
			return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)

		file.store_string(string)
		file.close()
		return PackageResult.ok()

	static func save_data(data: PoolByteArray, path: String) -> PackageResult:
		var file := File.new()
		if file.open(path, File.WRITE) != OK:
			return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)

		file.store_buffer(data)

		file.close()

		return PackageResult.ok()

	static func read_file_to_string(path: String) -> PackageResult:
		var file := File.new()
		if file.open(path, File.READ) != OK:
			return PackageResult.err(Error.Code.FILE_OPEN_FAILURE, path)

		var t := PackageResult.ok(file.get_as_text())
		return t

	static func absolute_to_relative(path: String, cwd: String, remove_res := true) -> String:
		if remove_res:
			path = Utils.remove_start(path, "res://")
			cwd = Utils.remove_start(cwd, "res://")
		var common := cwd
		var result := ""
		while Utils.remove_start(path, common) == path:
			common = common.get_base_dir()

			if !result:
				result = ".."
			else:
				result = "../" + result

		if common == "/":
			result += "/"

		var uncommon := Utils.remove_start(path, common)
		if result and uncommon:
			result += uncommon
		elif uncommon:
			result = uncommon.substr(1)
		return result
	
	## Emulates `tar xzf <filename> --strip-components=1 -C <output_dir>`
	##
	## @param: file_path: String - The relative file path to a tar file
	## @param: output_path: String - The file path to extract to
	##
	## @return: PackageResult[] - The result of the operation
	static func xzf(file_path: String, output_path: String) -> PackageResult:
		var output := []
		var exit_code := OS.execute(
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
		if exit_code != 0:
			printerr(output)
			return PackageResult.err(Error.Code.GENERIC, "Tar failed (%s)" % exit_code)

		return PackageResult.ok()


#endregion

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

		UNZIP_FAILURE,

		#endregion

		#region Config

		FILE_OPEN_FAILURE,
		PARSE_FAILURE,
		UNEXPECTED_DATA,

		NO_PACKAGES,
		PROCESS_PACKAGES_FAILURE

		REMOVE_PACKAGE_DIR_FAILURE
		CREATE_PACKAGE_DIR_FAILURE

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
	var failed_package_log := []  # Log of failed packages and reasons
	var failed_packages := []  # Array of failed package names only

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
	var _hooks := {}  # Hook name: String -> AdvancedExpression

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


#region Package classes & cfg handling
class Package:
	var unscoped_name: String setget , _get_unscoped_name
	var name: String = ""
	var download_dir: String = "" setget , _get_download_dir
	var integrity: String = ""
	var version: String = ""
	var installed: bool = false setget , _get_is_installed
	var indirect: bool = false
	var dependencies := PackageList.new()

	var required_when: AdvancedExpression = null
	var optional_when: AdvancedExpression = null

	var npm_manifest: Dictionary

	var gpm: Object = null

	func _get_unscoped_name() -> String:
		return name.get_file()

	func _get_download_dir() -> String:
		return (
			(DEPENDENCIES_DIR_FORMAT % [self.unscoped_name, version])
			if indirect
			else (ADDONS_DIR_FORMAT % self.unscoped_name)
		)

	func _get_is_installed() -> bool:
		return Directory.new().dir_exists(self.download_dir)

	func _init(name: String, version: String, gpm: Object, indirect: bool = false) -> void:
		self.name = name
		self.version = version
		self.gpm = gpm
		self.indirect = indirect

	func _to_string() -> String:
		return "[Package:%s@%s]" % [name, version]

	#region utils (lowlevel stuff)

	func get_manifest() -> PackageResult:
		npm_manifest = {}
		var res: PackageResult = yield(NetUtils.send_get_request(REGISTRY, "%s/%s" % [name, version]), "completed")
		if res.is_err():
			return res

		var body: String = res.unwrap().get_string_from_utf8()
		var parse_res := Utils.json_to_dict(body)
		if parse_res.is_err():
			return parse_res

		var tmp_manifest: Dictionary = parse_res.unwrap()

		if not NpmManifestKeys.DIST in tmp_manifest or not tmp_manifest[NpmManifestKeys.DIST].has(NpmManifestKeys.TARBALL):
			return PackageResult.err(Error.Code.UNEXPECTED_DATA, "%s - NPM manifest missing required fields" % name)

		npm_manifest = tmp_manifest
		integrity = npm_manifest["dist"]["integrity"]
		return PackageResult.ok(npm_manifest)

	func get_tarball(download_location: String) -> PackageResult:
		var res: PackageResult = yield(
			NetUtils.send_get_request(
				REGISTRY, npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].replace(REGISTRY, "")
			),
			"completed"
		)
		if not res or res.is_err():
			return res

		var downloaded_file: PoolByteArray = res.unwrap()
		res = FileUtils.save_data(downloaded_file, download_location)
		if not res or res.is_err():
			return res
		return PackageResult.ok()


	func _modify_script_loads(t: String, cwd: String) -> PackageResult:
		var script_load_r := Utils.compile_regex('(pre)?load\\(\\"([^)]+)\\"\\)')
		var offset := 0
		for m in script_load_r.search_all(t):
			# m.strings[(the entire match), (the pre part), (group1)]
			var is_preload = m.strings[1] == "pre"
			var res := _modify_load(m.strings[2], is_preload, cwd, ("preload" if is_preload else "load") + '("%s")')
			if res.is_err():
				return res
			var p: String = res.unwrap()
			if p.empty(): continue
			var t_l := len(t)
			t = Utils.insert(t, p, m.get_start() + offset, m.get_end() + offset)
			offset += len(t) - t_l
		return PackageResult.ok(t)


	func _modify_text_resource_loads(t: String, cwd: String) -> PackageResult:
		var scene_load_r := Utils.compile_regex('\\[ext_resource path="([^"]+)"')
		var offset := 0
		for m in scene_load_r.search_all(t):
			var res := _modify_load(m.strings[1], false, cwd, '[ext_resource path="%s"')
			if res.is_err():
				return res
			var p: String = res.unwrap()
			if p.empty(): continue
			var t_l := len(t)
			t = Utils.insert(t, p, m.get_start() + offset, m.get_end() + offset)
			offset += len(t) - t_l
		return PackageResult.ok(t)


	func _modify_load(path: String, is_preload: bool, cwd: String, f_str: String) -> PackageResult:
		var F := File.new()
		if F.file_exists(path) or F.file_exists(cwd.plus_file(path)):
			var is_rel := path.begins_with(".")
			if not is_rel:
				var rel := FileUtils.absolute_to_relative(path, cwd)
				if len(path) > len(rel):
					return PackageResult.ok(f_str % rel)
			return PackageResult.ok("")
		path = Utils.remove_start(path, "res://addons")
		var split := path.split("/")
		var wanted_addon := split[1]
		var wanted_file := PoolStringArray(Array(split).slice(2, len(split) - 1)).join("/")
		var noscope_cfg: Dictionary = {}
		for pkg in dependencies:
			noscope_cfg[pkg.unscoped_name] = pkg.download_dir
		if wanted_addon in noscope_cfg:
			var wanted_f: String = noscope_cfg[wanted_addon].plus_file(wanted_file)
			if is_preload:
				var rel := FileUtils.absolute_to_relative(wanted_f, cwd)
				if len(wanted_f) > len(rel):
					PackageResult.ok(f_str % rel)
			return PackageResult.ok(f_str % wanted_f)
		return PackageResult.err(Error.Code.GENERIC, "Could not find path for %s" % path)

	#endregion

	# scan for load and preload funcs and have their paths modified
	# - preload will be modified to use a relative path, if the relative path is shorter than the absolute path.s
	# - load will be modified to use an absolute path (they are not preprocessored, must be absolute)
	func modify() -> PackageResult:
		if not self.installed:
			return PackageResult.err(Error.Code.GENERIC, "Not installed")

		for f in Utils.flatten(DirUtils.get_files_recursive(self.download_dir)):
			if ResourceLoader.exists(f):
				var ext: String = f.split(".")[-1]
				var modify_func: FuncRef

				if ext in ["gd", "gdscript"]:
					modify_func = funcref(self, "_modify_script_loads")
				elif ext in ["tscn", "tres"]:
					modify_func = funcref(self, "_modify_text_resource_loads")
				else:
					continue
				var res := FileUtils.read_file_to_string(f)

				if res.is_err():
					return res
				var file_contents: String = res.unwrap()
				res = modify_func.call_func(file_contents, f.get_base_dir())

				if res.is_err():
					return res
				var new_file_contents: String = res.unwrap()
				if file_contents != new_file_contents:
					res = FileUtils.save_string(new_file_contents, f)
					if res.is_err():
						return res
		return PackageResult.ok()

	func should_download() -> bool:
		if required_when || optional_when:
			for n in [[required_when, 0], [optional_when, 1]]:
				var execute_value = n[0].execute([gpm])
				if typeof(execute_value) == TYPE_BOOL:
					match n[1]:
						0: # reqwhen
							return execute_value != false
						1: # optwhen
							return execute_value != true
		return true

	func download() -> PackageResult:
		gpm.emit_signal("operation_checkpoint_reached", name)
		yield(Engine.get_main_loop(), "idle_frame")  # return a GDScriptFunctionState
		if not should_download():
			gpm.emit_signal("message_logged", "Skipping package %s because of condition" % name)
			return PackageResult.ok()

		var dir := Directory.new()
		if dir.dir_exists(self.download_dir):
			if DirUtils.remove_dir_recursive(self.download_dir) != OK:
				return PackageResult.err(Error.Code.REMOVE_PACKAGE_DIR_FAILURE)

		var download_location: String = (
			ADDONS_DIR_FORMAT
			% npm_manifest[NpmManifestKeys.DIST][NpmManifestKeys.TARBALL].get_file()
		)
		var res: PackageResult = yield(get_tarball(download_location), "completed")
		if res.is_err():
			return res

		if not dir.dir_exists(self.download_dir) and dir.make_dir_recursive(self.download_dir) != OK:
			return PackageResult.err(Error.Code.CREATE_PACKAGE_DIR_FAILURE)
		res = FileUtils.xzf(download_location, self.download_dir)
		if not res or res.is_err():
			return PackageResult.err(Error.Code.UNZIP_FAILURE)

		if dir.remove(download_location) != OK:
			return PackageResult.err(Error.Code.FILE_OPEN_FAILURE)
		return modify()
	
	func depend(on: Package) -> void:
		dependencies.append(on)


class PackageList:
	var _packages := []
	var _iter_current: int

	func add(package: Package) -> PackageList:
		_packages.append(package)
		return self
	
	func append(package: Package) -> void:
		_packages.append(package)

	func _should_continue() -> bool:
		return len(_packages) > _iter_current

	func _iter_init(arg) -> bool:
		_iter_current = 0
		return _should_continue()

	func _iter_next(arg) -> bool:
		_iter_current += 1
		return _should_continue()

	func _iter_get(arg) -> Package:
		return _packages[_iter_current]

	func size() -> int:
		return _packages.size()
	
	func _to_string() -> String:
		return "PackageList" + str(_packages)


class WantedPackages:
	extends PackageList
	var hooks: Hooks = null
	var gpm: Object = null

	func _init(gpm: Object) -> void:
		self.gpm = gpm

	func _add(p: Package, cfg: Dictionary) -> PackageResult:
		append(p)
		#region scripts
		if p.indirect == false:
			var data = cfg[PackageKeys.PACKAGES][p.name]
			if typeof(data) == TYPE_DICTIONARY:
				for n in [PackageKeys.REQUIRED_WHEN, PackageKeys.OPTIONAL_WHEN]:
					if data.has(n):
						var res: PackageResult = ScriptUtils.dict_to_script(data[n], cfg)
						if res.is_err():
							return res
						match n:
							PackageKeys.REQUIRED_WHEN:
								p.required_when = res.unwrap()
							PackageKeys.OPTIONAL_WHEN:
								p.optional_when = res.unwrap()
		#endregion
		var res: PackageResult = yield(p.get_manifest(), "completed")
		if res.is_err():
			return res
		#region dependency sniffing
		res = yield(NPMUtils.get_package_file_godot(p.name, p.version), "completed")
		if res.is_err():
			return res
		var package_file: Dictionary = res.unwrap()
		for package_name in package_file.get(PackageKeys.PACKAGES, {}).keys():
			var dep := Package.new(package_name, package_file[PackageKeys.PACKAGES][package_name], gpm, true)
			p.depend(dep)
			res = yield(_add(dep, {}), "completed")
			if res.is_err():
				return res
		#endregion
		return PackageResult.ok()

	# @result GDScriptFunctionState<PackageResult<null>>
	func update() -> PackageResult:
		var res: PackageResult = read_config(PACKAGE_FILE)
		if res.is_err():
			return res

		_packages.clear()
		var file := File.new()
		var cfg = res.unwrap()
		for pkg in cfg.get(PackageKeys.PACKAGES, {}).keys():
			var v: String = (
				cfg[PackageKeys.PACKAGES][pkg][PackageKeys.VERSION]
				if typeof(cfg[PackageKeys.PACKAGES][pkg]) == TYPE_DICTIONARY
				else cfg[PackageKeys.PACKAGES][pkg]
			)

			res = yield(_add(Package.new(pkg, v, gpm), cfg), "completed")
			if res.is_err():
				return res

		res = ScriptUtils.parse_hooks(cfg)
		if res.is_err():
			return res

		hooks = res.unwrap()

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

		var res = FileUtils.read_file_to_string(file_name)
		if res.is_err():
			return res

		res = Utils.json_to_dict(res.unwrap())
		if res.is_err():
			return res

		var data: Dictionary = res.unwrap()

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

	func run_hook(hook: String):
		return hooks.run(gpm, hook)

	func lock() -> PackageResult:
		var lock_file := {}
		for pkg in self:
			if pkg.installed:
				lock_file[pkg.name] = {
					LockFileKeys.VERSION: pkg.version,
					LockFileKeys.INTEGRITY: pkg.integrity,
				}
		var res = write_config(LOCK_FILE, lock_file)
		if not res or res.is_err():
			return res if res else PackageResult.err(Error.Code.GENERIC, "Unable to write configs")
		return PackageResult.ok()


#endregion

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


class ScriptUtils:
	static func _clean_text(text: String) -> PackageResult:
		var whitespace_regex := Utils.compile_regex("\\B(\\s+)\\b")

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
	static func build_script(text: String) -> PackageResult:
		var ae := AdvancedExpression.new()

		var clean_res := _clean_text(text)
		if clean_res.is_err():
			return clean_res

		var split: PoolStringArray = clean_res.unwrap()

		ae.runner.add_param("gpm")

		for line in split:
			ae.add(line)

		if ae.compile() != OK:
			return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, "build_script")

		return PackageResult.ok(ae)

	## Parse all hooks. Failures cause the entire function to short-circuit
	##
	## @param: data: Dictionary - The entire package dictionary
	##
	## @return: PackageResult<Hooks> - The result of the operation
	static func parse_hooks(data: Dictionary) -> PackageResult:
		var hooks := Hooks.new()

		var file_hooks: Dictionary = data.get(PackageKeys.HOOKS, {})

		for key in file_hooks.keys():
			if not key in ValidHooks.values():
				printerr("Unrecognized hook %s" % key)
				continue

			var val = file_hooks[key]
			match typeof(val):
				TYPE_ARRAY:
					var res = build_script(PoolStringArray(val).join("\n"))
					if res.is_err():
						return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())
				TYPE_DICTIONARY:
					var type = val.get("type", "")
					var value = val.get("value", "")
					if type == "script":
						var res = build_script(value)
						if res.is_err():
							return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
						hooks.add(key, res.unwrap())
					elif type == "script_name":
						if not data[PackageKeys.SCRIPTS].has(value):
							return PackageResult.err(Error.Code.MISSING_SCRIPT, key)

						var res = build_script(data[PackageKeys.SCRIPTS][value])
						if res.is_err():
							return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
						hooks.add(key, res.unwrap())
					else:
						return PackageResult.err(Error.Code.BAD_SCRIPT_TYPE, value)
				_:
					var res = build_script(val)
					if res.is_err():
						return PackageResult.err(Error.Code.SCRIPT_COMPILE_FAILURE, key)
					hooks.add(key, res.unwrap())

		return PackageResult.ok(hooks)

	# parse the optional_when script, or required_when
	#
	# @result PackageResult<AdvancedExpression>
	static func dict_to_script(body_data, package_file: Dictionary) -> PackageResult:
		var body
		if body_data is Dictionary:
			var type = body_data.get("type", "")
			var value = body_data.get("value", "")
			if type == "script":
				body = value
			elif type == "script_name":
				if not package_file[PackageKeys.SCRIPTS].has(value):
					return PackageResult.err(Error.Code.PARSE_FAILURE, "Script does not exist %s" % value)

				body = package_file[PackageKeys.SCRIPTS][value]
			else:
				# Invalid type, assume the entire block is bad
				return PackageResult.err(Error.Code.PARSE_FAILURE, "Invalid type %s, bailing out" % type)
		else:
			body = body_data
		var res = build_script(body if body is String else PoolStringArray(body).join("\n"))
		if res.is_err():
			return res
		var code: AdvancedExpression = res.unwrap()
		return PackageResult.ok(code)


#endregion

## A message that may be logged at any point during runtime
signal message_logged(text)

## Signifies the start of a package operation
signal operation_started(op_name, num_packages)
## Emitted when a package has started processing
signal operation_checkpoint_reached(package_name)
## Emitted when the package operation is complete
signal operation_finished

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

const CONNECTING_STATUS := [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]
const SUCCESS_STATUS := [
	HTTPClient.STATUS_BODY,
	HTTPClient.STATUS_CONNECTED,
]

const HEADERS := ["User-Agent: GodotPackageManager/1.0 (you-win on GitHub)", "Accept: */*"]

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
}

const NPM_PACKAGE_FILE := "package.json"
const NpmManifestKeys := {"VERSION": "version", "DIST": "dist", "INTEGRITY": "integrity", "TARBALL": "tarball"}
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

var pkg_configs := WantedPackages.new(self)
#endregion

###############################################################################
# Builtin functions                                                           #
###############################################################################

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Public functions                                                            #
###############################################################################


func print(text: String) -> void:
	print(text)
	emit_signal("message_logged", text)


## Reads the `godot.package` file and updates all packages. A `godot.lock` file is also written afterwards.
##
## @result: PackageResult<()> - The result of the operation
func update() -> PackageResult:
	var res: PackageResult = yield(pkg_configs.update(), "completed")
	if res.is_err():
		return res

	var pre_update_res = pkg_configs.run_hook(ValidHooks.PRE_UPDATE)
	if typeof(pre_update_res) == TYPE_BOOL and pre_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_UPDATE)
		return PackageResult.ok()

	var dir := Directory.new()

	emit_signal("operation_started", "update", pkg_configs.size())

	# Used for compiling together all errors that may occur
	var failed_packages := FailedPackages.new()
	for pkg in pkg_configs:
		res = yield(pkg.download(), "completed")
		if res.is_err():
			failed_packages.add(pkg.name, str(res))
	
	res = pkg_configs.lock()
	if res.is_err():
		return res

	emit_signal("operation_finished")

	var post_update_res = pkg_configs.run_hook(ValidHooks.POST_UPDATE)
	if typeof(post_update_res) == TYPE_BOOL and post_update_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_UPDATE)
		return PackageResult.ok()

	if failed_packages.has_logs():
		return PackageResult.err(Error.Code.PROCESS_PACKAGES_FAILURE, failed_packages.get_logs())

	return PackageResult.ok()


func dry_run() -> PackageResult:
	var res: PackageResult = yield(pkg_configs.update(), "completed")
	if res.is_err():
		return res
	
	var pre_dry_run_res = pkg_configs.run_hook(ValidHooks.PRE_DRY_RUN)
	if typeof(pre_dry_run_res) == TYPE_BOOL and pre_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_DRY_RUN)
		return PackageResult.ok({DryRunValues.OK: true})

	emit_signal("operation_started", "dry run", pkg_configs.size())
	var failed_packages := FailedPackages.new()
	var packages_to_update := []
	for package in pkg_configs:
		emit_signal("operation_checkpoint_reached", package.name)
		if not package.should_download():
			continue
		packages_to_update.append(package.name)
	
	emit_signal("operation_finished")

	var post_dry_run_res = pkg_configs.run_hook(ValidHooks.POST_DRY_RUN)
	if typeof(post_dry_run_res) == TYPE_BOOL and post_dry_run_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_DRY_RUN)
		return PackageResult.ok({DryRunValues.OK: true})

	return PackageResult.ok({
		DryRunValues.OK: packages_to_update.empty() and failed_packages.failed_package_log.empty(),
		DryRunValues.UPDATE: packages_to_update,
		DryRunValues.INVALID: failed_packages.failed_package_log
	})

## Remove all packages listed in `godot.lock`
##
## @return: PackageResult<()> - The result of the operation
func purge() -> PackageResult:
	var res: PackageResult = yield(pkg_configs.update(), "completed")
	if res.is_err():
		return res
	var pre_purge_res = pkg_configs.run_hook(ValidHooks.PRE_PURGE)
	if typeof(pre_purge_res) == TYPE_BOOL and pre_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.PRE_PURGE)
		return PackageResult.ok()

	var dir := Directory.new()

	var installed_pkgs := []
	for p in pkg_configs:
		if p.installed:
			installed_pkgs.append(p)
	emit_signal("operation_started", "purge", installed_pkgs.size())

	var failed_packages := FailedPackages.new()
	var completed_package_count: int = 0
	for pkg in installed_pkgs:
		emit_signal("operation_checkpoint_reached", pkg.name)
		if dir.dir_exists(pkg.download_dir):
			if DirUtils.remove_dir_recursive(pkg.download_dir) != OK:
				failed_packages.add(pkg.name, "Unable to remove directory")
				continue

	emit_signal("operation_finished")

	var post_purge_res = pkg_configs.run_hook(ValidHooks.POST_PURGE)
	if typeof(post_purge_res) == TYPE_BOOL and post_purge_res == false:
		emit_signal("message_logged", "Hook %s returned false" % ValidHooks.POST_PURGE)
		return PackageResult.ok()

	return (
		PackageResult.ok()
		if not failed_packages.has_logs()
		else PackageResult.err(Error.Code.REMOVE_PACKAGE_DIR_FAILURE, failed_packages.get_logs())
	)
