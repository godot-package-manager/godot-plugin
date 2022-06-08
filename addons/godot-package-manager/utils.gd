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
