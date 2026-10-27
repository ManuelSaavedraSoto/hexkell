class_name Env
extends RefCounted
## Immutable, persistent environment for the interpreter.
##
## Each environment is a linked list of frames, where each frame contains a dictionary of bindings.

var parent: Env = null
var bindings: Dictionary[String, Value] = {}
var cache: Dictionary[String, Value] = {}


func _init(p_parent: Env = null, p_bindings: Dictionary[String, Value] = {}) -> void:
	parent = p_parent
	bindings = p_bindings


static func root() -> Env:
	return Env.new()


## Push an empty frame.
func fork() -> Env:
	return Env.new(self)


## Define in the current (top) frame by copying only this frame's bindings.
func define_local(name: String, value: Value) -> Env:
	var new_bindings = bindings.duplicate()
	new_bindings[name] = value
	return Env.new(parent, new_bindings)


## Define in the current frame multiple bindings.
func define_local_batch(new_bindings: Dictionary[String, Value]) -> Env:
	var merged_bindings = bindings.duplicate()
	merged_bindings.merge(new_bindings)
	return Env.new(parent, merged_bindings)


## Push a new frame that contains this binding; does not copy existing frames.
func define_in_new_frame(name: String, value: Value) -> Env:
	return Env.new(self, {name: value})


## Push a new frame that contains multiple bindings; does not copy existing frames.
func define_in_new_frame_batch(new_bindings: Dictionary[String, Value]) -> Env:
	return Env.new(self, new_bindings)


## Check if this frame is the root.
func is_root() -> bool:
	return parent == null


## Check if this environment has no bindings (iteratively checks parents).
func is_empty() -> bool:
	if not is_root():
		var cur: Env = self
		while cur != null:
			
			if not cur.bindings.is_empty():
				return false
			
			cur = cur.parent

	return true


## Check if the current frame has any bindings.
func is_frame_empty() -> bool:
	return bindings.is_empty()


## Check if a binding exists in this environment or any parent.
func has(name: String) -> bool:
	var cur: Env = self
	while cur != null:
		if cur.bindings.has(name) or cur.cache.has(name):
			return true
		
		cur = cur.parent
	
	return false


## Look up a binding by name, searching parent frames if needed.
## Caches the value if it looked into the parent to speed up future searches.
## Returns value or null when not found.
func lookup(name: String):
	var cur: Env = self
	var path: Array[Env] = []
	
	while cur != null:
		if cur.bindings.has(name):
			var val = cur.bindings[name]
			for e in path:
				e.cache[name] = val
			return cur.bindings[name]
		elif cur.cache.has(name):
			var val = cur.cache[name]
			for e in path:
				e.cache[name] = val
			return cur.cache[name]
		
		path.append(cur)
		cur = cur.parent
	
	return null


## Update the nearest existing binding. If not found, define in current frame.
func set_binding(name: String, value) -> Env:
	var result = _assoc_set(self, name, value)
	if result.size() == 2 and result[1]:
		return result[0]
	# Not found: define in current frame (copy current frame only).
	return define_local(name, value)


## Utility method to replace the root of this environment with a new one.
func set_new_root(env: Env) -> void:
	var cur: Env = self
	while cur.parent != null:
		cur = cur.parent
	cur.parent = env


## Returns [new_node, true] when updated, or [null, false] when not found in this subtree.
func _assoc_set(node: Env, name: String, value) -> Array:
	if node.bindings.has(name):
		var new_bindings = node.bindings.duplicate()
		new_bindings[name] = value
		return [Env.new(node.parent, new_bindings), true]
	if node.parent == null:
		return [null, false]
	var parent_result = _assoc_set(node.parent, name, value)
	if parent_result.size() == 2 and parent_result[1]:
		# Rebuild this node with the updated parent while reusing this node's bindings.
		return [Env.new(parent_result[0], node.bindings), true]
	return [null, false]


## Produce a single Dictionary with visible bindings (top-most shadows lower frames).
func to_flat_dictionary() -> Dictionary:
	var out: Dictionary = {}
	var cur: Env = self
	while cur != null:
		for k in cur.bindings.keys():
			if not out.has(k):
				out[k] = cur.bindings[k]
		cur = cur.parent
	return out


## Utility methods for debugging and introspection.
func keys() -> Array:
	return to_flat_dictionary().keys()


func debug_repr() -> String:
	return str(to_flat_dictionary())
