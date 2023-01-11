extends RefCounted

const Net := preload("res://addons/godot-package-manager/net.gd")

const PackageJson := {
	"PACKAGES": "packages",
}

const JS_DELIVR := "https://cdn.jsdelivr.net"
const MANIFEST_FORMAT := "npm/%s@%s/package.json"

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Gets the packages from a package.json.
##
## @param manifest: Dictionary - The parsed contents of a package.json.
##
## @return Dictionary<String, String | Dictionary> - The packages in a package.json.
static func packages_from_manifest(manifest: Dictionary) -> Dictionary:
	return manifest.get(PackageJson.PACKAGES, {})

## Gets the package.json file for an NPM package.
##
## @param http: Net - The http helper.
## @param package_name: String - The package to search for. (e.g. @my_namespace/my_package)
## @param version: String - The package version. (e.g. 1.0.0)
##
## @return Dictionary - The manifest for the package. Will be empty if there was an error.
static func get_manifest(http: Net, package_name: String, version: String) -> Dictionary:
	var response: Dictionary = await http.get_request(
		JS_DELIVR, MANIFEST_FORMAT % [package_name, version], [200])
	
	return response
