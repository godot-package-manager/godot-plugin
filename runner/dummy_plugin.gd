extends Node

func get_editor_interface() -> Node:
	return self

func get_base_control() -> Node:
	return get_parent()

func get_resource_filesystem() -> Node:
	return self

func scan() -> void:
	return
