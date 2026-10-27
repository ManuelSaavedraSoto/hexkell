@abstract
class_name Pattern
extends RefCounted
## Abstract class for patterns within the AST.
##
## All patterns in the AST inherit from this class.


## Matches the pattern against a given [Value].
@abstract func match(value: Value) -> Dictionary


## Integer pattern class
class Int extends Pattern:
	var _value: int


	func _init(value: int) -> void:
		_value = value


	func _to_string() -> String:
		return "Pattern.Int(%d)" % _value


	func match(value: Value) -> Dictionary:
		var forced_value: Value = value.force()

		if forced_value.type == Value.Type.INT and forced_value.unwrap() == _value:
			return {"matched": true, "bindings": {}}
		else:
			return {"matched": false, "bindings": {}}


## Boolean pattern class
class Bool extends Pattern:
	var _value: bool

	
	func _init(value: bool) -> void:
		_value = value


	func _to_string() -> String:
		return "Pattern.Bool(%s)" % str(_value)


	func match(value: Value) -> Dictionary:
		var forced_value: Value = value.force()

		if forced_value.type == Value.Type.BOOL and forced_value.unwrap() == _value:
			return {"matched": true, "bindings": {}}
		else:
			return {"matched": false, "bindings": {}}


## Variable pattern class
##
## Matches any pattern and binds it to the name without forcing evaluation.
class Var extends Pattern:
	var _name: String

	
	func _init(name: String) -> void:
		_name = name


	func _to_string() -> String:
		return "Pattern.Var(%s)" % _name

	
	func match(value: Value) -> Dictionary:
		return {"matched": true, "bindings": {_name: value}}


## Tuple pattern class
class Tuple extends Pattern:
	var _patterns: Array[Pattern]

	
	func _init(patterns: Array[Pattern]) -> void:
		_patterns = patterns


	func _to_string() -> String:
		return "Pattern.Tuple(%s)" % str(_patterns)

	
	func match(value: Value) -> Dictionary:
		var _value := value.force()

		if (
				_value.type != Value.Type.TUPLE 
				or _value.size() != _patterns.size()
		):
			return {"matched": false, "bindings": {}}
		
		var all_bindings: Dictionary = {}

		for i in range(_patterns.size()):
			var pattern = _patterns[i]
			var element_value = _value.get_element(i)
			var match_result = pattern.match(element_value)
			if not match_result["matched"]:
				return {"matched": false, "bindings": {}}
			all_bindings.merge(match_result["bindings"])

		return {"matched": true, "bindings": all_bindings}


## List pattern class
##
## Matches a list of values against a list of patterns.
class List extends Pattern:
	var _patterns: Array[Pattern]


	func _init(patterns: Array[Pattern]) -> void:
		_patterns = patterns


	func _to_string() -> String:
		return "Pattern.List(%s)" % str(_patterns)


	func match(value: Value) -> Dictionary:
		var _value := value.force()

		if _value.type != Value.Type.LIST:
			return {"matched": false, "bindings": {}}

		if _patterns.size() == 0:
			if _value.is_empty:
				return {"matched": true, "bindings": {}}
			else:
				return {"matched": false, "bindings": {}}

		var current_value: Value = _value
		var all_bindings: Dictionary = {}

		for i in range(_patterns.size()):
			if current_value.is_empty:
				return {"matched": false, "bindings": {}}
			
			var head_value = current_value.head
			var match_result = _patterns[i].match(head_value)

			if not match_result["matched"]:
				return {"matched": false, "bindings": {}}

			all_bindings.merge(match_result["bindings"])
			current_value = current_value.tail

		if not current_value.is_empty:
			return {"matched": false, "bindings": {}}

		return {"matched": true, "bindings": all_bindings}


## Cons pattern class
##
## Matches a list with a head and tail pattern (head:tail).
class Cons extends Pattern:
	var _head_pattern: Pattern
	var _tail_pattern: Pattern

	func _init(head_pattern: Pattern, tail_pattern: Pattern) -> void:
		_head_pattern = head_pattern
		_tail_pattern = tail_pattern


	func _to_string() -> String:
		return "Pattern.Cons(%s : %s)" % [_head_pattern._to_string(), _tail_pattern._to_string()]


	func match(value: Value) -> Dictionary:
		var _value := value.force()

		if _value.type != Value.Type.LIST or _value.is_empty:
			return {"matched": false, "bindings": {}}

		if _value.is_empty:
			return {"matched": false, "bindings": {}}

		var head_value = _value.head
		var head_result = _head_pattern.match(head_value)

		if not head_result["matched"]:
			return {"matched": false, "bindings": {}}

		var tail_value = _value.tail
		var tail_result = _tail_pattern.match(tail_value)

		if not tail_result["matched"]:
			return {"matched": false, "bindings": {}}

		var all_bindings: Dictionary = {}
		all_bindings.merge(head_result["bindings"])
		all_bindings.merge(tail_result["bindings"])

		return {"matched": true, "bindings": all_bindings}


## Wildcard pattern class
##
## Matches any value without binding it to a name or forcing its evaluation.
class Wildcard extends Pattern:    
	func _to_string() -> String:
		return "Pattern.Wildcard()"


	func match(_value: Value) -> Dictionary:
		return {"matched": true, "bindings": {}}
