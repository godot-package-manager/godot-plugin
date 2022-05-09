# GDScript Verbal Expressions

[![Chat on Discord](https://img.shields.io/discord/853476898071117865?label=chat&logo=discord)](https://discord.gg/6mcdWWBkrr)

A port of [VerbalExpressions](https://github.com/VerbalExpressions) to GDScript. Tested on Godot 3.4.x.

Based on the [Java](https://github.com/VerbalExpressions/JavaVerbalExpressions) implementation.

An itch.io demo can be [found here](https://fakefirefly.itch.io/gdscript-verbal-expressions).

See the `tests` directory for more examples.

## Quickstart
1. Copy the `addons/verbal-expressions/` folder to your project's `addons` directory (create the `addons` directory if it doesn't exist)
2. Load the `verbal_expressions.gd` file in your script and create a new instance of it
3. Start constructing the regex expression
4. Call `build()` to compile the expression
5. Use the usual built-in `ReGex` methods to do regex stuff

## Example

Verify a URL

```GDScript
var verbal_expressions = load("res://addons/verbal-expressions/verbal_expressions.gd").new()

verbal_expressions \
    .start_of_line() \
    .then("http") \
    .maybe("s") \
    .then("://") \
    .maybe("www.") \
    .anything_but(" ") \
    .end_of_line() \
    .build()

var regex_match = verbal_expressions.search("https://godotengine.org/")

assert(regex_match != null)

# Technically unnecessary since `search(...)` returns null if there is no match
assert(regex_match.get_string() == "https://godotengine.org/")
```
