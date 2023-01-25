extends RefCounted

## Wrapper around NPM search functionality.
##
## Reference: https://github.com/npm/registry/blob/master/docs/REGISTRY-API.md

const Net := preload("res://addons/godot-package-manager/net.gd")

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
## https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md
##
## @param http: Net - The http helper.
## @param package_name: String - The package to search for. (e.g. @my_namespace/my_package)
##
## @return Dictionary - The packument.
static func get_package_metadata(http: Net, package_name: String) -> Dictionary:
	var response: Dictionary = await http.get_request(
		NPM, GET_FORMAT % package_name, [200]
	)
	
	return response

## Gets the package.json file for an NPM package.
##
## @param http: Net - The http helper.
## @param package_name: String - The package to search for. (e.g. @my_namespace/my_package)
## @param version: String - The package version. (e.g. 1.0.0)
##
## @return Dictionary - The manifest for the package. Will be empty if there was an error.
static func get_manifest(http: Net, package_name: String, version: String) -> Dictionary:
	var response: Dictionary = await http.get_request(
		NPM, GET_WITH_VERSION_FORMAT % [package_name, version], [200])
	
	return response

## Search NPM for a given package.
##
## @param http: Net - The http helper.
## @param search_term: String - The search term that's automatically uri encoded.
##
## @return Array[Dictionary] - List of Dictionaries containing package metadata.
static func search(http: Net, search_term: String) -> Array[Dictionary]:
	var response: Dictionary = await http.get_request(
		NPM, SEARCH_FORMAT % search_term.uri_encode(), [200]
	)
	
	return response.get("objects", [])
