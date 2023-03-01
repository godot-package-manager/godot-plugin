extends RefCounted

## File utilities for Godot Package Manager.

const Package := preload("res://addons/godot-package-manager/model/package.gd")

#const RES_DIR := "res://"
# TODO move this into a constant file?
const DEPENDENCIES_DIR := "res://addons/__gpm_deps/"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#static func _fix_script(regex: RegEx, cwd: String, script_content: String) -> String:
#	var offset: int = 0
#	for m in regex.search_all(script_content):
#		# m.strings[(the entire match), (the pre part), (group contents)]
#		var matched_path: String = m.strings[2]
#
#		# Addon's own resources
#		if FileAccess.file_exists(matched_path) or FileAccess.file_exists(cwd.path_join(matched_path)):
#			if not matched_path.begins_with("."):
#				var rel_path := absolute_to_relative(matched_path, cwd)
#				if matched_path.length() > rel_path.length():
#					return ("preload(%s)" if m.strings[1].begins_with("pre") else "load(%s)") % [
#						rel_path
#					]
#			return ""
#
#		# Indirect resources
#		matched_path = matched_path.trim_prefix("res://addons")
#		var split := matched_path.split("/")
#		if split.size() < 2:
#			return ""
#
#		var wanted_addon := split[1]
#		var wanted_file := "/".join(split.slice(2))
#
#		# TODO
#
#	return ""
#
#static func _fix_tres(regex: RegEx) -> void:
#	pass

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Saves some text at a given path. [br]
##
## Params: [br]
## [param path]: [String] - The path to save the text at. [br]
## [param text]: [String] - The text to save. [br]
##
## [param int] - The error code.
static func save_string(path: String, text: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(text)
	
	return OK

## Saves some bytes at a given path. [br]
##
## Params: [br]
## [param path]: [String] - The path to save the bytes at. [br]
## [param text]: [String] - The bytes to save. [br]
##
## Returns: [br]
## [param int] - The error code.
static func save_bytes(path: String, bytes: PackedByteArray) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_buffer(bytes)
	
	return OK

# TODO (Tim Yuen) I'm actually not really able to follow the Godot 3 implementation
# check if this actually works
## Convert an absoulte path to a relative path.
##
## @param path: String - The absolute path to convert.
## @param cwd: String - The current working directory.
## @param remove_res: bool - Whether to strip Godot's resource directory.
##
## @param String - The convert path.
#static func absolute_to_relative(path: String, cwd: String, remove_res: bool = true) -> String:
#	var r := ""
#
#	if remove_res:
#		path = path.replace(RES_DIR, "")
#		cwd = path.replace(RES_DIR, "")
#
#	var floating_path := cwd
#
#	while floating_path.replace(path, floating_path) == path:
#		floating_path = floating_path.get_base_dir()
#
#		r = "../%s" % r if not r.is_empty() else ".."
#
#	if floating_path == "/":
#		r += "/"
#
#	floating_path = floating_path.replace(path, floating_path)
#	if not floating_path.is_empty():
#		if not r.is_empty():
#			r += floating_path
#		else:
#			r = floating_path.substr(1)
#
#	return r

static func fix_script_path(
	regex: RegEx,
	file_path: String,
	deps: Array[Package]
) -> int:
	var file := FileAccess.open(file_path, FileAccess.WRITE_READ)
	if file == null:
		printerr("Unable to open file at %s" % file_path)
		return ERR_FILE_CANT_OPEN
	
	var file_content := file.get_as_text()
	
	# Read file contents without modifying anything in the source file
	var replacements := {}
	for m in regex.search_all(file_content):
		# m.strings[(the entire match), (the pre part), (group content)]
		var matched_path: String = m.strings[2]
		# Already the correct absolute path
		if FileAccess.file_exists(matched_path):
			return OK
		
		var split := matched_path.trim_prefix("res://").lstrip("./").split("/", false, 1)
		if split.size() != 2:
			printerr("Failed to split script path: %s" % str(split))
			return ERR_DOES_NOT_EXIST
		
		var addon_name := split[0]
		var uri := split[1]
		
		var filtered_deps := deps.filter(func(package: Package) -> bool:
			return package.name == addon_name
		)
		if filtered_deps.size() != 1:
			printerr("Failed to find matching package %s for file %s" % [addon_name, file_path])
			return ERR_DOES_NOT_EXIST
		
		var dep: Package = filtered_deps.front()
		
		var new_path := "%s/%s/%s/%s" % [
			DEPENDENCIES_DIR, addon_name, dep.version, uri
		]
		
		replacements[matched_path] = new_path
	
	# Actually start modifying source
	for key in replacements.keys():
		var val: String = replacements[key]
		
		file_content.replace(key, val)
	
	file.store_string(file_content)
	
	file.close()
	
	return OK

static func fix_tres_path(regex: RegEx, file_path: String) -> int:
	var offset: int = 0
	for m in regex.search_all(FileAccess.get_file_as_string(file_path)):
		var matched_path: String = m.strings[1]
	
	# TODO
	
	return OK

## Emulates `tar xzf <file_path> --strip-components=1 -C <output_path>`. [br]
##
## Params: [br]
## [param file_path]: [String] - The res:// file path to a tar.gz file. [br]
## [param output_path]: [String] - The res:// path to extract to. [br]
##
## [param int] - The error code.
static func xzf_native(file_path: String, output_path: String) -> int:
	
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
		output
	)
	
	if exit_code != 0:
		return ERR_BUG
	
	return OK

# TODO broken
## Decompress a `.tar.gz` file. [br]
## [url]https://github.com/godotengine/godot-proposals/issues/6089#issuecomment-1417950525[/url]
## [br]
##
## [param file_path]: [String] - The path to the `.tar.gz` file. [br]
## [param output_path]: [String] - The path where the files should be extracted to. [br]
##
## Returns: [br]
## [param int] - The error code.
static func xzf(file_path: String, output_path: String, size: int = 0) -> int:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	
	var buffer := file.get_buffer(file.get_length())
	file.close()
	
	buffer = buffer.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP) if size < 1 else \
		buffer.decompress(size, FileAccess.COMPRESSION_GZIP)
	if buffer.size() < 1:
		return ERR_INVALID_DATA
	
	var octal_number_get := func(data: PackedByteArray) -> int:
		var r: int = 0
		
		for i in data.size():
			if data[i] == 0:
				return r
			if data[i] < 48 or data[i] > 55:
				return -1
			
			r *= 8
			r += data[i] - 48
		
		return 0
	
	var trim_null := func(data: PackedByteArray) -> PackedByteArray:
		var end := data.size()
		while end > 0 and data[end - 1] == 0:
			end -= 1
		
		return data.slice(0, end)
	
	var check_all_zeros := func(data: PackedByteArray) -> bool:
		for i in data.size():
			if data[i] != 0:
				return false
		return true
	
	var entries: Array[Dictionary] = []
	
	var offset: int = 0
	while offset + 512 < buffer.size():
		var file_size: int = octal_number_get.call(buffer.slice(offset + 124))
		if file_size < 0 or offset + 512 + file_size > buffer.size():
			break
		if file_size == 0:
			# Check for two empty records marking the end of the archive
			# This is a relatively expensive operation for GDScript but will generally happen
			# only once in the whole archive
			if check_all_zeros.call(buffer.slice(offset, offset + 512)):
				if (
					offset + 1024 > buffer.size() or
					not check_all_zeros.call(buffer.slice(offset + 512, offset + 1024))
				):
					offset += 512
					continue
				break
		
		entries.push_back({
			"name": trim_null.call(buffer.slice(offset, offset + 100)).get_string_from_utf8(),
			"contents": buffer.slice(offset + 512, offset + 512 + file_size)
		})
		
		offset += 512 + file_size + (511 - ((file_size + 511) & 0x1FF))
	
	print(JSON.stringify(entries, "\t"))
	
	return OK
