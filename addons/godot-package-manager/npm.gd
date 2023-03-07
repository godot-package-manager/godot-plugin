extends RefCounted

## Wrapper around NPM search functionality.
##
## Reference: [url]https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md[/url]

const TarballInfo := GodotPackageManager.Model.NpmTarballInfo
const Net := GodotPackageManager.Net

const PackageJson := {
	"PACKAGES": "packages",
}

const NPM := "https://registry.npmjs.org"
const GET_FORMAT := "/%s"
const GET_WITH_VERSION_FORMAT := "/%s/%s"
const SEARCH_FORMAT := "/-/v1/search?text=%s"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Get the packument for the given package.
## [url]https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md[/url] [br]
##
## Params: [br]
## [param package_name]: [String] - The package to search for. (e.g. @my_namespace/my_package) [br]
##
## Returns: [br]
## [param Dictionary] - The packument.
static func get_package_metadata(package_name: String) -> Dictionary:
	var response: Dictionary = await Net.get_request_json(
		NPM, GET_FORMAT % package_name, [200]
	)
	
	return response

## Gets the package.json file for an NPM package. [br]
##
## Params: [br]
## [param package_name]: [String] - The package to search for. (e.g. @my_namespace/my_package) [br]
## [param version]: [String] - The package version. (e.g. 1.0.0) [br]
##
## Returns: [br]
## [param Dictionary] - The manifest for the package. Will be empty if there was an error.
static func get_manifest(package_name: String, version: String) -> Dictionary:
	var response: Dictionary = await Net.get_request_json(
		NPM, GET_WITH_VERSION_FORMAT % [package_name, version], [200])
	
	return response

# TODO don't use this
## Gets the tarball url for a given package and version. [br]
##
## Params: [br]
## [param package_name]: [String] - The package to get. [br]
## [param version]: [String] - The version to get. [br]
##
## Returns: [br]
## [param String] - The tarball url or an empty [String] if the package:version could not be found.
static func get_tarball_url(package_name: String, version: String) -> String:
	var response := await get_manifest(package_name, version)
	if response.is_empty():
		printerr("get_tarball_url response was empty")
		return ""
	
	return response.get("dist", {}).get("tarball", "")

static func get_tarball_info(package_name: String, version: String) -> TarballInfo:
	var r := TarballInfo.new()
	
	var response := await get_manifest(package_name, version)
	if response.is_empty():
		printerr("get_tarball_info response was empty")
		return r
	
	var dist: Dictionary = response.get("dist", {})
	if dist.is_empty():
		printerr("get_tarball_info dist was empty")
		return r
	
	r.url = dist.get("tarball", "")
	if r.url.is_empty():
		printerr("get_tarball_info no tarball url found")
		return r
	r.size = dist.get("unpackedSize", 0)
	if r.size < 1:
		printerr("get_tarball_info no unpackedSize found")
		return r
	r.shasum = dist.get("shasum", "")
	if r.shasum.is_empty():
		printerr("get_tarball_info no shasum found")
		return r
	
	r.is_error = false
	
	return r

## Search NPM for a given package. [br]
##
## Params: [br]
## [param search_term]: [String] - The search term that's automatically uri encoded. [br]
##
## Returns: [br]
## [param Array] - List of [Dictionary]s containing package metadata.
static func search(search_term: String) -> Array:
	var response: Dictionary = await Net.get_request_json(
		NPM, SEARCH_FORMAT % search_term.uri_encode(), [200]
	)
	
	return response.get("objects", [])
