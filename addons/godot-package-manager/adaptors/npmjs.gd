class_name GPMNpmJs

const REGISTRY := "https://registry.npmjs.org"

const NpmManifestKeys := {
	"VERSION": "version",
	"DIST": "dist",
	"INTEGRITY": "integrity",
	"TARBALL": "tarball"
}


#region REST

## Send a GET request to a given host/path
##
## @param: host: String - The host to connect to
## @param: path: String - The host path
##
## @return: GPMResult[PoolByteArray] - The response body
static func _send_get_request(host: String, path: String) -> GPMResult:
	var http := HTTPClient.new()

	var err := http.connect_to_host(host, 443, true)
	if err != OK:
		return GPMUtils.ERR(GPMError.Code.CONNECT_TO_HOST_FAILURE, host)

	while http.get_status() in CONNECTING_STATUS:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return GPMUtils.ERR(GPMError.Code.UNABLE_TO_CONNECT_TO_HOST, host)

	err = http.request(HTTPClient.METHOD_GET, "/%s" % path, HEADERS)
	if err != OK:
		return GPMUtils.ERR(GPMError.Code.GET_REQUEST_FAILURE, path)

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		yield(Engine.get_main_loop(), "idle_frame")

	if not http.get_status() in SUCCESS_STATUS:
		return GPMUtils.ERR(GPMError.Code.UNSUCCESSFUL_REQUEST, path)
	
	if http.get_response_code() == 302:
		var location = http.get_response_headers_as_dictionary()["Location"]
		var host_loc = "https://" + location.replace("https://", "").split("/")[0]
		var path_loc = location.replace(host_loc, "")
		print("Loc: ", location, " || ", host_loc, " || ", path_loc)
		
		return yield(_send_get_request("https://"+host_loc, path_loc), "completed")
	

	if http.get_response_code() != 200:
		return GPMUtils.ERR(GPMError.Code.UNEXPECTED_STATUS_CODE, "%s - %d" % [path, http.get_response_code()])

	var body := PoolByteArray()

	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()

		var chunk := http.read_response_body_chunk()
		if chunk.size() == 0:
			yield(Engine.get_main_loop(), "idle_frame")
		else:
			body.append_array(chunk)

	return GPMUtils.OK(body)

static func _request_npm_manifest(package_name: String, package_version: String) -> GPMResult:
	var res = yield(_send_get_request(REGISTRY, "%s/%s" % [package_name, package_version]), "completed")
	if res.is_err():
		return res

	var body: String = res.unwrap().get_string_from_utf8()
	var parse_res := JSON.parse(body)
	if parse_res.error != OK or not parse_res.result is Dictionary:
		return GPMUtils.ERR(GPMError.Code.UNEXPECTED_DATA, "%s - Unexpected json" % package_name)

	var npm_manifest: Dictionary = parse_res.result

	if not npm_manifest.has("dist"):
		return GPMUtils.ERR(GPMError.Code.UNEXPECTED_DATA, "%s - NPM manifest missing required fields" % package_name)
	elif not npm_manifest["dist"].has("tarball"):
		return GPMUtils.ERR(GPMError.Code.UNEXPECTED_DATA, "%s - NPM manifest missing required fields tarball" % package_name)

	return GPMUtils.OK(npm_manifest)

#endregion