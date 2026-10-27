extends "res://src/classes/hex_nodes/operators/unary_op_hex.gd"
## Bespoke `!` (boolean negation) operator.

func _init() -> void:
	super._init()
	op_text = "!"
