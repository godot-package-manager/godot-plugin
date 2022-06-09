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
	# output_path = ProjectSettings.globalize_path(output_path)
	output_path = output_path.replace("res://", "")

	print("wget: ", file_path, " || ", output_path)

	var _output := []

	OS.execute(
		"wget",
		[
			file_path,
			"-O",
			output_path
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
	print("Moving %s %s" % [ProjectSettings.globalize_path(file_path), ProjectSettings.globalize_path(output_path)])
	var _output := []

	OS.execute(
		"mv",
		[
			ProjectSettings.globalize_path(file_path),
			ProjectSettings.globalize_path(output_path),
		],
		true,
		_output
	)
	print(_output)
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

## Mkdir
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: GPMResult[] - The result of the operation
static func mk(file_path: String) -> GPMResult:

	var _output := []

	OS.execute(
		"rm",
		[
			"-rf",
			ProjectSettings.globalize_path(file_path)
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
	return OK()