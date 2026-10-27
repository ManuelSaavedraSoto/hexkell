extends "res://src/classes/hex_nodes/control/let_hex.gd"
## `let rec NAME = V in B`. Same outer face and inner level as LetHex,
## but the bound name is also in scope inside V — enables a function
## value to reference itself for recursion.
##
## Implemented as a thin LetHex subclass that flips `is_rec`. The
## parent class handles label text, generated keyword, and the
## inner-level anchor's emission identically.


func _init() -> void:
	super._init()
	is_rec = true
