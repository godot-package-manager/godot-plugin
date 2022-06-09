#GPM Filesystem
class_name GPMFs


static func save_data(data: PoolByteArray, path: String) -> GPMResult:
	var file := File.new()
	if file.open(path, File.WRITE):
		return GPMUtils.ERR(GPMError.Code.FILE_OPEN_FAILURE, path)

	file.store_buffer(data)

	file.close()
	
	return GPMUtils.OK()

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
static func get_files_recursive_inner(original_path: String, path: String) -> Dictionary:
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
            r[path.replace(original_path, "").plus_file(file_name)] = get_files_recursive_inner(original_path, full_path)
        else:
            r[file_name] = full_path
        
        file_name = dir.get_next()
    
    return r

## Wrapper for get_files_recursive(..., ...) omitting the `original_path` arg.
##
## @param: path: String - The path to search
##
## @return: Dictionary<Dictionary> - A recursively `Dictionary` of all files found at `path`
static func get_files_recursive(path: String) -> Dictionary:
    return get_files_recursive_inner(path, path)

## Removes a directory recursively
##
## @param: path: String - The path to remove
## @param: delete_base_dir: bool - Whether to remove the root directory at path as well
## @param: file_dict: Dictionary - The result of `get_files_recursive` if available
##
## @return: int - The error code
static func remove_dir_recursive(path: String, delete_base_dir: bool = true, file_dict: Dictionary = {}) -> int:
    var files := get_files_recursive(path) if file_dict.empty() else file_dict
    
    var dir := Directory.new()
    
    for key in files.keys():
        var file_path: String = path.plus_file(key)
        var val = files[key]
        
        if val is Dictionary:
            if remove_dir_recursive(file_path, false) != OK:
                printerr("Unable to remove_dir_recursive")
                return GPMUtils.ERR_BUG
        
        if dir.remove(file_path) != OK:
            printerr("Unable to remove file at path: %s" % file_path)
            return GPMUtils.ERR_BUG
    
    if delete_base_dir and dir.remove(path) != OK:
        printerr("Unable to remove file at path: %s" % path)
        return GPMUtils.ERR_BUG
    
    return OK

#endregion