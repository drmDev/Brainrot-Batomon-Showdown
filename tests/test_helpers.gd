extends RefCounted
## TestHelpers - fakes and builders for the Brain Rot tests.
##
## FakeObject exists because the snapshot reader guards with is_instance_valid(),
## which returns false for Dictionaries. Fakes must be Object instances (RefCounted).


## RefCounted whose properties are backed by a Dictionary. Works with the probe
## callable below (which uses the `in` operator, consulting _has/_get).
class FakeObject:
	extends RefCounted
	var _props: Dictionary

	func _init(props: Dictionary = {}) -> void:
		_props = props

	func _get(property: StringName):
		return _props.get(property)

	func _has(property: StringName) -> bool:
		return _props.has(property)


## Property probe mirroring mod_main._has_property semantics for FakeObject and
## real Objects alike. Pass as the `_has_prop` Callable to the evaluator.
static func probe(obj, property: String) -> bool:
	if obj == null:
		return false
	return property in obj


## Build a monster fake for the snapshot reader: needs `data.name_key` and `level`.
## Set `is_shiny` true to expose the game's `is_shiny` property.
static func monster(name_key: String, level: int = 1, is_shiny: bool = false, perm_buffs: Dictionary = {}):
	var props := {
		"data": FakeObject.new({"name_key": name_key}),
		"level": level,
	}
	if is_shiny:
		props["is_shiny"] = true
	if not perm_buffs.is_empty():
		props["_permanent_buffs"] = perm_buffs
	return FakeObject.new(props)


## Build a run fake for the snapshot reader. `trinket_ids` is exposed as the
## run's held trinkets (the reader derives trinket_count from it).
static func run(trainer_id: String, day: int, team: Array = [], bench: Array = [], trinket_ids: Array = []):
	return FakeObject.new({
		"trainer_id": trainer_id,
		"current_round": day,
		"team": team,
		"bench": bench,
		"trinket_ids": trinket_ids,
	})


## Build a battle unit fake for the snapshot reader tests.
static func battle_unit(team_id: int, slot_index: int, shield_granted: float):
	return FakeObject.new({
		"team_id": team_id,
		"slot_index": slot_index,
		"shield_granted": shield_granted,
	})


## Build a battle unit fake with accumulated metrics (any subset of damage_dealt,
## healing_done, shield_granted, burn_inflicted, poison_inflicted, shock_inflicted).
static func battle_unit_metrics(team_id: int, slot_index: int, props: Dictionary = {}):
	var base := {"team_id": team_id, "slot_index": slot_index}
	base.merge(props, true)
	return FakeObject.new(base)


## Build a battle state fake: state.simulation.data.battle_units + battle_over.
## `extra` is merged into simulation.data (e.g. {"time_elapsed": 12.3}).
static func battle_state(units: Array, battle_over: bool = true, extra: Dictionary = {}):
	var props := {
		"battle_units": units,
		"battle_over": battle_over,
	}
	props.merge(extra, true)
	var data := FakeObject.new(props)
	var sim := FakeObject.new({"data": data})
	return FakeObject.new({"simulation": sim})
