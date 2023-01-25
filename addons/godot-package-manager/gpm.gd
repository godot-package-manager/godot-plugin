extends RefCounted

## A message that may be logged at any point during runtime.
signal message_logged(text: String)

signal operation_started(operation_name: String, number_of_packages: int)
signal operation_checkpoint_reached(package_name: String)
signal operation_finished()

const NPM_REGISTRY := "https://registry.npmjs.org"
const ADDONS_DIR := "res://addons"
const ADDONS_DIR_FORMAT := ADDONS_DIR + "/%s"
const DEPENDENCIES_DIR_FORMAT := "res://addons/__gpm_deps/%s/%s"

#const CONNECTING_STATUS

var npm := preload("res://addons/godot-package-manager/npm.gd").new()
var net := preload("res://addons/godot-package-manager/net.gd").new()
var dir_utils := preload("res://addons/godot-package-manager/dir_utils.gd").new()
var file_utils := preload("res://addons/godot-package-manager/file_utils.gd").new()
var dict_utils := preload("res://addons/godot-package-manager/dict_utils.gd").new()

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#
