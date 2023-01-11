extends RefCounted

const RES_DIR := "res://"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

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

## Reads a file into a String.
##
## @param path: String - The path to read a file from.
##
## @return String - The contents of the file. Will be empty if reading failed.
static func read_file_to_string(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	
	return file.get_as_text()

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
