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

static func packages_from_manifest(manifest: Dictionary) -> Dictionary:
	return manifest.get(PackageJson.PACKAGES, {})

## Gets the package.json file for an NPM package.
static func get_manifest(http: Net, package_name: String, version: String) -> Dictionary:
	var response: Dictionary = await http.get_request(
		JS_DELIVR, MANIFEST_FORMAT % [package_name, version], [200])
	
	return response
