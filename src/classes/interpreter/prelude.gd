class_name Prelude
## Module for prelude definitions, the standard library for the language.
##
## This module contains definitions for built-in functions, defined as native
## GDScript static functions wrapped in [Value.NativeClosure] values to
## reduce boilerplate and overhead.[br]
## Also includes helper functions for internal use.

## Hard cap for natives that walk a whole list eagerly (`length`).
## A cyclic lazy list (`let rec xs = 1 : xs`) used to spin these loops
## forever and freeze the game; past the cap they return an ErrorValue.
const MAX_EAGER_LIST_STEPS := 100_000

## Standard library environment.
static var std_lib: Env = Env.new(
	null,
	{
		"map": Value.NativeClosure.new(map, 2),
		"foldr": Value.NativeClosure.new(foldr, 3),
		"filter": Value.NativeClosure.new(filter, 2),
		"length": Value.NativeClosure.new(length, 1),
		"head": Value.NativeClosure.new(head, 1),
		"tail": Value.NativeClosure.new(tail, 1),
		"take": Value.NativeClosure.new(take, 2),
		"drop": Value.NativeClosure.new(drop, 2),
	},
)


## Loads prelude definitions into the given environment.
static func load_std_lib(env: Env) -> void:
	env.set_new_root(std_lib)


## Force an argument and validate its type. Returns the forced value on
## success, or an ErrorValue (the propagated one, or a fresh mismatch
## message) — callers must check `is_error()` before using the result.
static func _force_typed(arg: Value, expected: Value.Type, who: String) -> Value:
	var forced = arg.force() if arg != null else null
	if forced == null:
		return Value.error("internal: %s received no value" % who)
	if forced.is_error():
		return forced
	if forced.type != expected:
		return Value.error(
				"%s expected %s, but received %s"
				% [who, _type_name(expected), forced.type_to_string()])
	return forced


static func _type_name(t: Value.Type) -> String:
	match t:
		Value.Type.INT: return "Int"
		Value.Type.BOOL: return "Bool"
		Value.Type.TUPLE: return "Tuple"
		Value.Type.LIST: return "List"
		Value.Type.CLOSURE: return "Function"
		_: return "Unknown"


## Map a function over a list, returning a new list with the results.
static func map(args: Array[Value]) -> Value:
	var fn = _force_typed(args[0], Value.Type.CLOSURE, "map")
	if fn.is_error():
		return fn
	var lst = _force_typed(args[1], Value.Type.LIST, "map")
	if lst.is_error():
		return lst

	if lst.is_empty:
		return Value.List.new()

	var map_args: Array[Value] = [lst.head]
	var new_head = fn.apply(map_args)
	if new_head != null and new_head.is_error():
		return new_head

	var next_call = Expr.NativeCall.new(
		map,
		[fn, lst.tail]
	)

	return Value.List.new(new_head, Value.Thunk.new(next_call, Env.root()))


## Fold a function over a list, right associative, returning the final result.
static func foldr(args: Array[Value]) -> Value:
	var fn = _force_typed(args[0], Value.Type.CLOSURE, "foldr")
	if fn.is_error():
		return fn
	var acc: Value = args[1]
	var lst = _force_typed(args[2], Value.Type.LIST, "foldr")
	if lst.is_error():
		return lst

	if lst.is_empty:
		return acc

	var foldr_args: Array[Value] = [lst.head, acc]
	var applied = fn.apply(foldr_args)
	if applied != null and applied.is_error():
		return applied

	var next_call = Expr.NativeCall.new(
		foldr,
		[fn, applied, lst.tail]
	)

	return Value.Thunk.new(next_call, Env.root())


static func filter(args: Array[Value]) -> Value:
	var fn = _force_typed(args[0], Value.Type.CLOSURE, "filter")
	if fn.is_error():
		return fn
	var lst = _force_typed(args[1], Value.Type.LIST, "filter")
	if lst.is_error():
		return lst

	if lst.is_empty:
		return Value.List.new()

	var head_val = lst.head
	var tail_val = lst.tail

	var next_call = Expr.NativeCall.new(
		filter,
		[fn, tail_val]
	)

	var filter_args: Array[Value] = [head_val]
	var keep = fn.apply(filter_args)
	if keep != null:
		keep = keep.force()
	if keep == null:
		return Value.error("internal: filter predicate produced no value")
	if keep.is_error():
		return keep
	if keep.type != Value.Type.BOOL:
		return Value.error(
				"filter predicate must return Bool, but returned %s"
				% keep.type_to_string())

	if keep.unwrap():
		return Value.List.new(head_val, Value.Thunk.new(next_call, Env.root()))
	else:
		return Value.Thunk.new(next_call, Env.root())


## Returns the length of a list as an integer.
static func length(args: Array[Value]) -> Value:
	var lst = _force_typed(args[0], Value.Type.LIST, "length")
	if lst.is_error():
		return lst
	var count = 0
	while not lst.is_empty:
		count += 1
		if count > MAX_EAGER_LIST_STEPS:
			return Value.error(
					"length: list exceeds %d elements (infinite list?)"
					% MAX_EAGER_LIST_STEPS)
		lst = lst.tail
		if lst == null:
			return Value.error("length: invalid list tail")
	return Value.Int.new(count)


## Returns the head of a list, or an empty list if the list is empty.
static func head(args: Array[Value]) -> Value:
	var lst = _force_typed(args[0], Value.Type.LIST, "head")
	if lst.is_error():
		return lst
	if lst.is_empty:
		return Value.List.new()
	return lst.head


## Returns the tail of a list, or an empty list if the list is empty.
static func tail(args: Array[Value]) -> Value:
	var lst = _force_typed(args[0], Value.Type.LIST, "tail")
	if lst.is_error():
		return lst
	if lst.is_empty:
		return Value.List.new()
	var t = lst.tail
	if t == null:
		return Value.error("tail: invalid list tail")
	return t


## Takes the first n elements of a list, returning a new list with those elements.
static func take(args: Array[Value]) -> Value:
	var n_val = _force_typed(args[0], Value.Type.INT, "take")
	if n_val.is_error():
		return n_val
	var n: int = n_val.unwrap()
	var lst = _force_typed(args[1], Value.Type.LIST, "take")
	if lst.is_error():
		return lst

	if n <= 0 or lst.is_empty:
		return Value.List.new()  # Return empty list

	var next_step = Expr.NativeCall.new(
		take,
		[Value.Int.new(n - 1), lst.tail]
	)

	return Value.List.new(lst.head, Value.Thunk.new(next_step, Env.root()))


## Drops the first n elements of a list, returning the remaining list.
static func drop(args: Array[Value]) -> Value:
	var n_val = _force_typed(args[0], Value.Type.INT, "drop")
	if n_val.is_error():
		return n_val
	var n: int = n_val.unwrap()
	var lst = _force_typed(args[1], Value.Type.LIST, "drop")
	if lst.is_error():
		return lst

	if n <= 0 or lst.is_empty:
		return lst  # Return the original list

	var next_step = Expr.NativeCall.new(
		drop,
		[Value.Int.new(n - 1), lst.tail]
	)

	return Value.Thunk.new(next_step, Env.root())


## Internal helper for range generation. [br]
## Not meant to be exposed in the standard library.
static func range_step(args: Array[Value]) -> Value:
	var current_val = _force_typed(args[0], Value.Type.INT, "range")
	if current_val.is_error():
		return current_val
	var current: int = current_val.unwrap()
	var end = args[1]

	if end != null and end.is_error():
		return end

	# An open range (`[1..]`) carries an empty List as its end marker;
	# any other non-Int end is a type error (it used to make the range
	# silently infinite).
	if end != null and end.type != Value.Type.INT and end.type != Value.Type.LIST:
		return Value.error(
				"Range end must be Int, but received %s" % end.type_to_string())

	var next_val = Value.Int.new(current + 1)

	if end != null and end.type == Value.Type.INT and current > end.unwrap():
		return Value.List.new()

	var next_call = Expr.NativeCall.new(
		range_step,
		[
			Expr.Constant.new(next_val),
			Expr.Constant.new(end),
		],
	)

	return Value.List.new(Value.Int.new(current), Value.Thunk.new(next_call, Env.root()))
