extends RefCounted
## HighScores - persistent per-metric best single-unit battle values.
##
## The store is a versioned JSON dictionary:
##   {
##     "version": 1,
##     "metrics": {
##       "damage": {"value": int, "unit": String},  # unit is a species name_key
##       ...
##     }
##   }
##
## record_battle() computes the best single-unit value for each metric on the
## player's team and records the unit that achieved it. It is idempotent (max),
## so re-processing the same battle cannot lower a score. The store is global
## across runs and is written only when a metric improves.
##
## Adapted from Creature Comforts (core/saved_builds.gd) for the JSON load/save
## pattern; the metric set comes from catalog/brain_rot_catalog.gd.

const Catalog = preload("../catalog/brain_rot_catalog.gd")

const PATH := "user://brain_rot/high_scores.json"
const VERSION := 1
const PLAYER_TEAM_ID := 0


static func empty_store() -> Dictionary:
	return {"version": VERSION, "metrics": {}}


## Parse a store from JSON text. Missing, corrupt, or wrongly typed data yields an
## empty store. Legacy integer metric values are accepted and normalized to the
## {"value", "unit"} shape.
static func parse(text: String) -> Dictionary:
	var store := empty_store()
	if text.strip_edges().is_empty():
		return store
	var json := JSON.new()
	if json.parse(text) != OK:
		return store
	var parsed = json.data
	if not parsed is Dictionary:
		return store
	var raw_metrics = parsed.get("metrics")
	if not raw_metrics is Dictionary:
		return store
	var metrics := {}
	for label in Catalog.BATTLE_METRIC_ORDER:
		var entry := _normalize_metric(raw_metrics.get(label))
		if not entry.is_empty():
			metrics[label] = entry
	store["metrics"] = metrics
	return store


static func serialize(store: Dictionary) -> String:
	return JSON.stringify(store, "\t")


static func load_store(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty_store()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Brain Rot: cannot read high scores at %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return empty_store()
	var text := file.get_as_text()
	file.close()
	return parse(text)


static func save_store(store: Dictionary, path: String = PATH) -> bool:
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Brain Rot: cannot create high-score directory %s: %s" % [abs_dir, error_string(dir_err)])
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Brain Rot: cannot write high scores to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(serialize(store))
	file.close()
	return true


## Best single-unit value per metric for the player's team, plus the unit that
## achieved it. Returns a Dictionary of improved metrics (empty when nothing
## improved or the snapshot is not a completed battle). Mutates `store` in place.
static func record_battle(store: Dictionary, battle_snapshot: Dictionary) -> Dictionary:
	var improved := {}
	if not bool(battle_snapshot.get("battle_over", false)):
		return improved
	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return improved
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []

	var best := {}
	for unit in units:
		if not unit is Dictionary:
			continue
		if int(unit.get("team_id", -1)) != PLAYER_TEAM_ID:
			continue
		var slot := int(unit.get("slot_index", -1))
		var unit_key := _unit_name_key(team, slot)
		for label in Catalog.BATTLE_METRIC_ORDER:
			var key := str(Catalog.BATTLE_METRICS.get(label, ""))
			var value = unit.get(key)
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				continue
			var actual := int(value)
			if actual > int(best.get(label, {}).get("value", 0)):
				best[label] = {"value": actual, "unit": unit_key}

	var metrics = store.get("metrics")
	if not metrics is Dictionary:
		metrics = {}
		store["metrics"] = metrics
	for label in best:
		var value := int(best[label]["value"])
		var unit := str(best[label]["unit"])
		var previous := 0
		var existing = metrics.get(label)
		if existing is Dictionary:
			previous = int(existing.get("value", 0))
		elif existing is int or existing is float:
			previous = int(existing)
		if value > previous:
			metrics[label] = {"value": value, "unit": unit}
			improved[label] = {"value": value, "previous": previous, "unit": unit}
	return improved


## Abbreviate a large number for display: 1,000,000+ -> "1.0M", 1,000+ -> "1.0K".
static func format_value(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (float(value) / 1000.0)
	return str(value)


## Species name_key -> display name ("monster.name.cinnabark" -> "Cinnabark").
## Mirrors the reaction evaluator's species formatting.
static func format_unit(name_key: String) -> String:
	if name_key.is_empty():
		return "Unknown"
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(name_key)
		if translated != name_key:
			return translated
	var key := name_key
	if "." in key:
		key = key.split(".")[-1]
	return key.capitalize()


static func _normalize_metric(raw) -> Dictionary:
	var value := 0
	var unit := ""
	if raw is Dictionary:
		var raw_value = raw.get("value")
		if raw_value is int or raw_value is float:
			value = int(raw_value)
		unit = str(raw.get("unit", ""))
	elif raw is int or raw is float:
		value = int(raw)
	if value <= 0:
		return {}
	return {"value": value, "unit": unit}


static func _unit_name_key(team: Array, slot: int) -> String:
	if slot < 0 or slot >= team.size():
		return ""
	var entry = team[slot]
	if not entry is Dictionary:
		return ""
	return str(entry.get("name_key", ""))
