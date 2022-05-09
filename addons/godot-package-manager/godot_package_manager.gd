extends Reference

class Error:
	enum Code {
		NONE = 0,
		GENERIC,

		#region Http requests

		INITIATE_CONNECT_TO_HOST_FAILURE,
		UNABLE_TO_CONNECT_TO_HOST,

		UNSUCCESSFUL_REQUEST,
		MISSING_RESPONSE,
		UNEXPECTED_STATUS_CODE,

		GET_REQUEST_FAILURE,

		#endregion

		#region Config

		FILE_OPEN_FAILURE,
		PARSE_FAILURE,
		UNEXPECTED_DATA,

		NO_PACKAGES,
		PROCESS_PACKAGES_FAILURE

		#endregion

	}

	var _error: int
	var _description: String

	func _init(error: int, description: String = "") -> void:
		_error = error
		_description = description
	
	func _to_string() -> String:
		return "Code: %d\nName: %s\nDescription: %s" % [_error, error_name(), _description]

	func error_code() -> int:
		return _error

	func error_name() -> int:
		return Code.keys()[_error]

	func error_description() -> String:
		return _description

class Result:
	var _value
	var _error: Error

	func _init(v) -> void:
		if not v is Error:
			_value = v
		else:
			_error = v

	func _to_string() -> String:
		if is_err():
			return "ERR: %s" % str(_error)
		else:
			return "OK: %s" % str(_value)

	func is_ok() -> bool:
		return not is_err()

	func is_err() -> bool:
		return _error != null

	func unwrap():
		return _value

	func unwrap_err() -> Error:
		return _error

	func expect(text: String):
		if is_err():
			printerr(text)
			return null
		return _value

	func or_else(val):
		return _value if is_ok() else val

	static func ok(v = null) -> Result:
		var res = Result.new(OK)
		return Result.new(v if v != null else OK)

	static func err(error_code: int = 1, description: String = "") -> Result:
		return Result.new(Error.new(error_code, description))

signal update_started(num_packages)
signal update_checkpoint(checkpoint_num)
signal update_finshed()

const REGISTRY := "https://registry.npmjs.org"
const ADDONS_DIR_FORMAT := "res://addons/%s"

const CONNECTING_STATUS := [
	HTTPClient.STATUS_CONNECTING,
	HTTPClient.STATUS_RESOLVING
]
const SUCCESS_STATUS := [
	HTTPClient.STATUS_BODY,
	HTTPClient.STATUS_CONNECTED,
]

const HEADERS := [
	"User-Agent: GodotPackageManager/1.0 (you-win on GitHub)",
	"Accept: */*"
]

const PACKAGE_FILE := "godot.package"
const LOCK_FILE := "godot.lock"

###############################################################################
# Builtin functions                                                           #
###############################################################################

###############################################################################
# Connections                                                                 #
###############################################################################

###############################################################################
# Private functions                                                           #
###############################################################################

static func _save_data(data: PoolByteArray, path: String) -> Result:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		return Result.err(Error.Code.FILE_OPEN_FAILURE, path)

	file.store_buffer(data)

	file.close()
	
	return Result.ok()

###############################################################################
# Public functions                                                            #
###############################################################################

## Send a GET request to a given host/path
##
## @param: host: String - The host to connect to
## @param: path: String - The host path
##
## @return: Result[PoolByteArray] - The response body
static func send_get_request(host: String, path: String) -> Result:
	var http := HTTPClient.new()

	var err := http.connect_to_host(host, 443, true)
	if err != OK:
		return Result.err(Error.Code.CONNECT_TO_HOST_FAILURE, host)

	while http.get_status() in CONNECTING_STATUS:
		http.poll()
#		OS.delay_msec(100)
		yield(Engine.get_main_loop(), "idle_frame")

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return Result.err(Error.Code.UNABLE_TO_CONNECT_TO_HOST, host)

	err = http.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
	if err != OK:
		return Result.err(Error.Code.GET_REQUEST_FAILURE, path)

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
#		OS.delay_msec(100)
		yield(Engine.get_main_loop(), "idle_frame")

	if not http.get_status() in SUCCESS_STATUS:
		return Result.err(Error.Code.UNSUCCESSFUL_REQUEST, path)

	if http.get_response_code() != 200:
		return Result.err(Error.Code.UNEXPECTED_STATUS_CODE, "%s - %d" % [path, http.get_response_code()])

	var body := PoolByteArray()

	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()

		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
#			OS.delay_msec(500)
			yield(Engine.get_main_loop(), "idle_frame")
		else:
			body.append_array(chunk)

	return Result.ok(body)

## Emulates `tar xzf <filename> --strip-components=1 -C <output_dir>`
##
## @param: file_path: String - The relative file path to a tar file
## @param: output_path: String - The file path to extract to
##
## @return: Result[] - The result of the operation
static func xzf(file_path: String, output_path: String) -> Result:
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
		return Result.err(Error.Code.GENERIC, "Tar failed")

	return Result.ok()

## Reads a config file
##
## @param: file_name: String - Either the PACKAGE_FILE or the LOCK_FILE
##
## @return: Result[Dictionary] - The contents of the config file
static func read_config(file_name: String) -> Result:
	if not file_name in [PACKAGE_FILE, LOCK_FILE]:
		return Result.err(Error.Code.GENERIC, "Unrecognized file %s" % file_name)

	var file := File.new()
	if file.open(file_name, File.READ) != OK:
		return Result.err(Error.Code.FILE_OPEN_FAILURE, file_name)

	var parse_result := JSON.parse(file.get_as_text())
	if parse_result.error != OK:
		return Result.err(Error.Code.PARSE_FAILURE, file_name)

	# Closing to save on memory I guess
	file.close()

	var data = parse_result.result
	if not data is Dictionary:
		return Result.err(Error.Code.UNEXPECTED_DATA, file_name)

	if file_name == PACKAGE_FILE and data.get("packages", {}).empty():
		return Result.err(Error.Code.NO_PACKAGES, file_name)

	return Result.ok(data)

func update() -> Result:
	#region Read all configs

	var package_file := {}

	var res := read_config(PACKAGE_FILE)
	if res.is_ok():
		package_file = res.unwrap()

	var lock_file := {}

	res = read_config(LOCK_FILE)
	if res.is_ok():
		lock_file = res.unwrap()

	#endregion

	var dir := Directory.new()
	
	emit_signal("update_started", package_file["packages"].size())
	
	# Used for compiling together all errors that may occur
	var failed_packages := PoolStringArray()
	var completed_package_count: int = 0
	for package_name in package_file["packages"]:
		var package_version := ""

		var data = package_file["packages"][package_name]
		if data is Dictionary:
			package_version = data.get("version", "")
			if package_version.empty():
				failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
				continue
			# TODO handle `required_when` and `optional_when` here
		else:
			package_version = data

		res = yield(send_get_request(REGISTRY, "%s/%s" % [package_name, package_version]), "completed")
		if res.is_err():
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue

		var body: String = res.unwrap().get_string_from_utf8()
		var parse_res := JSON.parse(body)
		if parse_res.error != OK or not parse_res.result is Dictionary:
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue

		var get_resp: Dictionary = parse_res.result

		if not get_resp.has("dist") and not get_resp["dist"].has("tarball"):
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue

		res = yield(send_get_request(REGISTRY, get_resp["dist"]["tarball"].replace(REGISTRY, "")), "completed")
		if res.is_err():
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue

		var download_location: String = ADDONS_DIR_FORMAT % get_resp["dist"]["tarball"].get_file()
		var downloaded_file: PoolByteArray = res.unwrap()
		res = _save_data(downloaded_file, download_location)
		if res.is_err():
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue

		var dir_name: String = ADDONS_DIR_FORMAT % package_name.get_file()
		if not dir.dir_exists(dir_name):
			if dir.make_dir_recursive(dir_name) != OK:
				failed_packages.append("%s - Unable to create directory" % package_name)
				continue
		
		res = xzf(download_location, dir_name)
		if res.is_err():
			failed_packages.append("%s - %s" % [package_name, res.unwrap_err().to_string()])
			continue
		
		if dir.remove(download_location) != OK:
			failed_packages.append("%s - Failed to remove tarball" % package_name)
			continue
		
		completed_package_count += 1
		emit_signal("update_checkpoint", completed_package_count)
	
	emit_signal("update_finshed")
	
	if not failed_packages.empty():
		failed_packages.invert()
		return Result.err(Error.Code.PROCESS_PACKAGES_FAILURE, failed_packages.join("\n"))

	return Result.ok()
