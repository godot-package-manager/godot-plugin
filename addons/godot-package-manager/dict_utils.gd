extends RefCounted

#-----------------------------------------------------------------------------#
# Builtin functions
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Private functions
#-----------------------------------------------------------------------------#

## Helper for recursively flattening a Dictionary.
##
## @param dict: Dictionary - The current Dictionary to flatten.
## @param array: Array - All flattened values for the root Dictionary
static func _flatten_values(dict: Dictionary, array: Array) -> void:
	for v in dict.values():
		if v is Dictionary:
			_flatten_values(v, array)
			continue
		
		array.push_back(v)

#-----------------------------------------------------------------------------#
# Public functions
#-----------------------------------------------------------------------------#

## Recursive flatten a Dictionary's values into an Array. All nested Dictionary's will also
## be flattened.
##
## @param dict: Dictionary - The Dictionary to flatten.
##
## @return Array<Variant> - The flattened Dictionary.
static func flatten_values(dict: Dictionary) -> Array:
	var r := []
	
	_flatten_values(dict, r)
	
	return r
