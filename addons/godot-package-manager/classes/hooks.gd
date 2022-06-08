class_name GPMHooks

var _hooks := {} # Hook name: String -> GPMAdvancedExpression

func add(hook_name: String, advanced_expression: GPMAdvancedExpression) -> void:
	_hooks[hook_name] = advanced_expression

## Runs the given hook if it exists. Requires the containing GPM to be passed
## since all scripts assume they have access to a `gpm` variable
##
## @param: gpm: Object - The containing GPM. Must be a valid `Object`
## @param: hook_name: String - The name of the hook to run
##
## @return: Variant - The return value, if any. Will return `null` if the hook is not found
func run(gpm: Object, hook_name: String):
	return _hooks[hook_name].execute([gpm]) if _hooks.has(hook_name) else null