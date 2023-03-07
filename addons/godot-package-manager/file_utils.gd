extends RefCounted

## File utilities for Godot Package Manager.

const Package := GodotPackageManager.Model.Package

#const RES_DIR := "res://"
# TODO move this into a constant file?
const DEPENDENCIES_DIR := "res://addons/__gpm_deps/"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

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

## Calculate the hex-encoded, sha1sum for a given file. [br]
##
## Params: [br]
## [param path]: [String] - The path to the file to calculate the sha1sum for. [br]
##
## Returns: [br]
## [param String] - The hex-encoded, sha1sum for the file. Will be an empty string if the file
## does not exist.
static func sha1sum_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	
	return sha1sum_bytes(file.get_buffer(file.get_length()))

## Calculate the hex-encoded, sha1sum for the given bytes. [br]
##
## Params: [br]
## [param bytes]: [PackedByteArray] - The bytes to calculate the sha1sum for. [br]
##
## Returns: [br]
## [param String] - The hex-encoded, sha1sum for the file. Will be an empty string if the file
## does not exist.
static func sha1sum_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(bytes)
	
	return ctx.finish().hex_encode()

# TODO removed typed array since that was causing type errors (even though the type is correct)
## Fix absolute/relative paths in direct dependencies to point towards the indirect depedency
## directory. Works for both [GDScript] files and [PackedScene]s. [br]
##
## Params: [br]
## [param regex]: [RegEx] - The regex to use. [br]
## [param file_path]: [String] - The path to the file to modify. [br]
## [param deps]: [Array] - The dependencies of the [param file_path]. [br]
##
## Returns: [br]
## [param int] - The error code.
static func fix_path(
	regex: RegEx,
	file_path: String,
	deps: Array
) -> int:
	var file := FileAccess.open(file_path, FileAccess.READ_WRITE)
	if file == null:
		printerr("Unable to open file at %s" % file_path)
		return ERR_FILE_CANT_OPEN
	
	var file_content := file.get_as_text()
	
	# Read file contents without modifying anything in the source file
	var replacements := {}
	for m in regex.search_all(file_content):
		# m.strings[(the entire match), (group content)]
		var matched_path: String = m.strings[1]
		# Already the correct absolute path
		if FileAccess.file_exists(matched_path):
			return OK
		
		var split := matched_path.trim_prefix("res://addons").lstrip("./").split("/", false, 1)
		if split.size() != 2:
			printerr("Failed to split script path: %s" % str(split))
			return ERR_DOES_NOT_EXIST
		
		var addon_name := split[0]
		var uri := split[1]
		
		var filtered_deps := deps.filter(func(package: GodotPackageManager.Model.Package) -> bool:
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
		
		file_content = file_content.replace(key, val)
	
	file.store_string(file_content)
	
	file.close()
	
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
