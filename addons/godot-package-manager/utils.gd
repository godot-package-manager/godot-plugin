class_name GPMUtils

const DEFAULT_ERROR := "Default error"

static func OK(v = null):
	return GPMResult.new(v if v != null else OK)
		
static func ERR(error_code: int = 1, description: String = "") -> GPMResult:
	return GPMResult.new(GPMError.new(error_code, description))

## Emulates `tar xzf <filename> --strip-components=1 -C <output_dir>`
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func xzf(file_path: String, output_path: String) -> GPMResult:
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
		return ERR(GPMError.Code.GENERIC, "Tar failed")

	return OK()

## Wget url path
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func wget(file_path: String, output_path: String) -> GPMResult:
	print("wget: ", file_path, " || ", output_path)

	var _output := []

	OS.execute(
		"wget",
		[
			file_path,
			"-O",
			output_path.replace("res://", "")
		],
		true,
		_output
	)
	
	return OK()

## mv
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func mv(file_path: String, output_path: String) -> GPMResult:

	var _output := []

	OS.execute(
		"mv",
		[
			file_path,
			output_path
		],
		true,
		_output
	)
	
	return OK()

## rm
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func rm(file_path: String) -> GPMResult:

	var _output := []

	OS.execute(
		"rm",
		[
			"-rf",
			file_path
		],
		true,
		_output
	)
	
	return OK()

## Git clone 
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func clone(file_path: String, output_path: String) -> GPMResult:

	var _output := []

	OS.execute(
		"git",
		[
			"clone",
			"--depth", 
			"1",
			file_path,
			output_path
		],
		true,
		_output
	)
	print("Clone: ", file_path, " || ", output_path, " || ", _output)
	return OK()
	
## Get's hostname from url
##
## @param: url: String - The relative file path to a tar file
##
## @return: String - The result of the operation

static func hostname(url: String) -> String:
	var protocol = url.split("//")[0]
	var full_protocol = protocol + "//"

	var hostname = full_protocol+url.replace(full_protocol, "").split("/")[0]

	return hostname

## Get's path from url
##
## @param: url: String - The relative file path to a tar file
##
## @return: String - The result of the operation

static func path(url: String) -> String:
	return url.replace(hostname(url), "").split("/")[0]

	###############################################################################
	# Private functions                                                           #
	###############################################################################
	
	## Reads all relevant config files
	## Empty or missing configs are not considered errors
	##
	## @return: GPMResult<Tuple<Dictionary, Dictionary>> - A tuple-like structure containing the relevant files
	static func _read_all_configs() -> GPMResult:
		var package_file := {}
	
		var res := read_config(PACKAGE_FILE)
		if res.is_ok():
			package_file = res.unwrap()
	
		var lock_file := {}
		
		res = read_config(LOCK_FILE)
		if res.is_ok():
			lock_file = res.unwrap()
	
		return GPMUtils.OK([package_file, lock_file])
	
	static func _save_data(data: PoolByteArray, path: String) -> GPMResult:
		var file := File.new()
		if file.open(path, File.WRITE) != OK:
			return GPMUtils.ERR(GPMError.Code.FILE_OPEN_FAILURE, path)
	
		file.store_buffer(data)
	
		file.close()
		
		return GPMUtils.OK()
	
	static func _is_valid_new_package(lock_file: Dictionary, npm_manifest: Dictionary) -> bool:
		if lock_file.get(LockFileKeys.VERSION, "") == npm_manifest.get(NpmManifestKeys.VERSION, "__MISSING__"):
			return false
	
		if lock_file.get(LockFileKeys.INTEGRITY, "") == npm_manifest.get(NpmManifestKeys.DIST, {}).get(NpmManifestKeys.INTEGRITY, "__MISSING__"):
			return false
	
		return true


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