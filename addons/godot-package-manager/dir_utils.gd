extends RefCounted

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Recursively gets all files in a directory. Can take a long time if there are many nested files
## in the directory.
static func _get_files_recursive(original_path: String, current_path: String) -> Dictionary:
	var r := {}
	
	var dir := DirAccess.open(current_path)
	if dir == null:
		printerr("Failed to open directory at %s" % current_path)
		return r
	
	dir.list_dir_begin()
	
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := "%s/%s" % [dir.get_current_dir(), file_name]
		if dir.current_is_dir():
			var relative_path := "%s/%s" % [current_path.replace(original_path, ""), file_name]
			r[relative_path] = _get_files_recursive(original_path, current_path)
		else:
			r[file_name] = full_path
		
		file_name = dir.get_next()
	
	return r

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Wrapper around [code]_get_files_recursive[/code]. Needed since the recursive function
## is always initially passed the same path twice.
##
## @param path: String - The path to search.
##
## @return Dictionary<String, String | Dictionary> - Keys are relative paths, values are either
## file names or Dictionaries (indicating an inner directory).
static func get_files_recursive(path: String) -> Dictionary:
	return _get_files_recursive(path, path)

## Removes a directory recursively.
##
## @param path: String - The path to remove.
## @param remove_base_dir: bool - Whether to remove the directory at the given path.
## @param file_dict: Dictionary - The result of [code]get_files_recursive[/code], only useful
## when removing inner directories.
##
## @return int - The error code.
static func remove_dir_recursive(
	path: String,
	remove_base_dir: bool = true,
	file_dict: Dictionary = {}
) -> int:
	var files := get_files_recursive(path) if file_dict.is_empty() else file_dict
	
	for key in files.keys():
		var file_path := "%s/%s" % [path, key]
		var val = files[key]
		
		if val is Dictionary:
			if remove_dir_recursive(file_path, false, val) != OK:
				printerr("Unable to remove directories recursively for %s" % path)
				return ERR_BUG
		
		if OS.move_to_trash(file_path) != OK:
			printerr("Unable to remove file at path %s" % file_path)
			return ERR_BUG
	
	if remove_base_dir and OS.move_to_trash(path) != OK:
		printerr("Unable to remove base directory at path %s" % path)
		return ERR_BUG
	
	return OK
