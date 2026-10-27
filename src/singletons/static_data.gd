extends Node

var static_data = {}
var static_data_path = "res://data/static_data.json"

# Maps short hex ids to their script paths so the JSON (e.g. a job's
# `unlocks_hexes`) can reference hexes by id instead of brittle hard paths.
# Ids follow `hex_<stem>`, where <stem> is the script filename minus the
# `_hex.gd` suffix (add_hex.gd → hex_add, let_rec_hex.gd → hex_let_rec).
# Resolve through `hex_path()` / `hex_paths()`. A test cross-checks this
# against HexPalette.SCRIPT_FAMILY so a new hex can't drift out of sync.
const HEX_REGISTRY := {
	# Integer
	"hex_int_literal": "res://src/classes/hex_nodes/literals/integer/int_literal_hex.gd",
	"hex_add": "res://src/classes/hex_nodes/operators/arithmetic/add_hex.gd",
	"hex_sub": "res://src/classes/hex_nodes/operators/arithmetic/sub_hex.gd",
	"hex_mul": "res://src/classes/hex_nodes/operators/arithmetic/mul_hex.gd",
	"hex_div": "res://src/classes/hex_nodes/operators/arithmetic/div_hex.gd",
	"hex_mod": "res://src/classes/hex_nodes/operators/arithmetic/mod_hex.gd",
	"hex_neg": "res://src/classes/hex_nodes/operators/arithmetic/neg_hex.gd",

	# Boolean
	"hex_true": "res://src/classes/hex_nodes/literals/booleans/true_hex.gd",
	"hex_false": "res://src/classes/hex_nodes/literals/booleans/false_hex.gd",
	"hex_and": "res://src/classes/hex_nodes/operators/logical/and_hex.gd",
	"hex_or": "res://src/classes/hex_nodes/operators/logical/or_hex.gd",
	"hex_not": "res://src/classes/hex_nodes/operators/logical/not_hex.gd",
	"hex_eq": "res://src/classes/hex_nodes/operators/logical/eq_hex.gd",
	"hex_neq": "res://src/classes/hex_nodes/operators/logical/neq_hex.gd",
	"hex_lt": "res://src/classes/hex_nodes/operators/logical/lt_hex.gd",
	"hex_gte": "res://src/classes/hex_nodes/operators/logical/gte_hex.gd",

	# Functions
	"hex_lambda": "res://src/classes/hex_nodes/literals/lambdas/lambda_hex.gd",
	"hex_if": "res://src/classes/hex_nodes/control/if_hex.gd",
	"hex_match": "res://src/classes/hex_nodes/control/match_hex.gd",
	"hex_apply": "res://src/classes/hex_nodes/operators/functional/apply_hex.gd",
	"hex_compose": "res://src/classes/hex_nodes/operators/functional/compose_hex.gd",

	# Structures
	"hex_tuple": "res://src/classes/hex_nodes/literals/tuple/tuple_hex.gd",
	"hex_list_literal": "res://src/classes/hex_nodes/literals/list/list_literal_hex.gd",
	"hex_range": "res://src/classes/hex_nodes/operators/list/range_hex.gd",
	"hex_cons": "res://src/classes/hex_nodes/operators/list/cons_hex.gd",
	"hex_concat": "res://src/classes/hex_nodes/operators/list/concat_hex.gd",

	# Naming
	"hex_let": "res://src/classes/hex_nodes/control/let_hex.gd",
	"hex_let_rec": "res://src/classes/hex_nodes/control/let_rec_hex.gd",
	"hex_definition": "res://src/classes/hex_nodes/control/definition_hex.gd",
	"hex_ident_ref": "res://src/classes/hex_nodes/literals/identifier/ident_ref_hex.gd",

	# Fixtures
	"hex_do": "res://src/classes/hex_nodes/fixtures/do_hex.gd",
	"hex_anchor": "res://src/classes/hex_nodes/fixtures/anchor_hex.gd",
	"hex_match_anchor": "res://src/classes/hex_nodes/fixtures/match_anchor.gd",
}


func _ready() -> void:
	static_data = load_json_file(static_data_path)


# Resolve a hex reference to its script path. Accepts a registry id
# (`hex_add`) or, for migration safety, a raw `res://…` path (returned
# unchanged). Unknown ids log an error and return "".
func hex_path(id_or_path: String) -> String:
	if id_or_path.begins_with("res://"):
		return id_or_path
	if HEX_REGISTRY.has(id_or_path):
		return HEX_REGISTRY[id_or_path]
	push_error("Unknown hex id: %s" % id_or_path)
	return ""


# Resolve a list of hex references to paths, dropping any that fail.
func hex_paths(ids: Array) -> Array:
	var out: Array = []
	for entry in ids:
		var path := hex_path(String(entry))
		if path != "":
			out.append(path)
	return out


func load_json_file(filepath: String) -> Dictionary:
	if FileAccess.file_exists(filepath):
		
		var data_file = FileAccess.open(filepath, FileAccess.READ)
		var json = JSON.new()
		var error = json.parse(data_file.get_as_text())

		data_file.close()

		if error == OK:
			if json.data is Dictionary:
				return json.data
			else:
				push_error("JSON data is not a dictionary: %s" % filepath)
				return {}
		else:
			push_error("Failed to parse JSON file: %s" % filepath)
			return {}

	else:
		push_error("File not found: %s" % filepath)
		return {}
