#!/usr/bin/env -S godot --no-window --script

#Must inherit from SceneTree according to https://docs.godotengine.org/en/latest/tutorials/editor/command_line_tutorial.html#running-a-script
extends SceneTree

const GPM_PATH = "addons/godot-package-manager/"
const GPM_MAIN_SCRIPT = "godot_package_manager.gd"

var gpm = load("res://"+GPM_PATH+GPM_MAIN_SCRIPT).new()

func _init():
    print("Hello!")
    
    quit()