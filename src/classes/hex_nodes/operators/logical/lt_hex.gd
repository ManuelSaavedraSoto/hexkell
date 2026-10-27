extends "res://src/classes/hex_nodes/operators/binary_op_hex.gd"
## Bespoke < operator.

func _init() -> void:
	super._init()
	op_text = "<"
	input_role_labels = {4: "left", 2: "right"}
