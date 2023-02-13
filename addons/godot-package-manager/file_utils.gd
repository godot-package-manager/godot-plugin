extends RefCounted

const RES_DIR := "res://"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

static func _fix_script(regex: RegEx, cwd: String, script_content: String) -> String:
	var offset: int = 0
	for m in regex.search_all(script_content):
		# m.strings[(the entire match), (the pre part), (group contents)]
		var matched_path: String = m.strings[2]
		
		# Addon's own resources
		if FileAccess.file_exists(matched_path) or FileAccess.file_exists(cwd.path_join(matched_path)):
			if not matched_path.begins_with("."):
				var rel_path := absolute_to_relative(matched_path, cwd)
				if matched_path.length() > rel_path.length():
					return ("preload(%s)" if m.strings[1].begins_with("pre") else "load(%s)") % [
						rel_path
					]
			return ""
		
		# Indirect resources
		matched_path = matched_path.trim_prefix("res://addons")
		var split := matched_path.split("/")
		if split.size() < 2:
			return ""
		
		var wanted_addon := split[1]
		var wanted_file := "/".join(split.slice(2))
		
		# TODO
	
	return ""

static func _fix_tres(regex: RegEx) -> void:
	pass

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Saves some text at a given path.
##
## @param path: String - The path to save the text at.
## @param text: String - The text to save.
##
## @return int - The error code.
static func save_string(path: String, text: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(text)
	
	return OK

## Saves some bytes at a given path.
##
## @param path: String - The path to save the bytes at.
## @param text: String - The bytes to save.
##
## @return int - The error code.
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
static func absolute_to_relative(path: String, cwd: String, remove_res: bool = true) -> String:
	var r := ""
	
	if remove_res:
		path = path.replace(RES_DIR, "")
		cwd = path.replace(RES_DIR, "")
	
	var floating_path := cwd
	
	while floating_path.replace(path, floating_path) == path:
		floating_path = floating_path.get_base_dir()
		
		r = "../%s" % r if not r.is_empty() else ".."
	
	if floating_path == "/":
		r += "/"
	
	floating_path = floating_path.replace(path, floating_path)
	if not floating_path.is_empty():
		if not r.is_empty():
			r += floating_path
		else:
			r = floating_path.substr(1)
	
	return r

static func fix_script_path(regex: RegEx, file_path: String) -> int:
	var base_dir := file_path.replace("", "")
	var offset: int = 0
	for m in regex.search_all(FileAccess.get_file_as_string(file_path)):
		# m.strings[(the entire match), (the pre part), (group content)]
		var matched_path: String = m.strings[2]
#		if FileAccess.file_exists(matched_path) or FileAccess.file

	# TODO
	
	return OK

static func fix_tres_path(regex: RegEx, file_path: String) -> int:
	var offset: int = 0
	for m in regex.search_all(FileAccess.get_file_as_string(file_path)):
		var matched_path: String = m.strings[1]
	
	# TODO
	
	return OK

## Emulates `tar xzf <file_path> --strip-components=1 -C <output_path>`.
##
## @param file_path: String - The res:// file path to a tar.gz file.
## @param output_path: String - The res:// path to extract to.
##
## @return int - The error code.
static func xzf(file_path: String, output_path: String) -> int:
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
