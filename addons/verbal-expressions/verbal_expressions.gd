extends RegEx

"""
Based off of https://github.com/VerbalExpressions/JavaVerbalExpressions
The Python implementation is lacking features and seems to be slightly incorrect
when handling words:
https://github.com/VerbalExpressions/PythonVerbalExpressions/blob/dadbb6f9c1107cca9a448dc608acfba283064b47/tests/verbal_expressions_test.py#L178
The Javascript implementation seems to not handle prefixes correctly:
https://github.com/VerbalExpressions/JSVerbalExpressions/blob/56a21a5b3900e4b6b9fd5daba00dd31b4b24c2a7/VerbalExpressions.js#L90

Basically, the test isn't even testing `word()` which is why it passes

The built-in RegEx module in Godot does NOT support modifiers. All strings
must properly escape backslashes
"""

var _sanitizer_regex := RegEx.new()

var _prefixes := []
var _source := []
var _suffixes := []

var build_result := OK

###############################################################################
# Utils                                                                       #
###############################################################################

func _init() -> void:
	_sanitizer_regex.compile("[\\W]")

func _to_string() -> String:
	return "%s%s%s" % [_build_string(_prefixes), _build_string(_source), _build_string(_suffixes)]

static func _build_string(input: Array) -> String:
	return PoolStringArray(input).join("")

static func _push_builder_error(text: String) -> void:
	push_error("Only Strings and VerbalExpression objects can be added to the builder: %s" % text)

static func _count_occurrences_of(where: String, what: String) -> int:
	return (where.length() - where.replace(what, "").length()) / what.length()

func _sanitize(value) -> String:
	return _sanitizer_regex.sub(str(value), "\\$0", true)

func clear() -> void:
	.clear()
	_prefixes.clear()
	_source.clear()
	_suffixes.clear()

func build() -> Reference:
	build_result = compile(_to_string())
	return self

###############################################################################
# Builder commands                                                            #
###############################################################################

func add(value) -> Reference:
	"""
	Append a literal expression. Everything added to the expression should go through this method.
	
	When adding another VerbalExpressions object, the expression is built and added as a group
	
	Param:
		value - The expression, not sanitized | A VerbalExpressions object
	
	Return:
		Reference - The builder
	"""
	match typeof(value):
		TYPE_STRING:
			_source.append(value)
		TYPE_OBJECT:
			if value.has_method("build"):
				group().add(value.to_string()).end_group()
			else:
				_push_builder_error(str(value))
		_:
			_push_builder_error(str(value))
	return self

func start_of_line(enable: bool = true) -> Reference:
	"""
	Enable or disable the expression to start at the beginning of the line
	
	Params:
		enable: bool - Enables or disables the line starting
	
	Return:
		Reference - The builder
	"""
	if enable:
		_prefixes.append("^")
	else:
		var prefixes := _build_string(_prefixes).replace("^", "")
		_prefixes.clear()
		_prefixes.append(prefixes)
	
	return self

func end_of_line(enable: bool = true) -> Reference:
	"""
	Enable or disable the expression to end at the last character of the line
	
	Params:
		enable: bool - Enables or disables the line ending
	
	Return:
		Reference - The builder
	"""
	if enable:
		_suffixes.append("$")
	else:
		var suffixes := _build_string(_suffixes).replace("$", "")
		_suffixes.clear()
		_suffixes.append(suffixes)
	
	return self

func then(value: String) -> Reference:
	"""
	Add a string to the expression
	
	Params:
		value: String - The string to be looked for (sanitized)
	
	Return:
		Reference - The builder
	"""
	return add("(?:%s)" % _sanitize(value))

func find(value: String) -> Reference:
	"""
	Add a string to the expression. Syntax sugar for then(value)
	"""
	return then(value)

func maybe(value) -> Reference:
	"""
	Add a string to the expression that might appear once or not. Could also be a
	VerbalExpressions object that will be added to a new group
	
	Params:
		value - The string to be looked for | VerbalExpressions builder
	
	Return:
		Reference - The builder
	"""
	match typeof(value):
		TYPE_STRING:
			then(value).add("?")
		TYPE_OBJECT:
			if value.has_method("build"):
				group().add(value).end_group().add("?")
			else:
				_push_builder_error(str(value))
		_:
			_push_builder_error(str(value))
	return self

func anything() -> Reference:
	"""
	Add an expression that matches anything including empty strings
	
	Return:
		Reference - The builder
	"""
	return add("(?:.*)")

func anything_but(value: String) -> Reference:
	"""
	Add an expression that matches anything except for the passed argument
	
	Params:
		value: String - The string not to match
	
	Return:
		Reference - The builder
	"""
	return add("(?:[^%s]*)" % _sanitize(value))

func something() -> Reference:
	"""
	Add an expression that matches something that might appear once or more
	
	Return:
		Reference - The builder
	"""
	return add("(?:.+)")

func something_but_not(value: String) -> Reference:
	"""
	Add an expression that matches something that might appear once or more
	expect for the passed argument
	
	Params:
		value: String - The string not to match
	
	Return:
		Reference - The builder
	"""
	return add("(?:[^%s]+)" % value)

func line_break() -> Reference:
	"""
	Add a universal line break expression
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\n|(?:\\r\\n)|(?:\\r\\r))")

func br() -> Reference:
	"""
	Syntactic sugar for line_break()
	"""
	return line_break()

func tab() -> Reference:
	"""
	Add an expression to match a tab character ('\u0009')
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\t)")

# TODO this might not be true
func word() -> Reference:
	"""
	Add word, same as [a-zA-Z_0-9]+
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\w+)")

#region Predefined character classes

func word_char() -> Reference:
	"""
	Add word character, same as [a-zA-Z_0-9]
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\w)")

func non_word_char() -> Reference:
	"""
	Add non-word character: [^\\w]
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\W)")

func non_digit() -> Reference:
	"""
	Add non-digit: ["^0-9"]
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\D)")

func digit() -> Reference:
	"""
	Add digit, same as [0-9]
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\d)")

func space() -> Reference:
	"""
	Add whitespace character, same as [ \\t\\n\\x0B\\f\\r]
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\s)")

func non_space() -> Reference:
	"""
	Add non-whitespace character: [^\\s]
	
	Return:
		Reference - The builder
	"""
	return add("?:\\S")

func word_boundary() -> Reference:
	"""
	Add word boundary: \\b
	
	Return:
		Reference - The builder
	"""
	return add("(?:\\b)")

#endregion

func any_of(value: String) -> Reference:
	"""
	Matches against the value param
	
	Params:
		value: String - The string to match
	
	Return:
		Reference - The builder
	"""
	return add("[%s]" % _sanitize(value))

func any(value: String) -> Reference:
	"""
	Syntactic sugar for any_of(value)
	
	Params:
		value: String - The string to match
	
	Return:
		Reference - The builder
	"""
	return any_of(value)

func RANGE(args: Array) -> Reference:
	"""
	Add an expression to match a range or multiple ranges
	
	Params:
		args: Array[Variant] - A list of ranges to match, should be castable to String
	
	Return:
		Reference - The builder
	"""
	var value := ["["]
	for i in range(1, args.size(), 2):
		var from := _sanitize(args[i - 1])
		var to := _sanitize(args[i])
		
		value.append("%s-%s" % [from, to])
	value.append("]")
	
	return add(_build_string(value))

func multiple(value: String, count: Array = []) -> Reference:
	"""
	Convenience method to show that string usage count is the exact count
	
	Params:
		value: String - The string to look for
		count: Array[String] - The count, can contain 0, 1, or 2 args
	
	Return:
		Reference - The builder
	"""
	if count.empty():
		return then(value).one_or_more()
	match count.size():
		1, 2:
			return then(value).count(count)
		_:
			return then(value).one_or_more()

func one_or_more() -> Reference:
	"""
	Add '+' to the expression
	
	Return:
		Reference - The builder
	"""
	return add("+")

func zero_or_more() -> Reference:
	"""
	Add '*' to the expression
	
	Return:
		Reference - The builder
	"""
	return add("*")

func count(count: Array) -> Reference:
	"""
	Add count of group
	
	Params:
		count: Array[Variant] - The number of occurrences of the previous group in the expression, each item
								should be castable to String
	
	Return:
		Reference - The builder
	"""
	_source.append("{")
	
	match count.size():
		1:
			_source.append(_sanitize(count[0]))
		2:
			_source.append(_sanitize(count[0]))
			_source.append(",")
			_source.append(_sanitize(count[1]))
		_:
			push_error("Invalid number of arguments for count(...)")
	
	_source.append("}")
	
	return self

func at_least(from: int) -> Reference:
	"""
	Range count with only the minimal number of occurrences
	
	Params:
		from: int - The minimal number of occurrences
	
	Return:
		Reference - The builder
	"""
	return add("{").add(str(from)).add(",}")

func OR(value: String = "") -> Reference:
	"""
	Add an alternative expression to be matched
	
	Params:
		value: String - The string to be looked for
	
	Return:
		Reference - The builder
	"""
	_prefixes.append("(?:")
	
	var opened: int = _count_occurrences_of(_build_string(_prefixes), "(")
	var closed: int = _count_occurrences_of(_build_string(_suffixes), ")")
	
	if (opened >= closed):
		var text := _build_string(_suffixes)
		_suffixes.clear()
		_suffixes.append(")")
		_suffixes.append(text)
	
	add(")|(?:")
	if not value.empty():
		then(value)
	
	return self

func one_of(args: Array) -> Reference:
	"""
	Adds an alternative expression to be matched based on an array of values
	
	Params:
		args: Array[String] - The strings to be looked for
	
	Return:
		Reference - The builder
	"""
	if not args.empty():
		add("(?:")
		
		var args_size: int = args.size()
		for i in args_size:
			var value = args[i]
			if typeof(value) != TYPE_STRING:
				push_error("Invalid argument for one_of(...): %s" % str(value))
				continue
			
			add("(?:%s)" % value)
			
			if i < args_size - 1:
				add("|")
		add(")")
	
	return self

func capture(capture_name: String = "") -> Reference:
	"""
	Adds named-capture - open brace to the current position and closed to suffixes
	
	Params:
		capture_name: String - Name for the capture
	
	Return:
		Reference - The builder
	"""
	_suffixes.append(")")
	
	if capture_name.empty():
		return add("(")
	
	return add("(?<%s>" % capture_name)

func capt(capture_name: String = "") -> Reference:
	"""
	Syntactic sugar for capture(capture_name)
	
	Params:
		capture_name: String - Name for the capture
	
	Return:
		Reference - The builder
	"""
	return capture(capture_name)

func group() -> Reference:
	"""
	Same as capture(capture_name) but does not save the result
	May be used to set the count of duplicated captures without creating a new saved capture
	
	Returns:
		Reference - The builder
	"""
	_suffixes.append(")")
	return add("(?:")

func gr() -> Reference:
	"""
	Syntactic sugar for group()
	
	Returns:
		Reference - The builder
	"""
	return group()

func end_capture() -> Reference:
	"""
	Close brace for previous capture and remove las closed brace from suffixes
	Can be used to continue building the regex after capture or to add multiple captures
	
	Returns:
		Reference - The builder
	"""
	if _suffixes.find(")") != -1:
		_suffixes.resize(_suffixes.size() - 1)
		return add(")")
	else:
		push_error("Cannot end capture group if it has not started")
		return self

func end_capt() -> Reference:
	"""
	Syntactic sugar for end_capture()
	
	Returns:
		Reference - The builder
	"""
	return end_capture()

func end_group() -> Reference:
	"""
	Syntactic sugar for end_capture()
	
	Returns:
		Reference - The builder
	"""
	return end_capture()

func end_gr() -> Reference:
	"""
	Syntactic sugar for end_capture()
	
	Returns:
		Reference - The builder
	"""
	return end_capture()
