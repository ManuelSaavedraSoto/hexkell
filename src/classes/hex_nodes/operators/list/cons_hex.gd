extends "res://src/classes/hex_nodes/operators/binary_op_hex.gd"
## Bespoke `:` (cons) operator.

func _init() -> void:
	super._init()
	op_text = ":"
	# head/tail say more than the inherited left/right — validation
	# errors and the config sidebar pick these up too.
	input_role_names = {4: "head", 2: "tail"}
	input_role_labels = {4: "head", 2: "tail"}
