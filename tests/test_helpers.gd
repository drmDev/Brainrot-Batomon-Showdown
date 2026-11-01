extends RefCounted
## TestHelpers - fakes and builders for the Brain Rot achievement tests.
##
## FakeObject exists because achievement_evaluator.gd guards with is_instance_valid(),
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

	func set_prop(property: String, value) -> void:
		_props[property] = value


## Controllable clock for deterministic time-based tests. Pass `clock.now` as the
## evaluator's second `_init` argument, then call advance() to move time forward.
class TestClock:
	extends RefCounted
	var value: int

	func _init(start_ms: int = 0) -> void:
		value = start_ms

	func advance(ms: int) -> void:
		value += ms

	func now() -> int:
		return value


## Property probe mirroring mod_main._has_property semantics for FakeObject and
## real Objects alike. Pass as the `_has_prop` Callable to the evaluator.
static func probe(obj, property: String) -> bool:
	if obj == null:
		return false
	return property in obj


## Build a mature monster fake: species key plus nullable extras used by fixtures.
## Kept separate from monster() so existing call sites stay unchanged.
static func monster_full(props: Dictionary):
	return FakeObject.new(props)


## Build a monster fake for the achievement evaluator: needs `data.name_key` and `level`.
static func monster(name_key: String, level: int = 1):
	return FakeObject.new({
		"data": FakeObject.new({"name_key": name_key}),
		"level": level,
	})


## Build a run fake for the achievement evaluator.
static func run(trainer_id: String, day: int, team: Array = [], bench: Array = []):
	return FakeObject.new({
		"trainer_id": trainer_id,
		"current_round": day,
		"team": team,
		"bench": bench,
	})


## Build a battle unit fake for poll_battle.
static func battle_unit(team_id: int, slot_index: int, shield_granted: float):
	return FakeObject.new({
		"team_id": team_id,
		"slot_index": slot_index,
		"shield_granted": shield_granted,
	})


## Build a battle state fake: state.simulation.data.battle_units + battle_over.
static func battle_state(units: Array, battle_over: bool = true):
	var data := FakeObject.new({
		"battle_units": units,
		"battle_over": battle_over,
	})
	var sim := FakeObject.new({"data": data})
	return FakeObject.new({"simulation": sim})
