extends "res://src/classes/hex_nodes/operators/binary_op_hex.gd"
## Bespoke ++ operator.

func _init() -> void:
	super._init()
	op_text = "++"
	# front/back say more than the inherited left/right — validation
	# errors and the config sidebar pick these up too.
	input_role_names = {4: "front", 2: "back"}
	input_role_labels = {4: "front", 2: "back"}
