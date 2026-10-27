class_name MatchPatternTree
extends Tree
## Tree-based pattern builder for the Match config sidebar.
##
## One row per match branch; under each branch the pattern is built by
## option buttons (RANGE cells). Picking a *compound* kind — cons `( : )`,
## tuple `( , )`, list `[ ]` — extends the tree with follow-up sub-slots,
## each itself an option button. Leaf kinds (`_`, int, bool, name) expose
## an inline value editor instead.
##
## The widget owns a `PatternTree` model (plain Dictionaries) per branch
## and re-emits each branch's canonical source string via `pattern_edited`
## whenever it changes; the editor keeps storing pattern STRINGS, so the
## save format and scope queries are untouched.

## Emitted after any edit to branch `idx`, carrying its new source string.
signal pattern_edited(idx: int, source: String)

const PLUS_ICON: Texture2D = preload("res://assets/icons/buttons/plus_icon.tres")
const TRASH_ICON: Texture2D = preload("res://assets/icons/buttons/closed_trash.tres")

# RANGE option label per PatternTree.KINDS index. No internal commas
# (RANGE options are comma-separated).
const KIND_LABELS := "choose…,_,int,bool,name,cons,tuple,list"

const COL_ROLE := 0   # branch / child label (+ remove button)
const COL_KIND := 1   # kind option button
const COL_VALUE := 2  # leaf value editor / add button

const BTN_ADD := 0
const BTN_REMOVE := 1

# Tree buttons render at the texture's native size and `add_button` has
# no max-width, so the 50px source icons are downscaled to this width.
const BUTTON_MAX_WIDTH := 20

# One PatternTree node (Dictionary) per branch.
var _branches: Array = []

# 20px-wide icons derived from the source atlas textures in `_ready`.
var _plus_tex: Texture2D = PLUS_ICON
var _trash_tex: Texture2D = TRASH_ICON


func _ready() -> void:
	columns = COL_VALUE + 1
	set_column_title(COL_ROLE, "Slot")
	set_column_title(COL_KIND, "Kind")
	set_column_title(COL_VALUE, "Value")
	column_titles_visible = true
	hide_root = true
	set_column_expand(COL_KIND, false)
	set_column_custom_minimum_width(COL_KIND, 90)
	_plus_tex = _scaled_icon(PLUS_ICON)
	_trash_tex = _scaled_icon(TRASH_ICON)
	if not item_edited.is_connected(_on_item_edited):
		item_edited.connect(_on_item_edited)
	if not button_clicked.is_connected(_on_button_clicked):
		button_clicked.connect(_on_button_clicked)
	_rebuild()


# Downscale a source icon to BUTTON_MAX_WIDTH (preserving aspect) so the
# Tree's add/remove buttons stay compact. Falls back to the original if
# the image can't be read or is already small enough.
func _scaled_icon(src: Texture2D) -> Texture2D:
	var img := src.get_image()
	if img == null or img.get_width() <= BUTTON_MAX_WIDTH:
		return src
	img = img.duplicate()
	var h := int(round(img.get_height() * float(BUTTON_MAX_WIDTH) / float(img.get_width())))
	img.resize(BUTTON_MAX_WIDTH, maxi(h, 1), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


## Seed the branches from the editor's pattern strings (one per branch).
func set_branches(patterns: Array) -> void:
	_branches.clear()
	for p in patterns:
		_branches.append(PatternTree.parse(String(p)))
	if is_node_ready():
		_rebuild()


# ── View ────────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	clear()
	var root := create_item()
	for bi in _branches.size():
		_build_item(root, _branches[bi], "Branch %d" % (bi + 1), [bi], false)


# Build the TreeItem for `node` at `path` (branch index, then child
# indices). `removable` adds a remove button (used for tuple/list
# children, never for branch roots or cons head/tail).
func _build_item(parent: TreeItem, node: Dictionary, role: String, path: Array, removable: bool) -> void:
	var item := create_item(parent)
	item.set_metadata(COL_ROLE, path)

	item.set_text(COL_ROLE, role)
	item.set_selectable(COL_ROLE, false)
	if removable:
		item.add_button(COL_ROLE, _trash_tex, BTN_REMOVE, false, "Remove this element")

	var kind := String(node.get("kind", "slot"))
	item.set_cell_mode(COL_KIND, TreeItem.CELL_MODE_RANGE)
	item.set_text(COL_KIND, KIND_LABELS)
	item.set_range(COL_KIND, PatternTree.KINDS.find(kind))
	item.set_editable(COL_KIND, true)

	_setup_value_cell(item, node)
	_build_children(item, node, path)


func _setup_value_cell(item: TreeItem, node: Dictionary) -> void:
	match String(node.get("kind", "slot")):
		"int":
			item.set_cell_mode(COL_VALUE, TreeItem.CELL_MODE_STRING)
			item.set_text(COL_VALUE, String(node.get("value", "0")))
			item.set_editable(COL_VALUE, true)
		"bool":
			item.set_cell_mode(COL_VALUE, TreeItem.CELL_MODE_RANGE)
			item.set_text(COL_VALUE, "false,true")
			item.set_range(COL_VALUE, 1 if String(node.get("value", "true")) == "true" else 0)
			item.set_editable(COL_VALUE, true)
		"var":
			var names := _palette_names()
			item.set_cell_mode(COL_VALUE, TreeItem.CELL_MODE_RANGE)
			item.set_text(COL_VALUE, ",".join(names))
			item.set_range(COL_VALUE, maxi(names.find(String(node.get("value", ""))), 0))
			item.set_editable(COL_VALUE, true)
		"tuple":
			if node.get("children", []).size() < PatternTree.MAX_TUPLE:
				item.add_button(COL_VALUE, _plus_tex, BTN_ADD, false, "Add element")
		"list":
			item.add_button(COL_VALUE, _plus_tex, BTN_ADD, false, "Add element")
		_:
			pass


func _build_children(item: TreeItem, node: Dictionary, path: Array) -> void:
	match String(node.get("kind", "slot")):
		"cons":
			var ch: Array = node.get("children", [])
			_build_item(item, ch[0], "head", path + [0], false)
			_build_item(item, ch[1], "tail", path + [1], false)
		"tuple":
			var tch: Array = node.get("children", [])
			for ci in tch.size():
				_build_item(item, tch[ci], str(ci + 1), path + [ci], tch.size() > 2)
		"list":
			var lch: Array = node.get("children", [])
			for ci in lch.size():
				_build_item(item, lch[ci], str(ci + 1), path + [ci], true)


# ── Edits ─────────────────────────────────────────────────────────────────--

func _on_item_edited() -> void:
	var item := get_edited()
	if item == null:
		return
	var path: Array = item.get_metadata(COL_ROLE)
	var node := _node_at(path)
	match get_edited_column():
		COL_KIND:
			# Kind changes restructure the subtree. Rebuilding the Tree
			# from inside its own `item_edited` makes `create_item` return
			# null, so defer it to the next idle frame.
			_set_kind(node, PatternTree.KINDS[item.get_range(COL_KIND)])
			_rebuild.call_deferred()
		COL_VALUE:
			# Value-only edit: the structure is unchanged, so just sync the
			# model. For the int string cell, mirror the sanitised value
			# back (RANGE cells already display the committed selection).
			_apply_value(node, item)
			if String(node.get("kind", "")) == "int":
				item.set_text(COL_VALUE, String(node["value"]))
	_emit_branch(path[0])


func _on_button_clicked(item: TreeItem, _column: int, id: int, _mouse: int) -> void:
	var path: Array = item.get_metadata(COL_ROLE)
	match id:
		BTN_ADD:
			var node := _node_at(path)
			node["children"].append(PatternTree.make("slot"))
		BTN_REMOVE:
			var parent := _node_at(path.slice(0, path.size() - 1))
			parent["children"].remove_at(int(path[-1]))
	_rebuild.call_deferred()
	_emit_branch(path[0])


func _apply_value(node: Dictionary, item: TreeItem) -> void:
	match String(node.get("kind", "slot")):
		"int":
			var t := item.get_text(COL_VALUE).strip_edges()
			node["value"] = t if t.is_valid_int() else "0"
		"bool":
			node["value"] = "true" if int(item.get_range(COL_VALUE)) == 1 else "false"
		"var":
			var names := _palette_names()
			var idx := int(item.get_range(COL_VALUE))
			if idx >= 0 and idx < names.size():
				node["value"] = names[idx]


# Mutate `node` in place into a fresh node of `kind`, dropping any stale
# value/children so the model never carries leftovers from the old kind.
func _set_kind(node: Dictionary, kind: String) -> void:
	node.clear()
	node.merge(PatternTree.make(kind))


func _node_at(path: Array) -> Dictionary:
	var node: Dictionary = _branches[int(path[0])]
	for k in range(1, path.size()):
		node = node["children"][int(path[k])]
	return node


func _emit_branch(branch_idx: int) -> void:
	var bi := int(branch_idx)
	if bi < 0 or bi >= _branches.size():
		return
	pattern_edited.emit(bi, PatternTree.to_source(_branches[bi]))


func _palette_names() -> Array:
	var names: Array = []
	for i in IdentifierPalette.user_count():
		names.append(IdentifierPalette.name_of(i))
	return names
