extends RefCounted

var name := ""
var version := ""

var download_dir := ""

var is_installed := false
var is_indirect := false

## Array[Package]. Flattened dependency structure.
var dependencies := []

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

func _init(name: String, version: String, is_indirect: bool) -> void:
	self.name = name
	self.version = version
	self.is_indirect = is_indirect

func _to_string() -> String:
	return "[%s: %s@%s]" % ["Package" if not is_indirect else "Indirect", name, version]

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

static func _modify_load(
	cwd: String,
	resource_path: String,
	format_str: String
) -> String:
	var r := ""
	
	if FileAccess.file_exists(resource_path) or FileAccess.file_exists(cwd.path_join(resource_path)):
		if not resource_path.begins_with("."):
			pass
	
	return r

func _normalize_script_loads(regex: RegEx, cwd: String, file_contents: String) -> int:
	var offset: int = 0
	for m in regex.search_all(file_contents):
		# (the entire match), (the pre part), (group contents)
		# Raw access to index 1 is safe here
		var is_preload := m.strings[1] == "pre"
		var replacement := _modify_load(
			cwd, m.string[2], "preload(%s)" if m.strings[1] == "pre" else "load(%s)")
		if replacement.is_empty():
			return ERR_INVALID_DATA
	
	return OK

func _normalize_text_res_loads(regex: RegEx) -> void:
	pass

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

func normalize(gpm: RefCounted) -> int:
	if not is_installed:
		return ERR_DOES_NOT_EXIST
	
	var own_files: Array[String] = gpm.dict_utils.flatten(
		gpm.dir_utils.get_files_recursive(download_dir))
	
	for f in own_files:
		if not ResourceLoader.exists(f):
			continue
		
		var ext := f.split(".")[-1]
		
	
	return OK

## 
func unscoped_name() -> String:
	return name.get_file()
