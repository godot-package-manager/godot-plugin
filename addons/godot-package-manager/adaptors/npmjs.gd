class_name GPMNpm

const REGISTRY := "https://registry.npmjs.org"

static func request_npm_manifest(package_name: String, package_version: String) -> GPMResult:
	var url = REGISTRY + "/%s/%s" % [package_name, package_version]
	var res = yield(GPMHttp.send_get_request(url), "completed")
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