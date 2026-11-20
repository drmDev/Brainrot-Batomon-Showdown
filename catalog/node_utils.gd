extends RefCounted
## Scene-tree reflection helpers shared by the mod's modules.
##
## Adapted from Creature Comforts (core/node_utils.gd). Brain Rot stays
## standalone, so this is a copy, not a runtime dependency.

## True when `obj` exposes `property`. Handles both Objects and Dictionaries.
## `in` is O(1) and avoids allocating the full property list on every call.
static func has_property(obj, property: String) -> bool:
	if obj == null:
		return false
	if obj is Dictionary:
		return obj.has(property)
	if not is_instance_valid(obj):
		return false
	return property in obj


## True when `obj`'s script (or any base script) is `script_path`.
static func script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


## The SceneTree root, or null outside an active scene tree (a headless
## --script run, e.g. the test suite, has a detached root).
static func get_root():
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	var root: Window = (tree as SceneTree).root
	if root == null or not root.is_inside_tree():
		return null
	return root


## An autoload node by name (e.g. "GameDatabase"), or null when unavailable.
static func get_autoload(autoload_name: String):
	var root = get_root()
	if root == null:
		return null
	return root.get_node_or_null("/root/" + autoload_name)