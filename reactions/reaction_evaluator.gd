extends RefCounted
## ReactionEvaluator - detects "reactions" from game snapshots.
##
## Rules only: consumes the plain snapshots produced by
## achievements/game_snapshot_reader.gd and returns newly triggered reaction
## dictionaries. It never touches live game objects, files, UI, or the achievement
## store, so a completed achievement can never suppress a reaction.
##
##   poll(run_snapshot)            -> run-scoped reactions
##   poll_battle(battle_snapshot)  -> battle-scoped reactions
##   reset_run()                   -> clear everything for a new run
##   reset_battle()                -> clear battle-scoped tracking for a new battle
##
## Each returned reaction is {"id": String, "detail": String}.
##
## Reaction definitions live in reactions/reaction_definitions.gd. This file only
## evaluates them; adding a reaction is one block in that file.
##
## Occurrence semantics:
## - Run-scoped: triggers once per run, the first time a matching snapshot is seen.
##   Repeated matching polls, leaving and returning, and a menu round-trip (run
##   unavailable) do not retrigger. Only reset_run() clears it.
## - Battle-scoped: evaluated only on the FINAL battle totals (battle_over), never
##   mid-fight. Each battle reaction fires at most ONCE per battle, even when several
##   units qualify: the lowest slot wins, and within that slot the first metric in
##   BATTLE_METRIC_ORDER. Different battle reactions are tracked independently, so
##   several of them can fire in the same battle.
## - Outcome-scoped: evaluated only at battle_over from the battle snapshot's
##   `outcome` (the committed promoted-run totals). Occurrence is run-scoped, so
##   reset_battle() does not re-arm it.
## - An empty snapshot does NOT reset anything.
##
## LIMITATION: occurrence tracking is session-only. Restarting the game or the mod
## can allow a reaction to trigger again within a continuing run.

const ReactionDefinitions = preload("reaction_definitions.gd")

# Evaluation scope labels for registered_rows() (dev tooling / catalog).
const SCOPE_RUN := ReactionDefinitions.SCOPE_RUN
const SCOPE_BATTLE := ReactionDefinitions.SCOPE_BATTLE
const SCOPE_OUTCOME := ReactionDefinitions.SCOPE_OUTCOME

const PLAYER_TEAM_ID := 0  # battle_units team_id used for the player's side


## Every registered trigger with its evaluation scope. Dev tooling and schema
## tests iterate this so a new definition cannot be forgotten.
static func registered_rows() -> Array:
	var rows: Array = []
	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		for trigger in definition.get("triggers", []):
			var row: Dictionary = trigger.duplicate()
			row["id"] = id
			rows.append({"scope": str(trigger.get("scope", "")), "row": row})
	return rows


# Run-scoped occurrence count per reaction id. Presence means "already triggered".
var _occurrences: Dictionary = {}
# Battle-scoped: reaction ids that already fired for the current battle.
var _battle_fired: Dictionary = {}


## Poll a run snapshot. Returns newly triggered run-scoped reactions (empty most polls).
func poll(run_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if run_snapshot.is_empty():
		return triggered

	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		if id.is_empty() or _occurrences.has(id):
			continue
		var details: PackedStringArray = []
		for trigger in definition.get("triggers", []):
			if str(trigger.get("scope", "")) != SCOPE_RUN:
				continue
			var detail := _conditions_detail(
				trigger.get("when", []),
				run_snapshot,
				ReactionDefinitions.FIELDS,
			)
			if not detail.is_empty():
				details.append(detail)
		if details.is_empty():
			continue
		_occurrences[id] = 1
		triggered.append({
			"id": id,
			"detail": _format_detail(definition, ", ".join(details)),
		})
	return triggered


## Poll a completed battle snapshot. Returns at most one reaction per battle
## reaction id: the lowest player-side slot with a metric satisfying that
## reaction's comparison. Mid-battle snapshots never match.
func poll_battle(battle_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if battle_snapshot.is_empty():
		return triggered
	if not bool(battle_snapshot.get("battle_over", false)):
		return triggered

	var units = battle_snapshot.get("battle_units")
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []

	if units is Array:
		for definition in ReactionDefinitions.DEFINITIONS:
			var id := str(definition.get("id", ""))
			if id.is_empty() or _battle_fired.has(id):
				continue
			for trigger in definition.get("triggers", []):
				if str(trigger.get("scope", "")) != SCOPE_BATTLE:
					continue
				var found := _find_battle_match(units, trigger)
				if found.is_empty():
					continue
				_battle_fired[id] = true
				var detail := "%s %s %d" % [
					_species_display_name_at(team, int(found.get("slot", -1))),
					str(found.get("label", "")),
					int(found.get("value", 0)),
				]
				triggered.append({
					"id": id,
					"detail": _format_detail(definition, detail),
				})
				break

	_poll_battle_outcomes(triggered, battle_snapshot)
	return triggered


## Append outcome-based reactions from the committed post-battle totals. Requires
## battle_over (poll_battle already checked) and integer wins/lives. Occurrence is
## run-scoped, so the same run cannot fire it twice and reset_battle() keeps it armed.
func _poll_battle_outcomes(triggered: Array, battle_snapshot: Dictionary) -> void:
	var outcome = battle_snapshot.get("outcome")
	if not outcome is Dictionary:
		return
	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		if id.is_empty() or _occurrences.has(id):
			continue
		for trigger in definition.get("triggers", []):
			if str(trigger.get("scope", "")) != SCOPE_OUTCOME:
				continue
			var detail := _conditions_detail(
				trigger.get("when", []),
				outcome,
				ReactionDefinitions.OUTCOME_FIELDS,
			)
			if detail.is_empty():
				continue
			_occurrences[id] = 1
			triggered.append({
				"id": id,
				"detail": _format_detail(definition, detail),
			})
			break


## Clear all tracking. Call at a verified run transition.
func reset_run() -> void:
	_occurrences.clear()
	_battle_fired.clear()


## Clear battle-scoped tracking. Call when entering a new battle.
func reset_battle() -> void:
	_battle_fired.clear()


## How many times this run-scoped reaction has triggered in the current run (0 or 1).
func occurrence_count(id: String) -> int:
	return int(_occurrences.get(id, 0))


## Apply a definition's optional message template to a generated detail line.
func _format_detail(definition: Dictionary, detail: String) -> String:
	var message := str(definition.get("message", ""))
	if message.is_empty():
		return detail
	return message.replace("{detail}", detail)


## "Sunsage level 3" when the owned team or bench contains a matching unit, else "".
func _owns_detail(spec, snapshot: Dictionary) -> String:
	if not spec is Dictionary:
		return ""
	var species := str(spec.get("species", ""))
	var level_condition = spec.get("level")
	for list_name in ["team", "bench"]:
		var list = snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if not monster is Dictionary:
				continue
			if str(monster.get("name_key", "")) != species:
				continue
			var level = monster.get("level")
			if typeof(level) != TYPE_INT:
				continue
			if level_condition is Array and level_condition.size() == 2:
				if not _compare(int(level), str(level_condition[0]), int(level_condition[1])):
					continue
			return "%s level %d" % [_format_species_name(species), int(level)]
	return ""


## Detail line for a `when` list, or "" when the conditions do not match.
##
## Conditions are ANDed. A leaf contributes "<Label> <actual>" to the detail. An
## `any` block matches when at least one leaf matches and contributes every
## matching leaf, so "Lives 6, Day 7, Wins 7" is produced when both day and wins
## match. Numeric fields must be present ints; anything else does not match.
func _conditions_detail(conditions, snapshot: Dictionary, fields: Dictionary) -> String:
	if not conditions is Array:
		return ""
	var parts: PackedStringArray = []
	for condition in conditions:
		if condition is Dictionary and condition.has("any"):
			var any_list = condition["any"]
			if not any_list is Array:
				return ""
			var any_parts: PackedStringArray = []
			for sub in any_list:
				if sub is Array:
					var text := _leaf_detail(sub, snapshot, fields)
					if not text.is_empty():
						any_parts.append(text)
			if any_parts.is_empty():
				return ""
			parts.append_array(any_parts)
		elif condition is Dictionary and condition.has("owns"):
			var text := _owns_detail(condition["owns"], snapshot)
			if text.is_empty():
				return ""
			parts.append(text)
		elif condition is Array:
			var text := _leaf_detail(condition, snapshot, fields)
			if text.is_empty():
				return ""
			parts.append(text)
		else:
			return ""
	return ", ".join(parts)


## "<Label> <actual>" for a matching leaf, or "" when it does not match.
func _leaf_detail(condition: Array, snapshot: Dictionary, fields: Dictionary) -> String:
	if condition.size() != 3:
		return ""
	var field := str(condition[0])
	var op := str(condition[1])
	var info = fields.get(field)
	if not info is Dictionary:
		return ""
	var key := str(info.get("key", ""))
	var label := str(info.get("label", field))
	if str(info.get("type", "int")) == "string":
		var actual = snapshot.get(key)
		if typeof(actual) != TYPE_STRING:
			return ""
		if not _compare_string(str(actual), op, str(condition[2])):
			return ""
		return "%s %s" % [label, str(actual)]
	var actual = snapshot.get(key)
	if typeof(actual) != TYPE_INT:
		return ""
	if not _compare(int(actual), op, int(condition[2])):
		return ""
	return "%s %d" % [label, int(actual)]


## The one comparison implementation shared by every scope. Unknown ops warn and
## never match, so a typo cannot silently behave as equality.
func _compare(actual: int, op: String, expected: int) -> bool:
	match op:
		ReactionDefinitions.OP_EQUALS:
			return actual == expected
		ReactionDefinitions.OP_NOT_EQUALS:
			return actual != expected
		ReactionDefinitions.OP_GREATER_THAN:
			return actual > expected
		ReactionDefinitions.OP_GREATER_OR_EQUAL:
			return actual >= expected
		ReactionDefinitions.OP_LESS_THAN:
			return actual < expected
		ReactionDefinitions.OP_LESS_OR_EQUAL:
			return actual <= expected
	push_warning("Brain Rot: unknown reaction comparison '%s'" % op)
	return false


## String comparison for string fields. Only eq/ne are meaningful.
func _compare_string(actual: String, op: String, expected: String) -> bool:
	match op:
		ReactionDefinitions.OP_EQUALS:
			return actual == expected
		ReactionDefinitions.OP_NOT_EQUALS:
			return actual != expected
	push_warning("Brain Rot: unsupported string comparison '%s'" % op)
	return false


## Lowest player-side slot with a metric satisfying `trigger`, plus the first
## matching metric label in BATTLE_METRIC_ORDER and the actual total. Returns {}
## when nothing matches.
func _find_battle_match(units: Array, trigger: Dictionary) -> Dictionary:
	var total_condition = trigger.get("total")
	if not total_condition is Array or total_condition.size() != 2:
		return {}
	var op := str(total_condition[0])
	var expected := int(total_condition[1])
	var metric_labels = trigger.get("metrics")
	if not metric_labels is Array:
		metric_labels = ReactionDefinitions.BATTLE_METRIC_ORDER

	var best_slot := -1
	var best_label := ""
	var best_value := 0
	for unit in units:
		if not unit is Dictionary:
			continue
		var team_id = unit.get("team_id")
		if typeof(team_id) != TYPE_INT or int(team_id) != PLAYER_TEAM_ID:
			continue
		var slot_value = unit.get("slot_index")
		if typeof(slot_value) != TYPE_INT:
			continue
		var slot := int(slot_value)
		# A lower slot already matched, so this unit cannot win.
		if best_slot >= 0 and slot >= best_slot:
			continue
		for label in ReactionDefinitions.BATTLE_METRIC_ORDER:
			if not metric_labels.has(label):
				continue
			var key := str(ReactionDefinitions.BATTLE_METRICS.get(label, ""))
			var value = unit.get(key)
			# The reader emits floats for battle counters (e.g. heal=420.0), so
			# accept both numeric types and compare the integer total.
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				continue
			if _compare(int(value), op, expected):
				best_slot = slot
				best_label = label
				best_value = int(value)
				break
	if best_slot < 0:
		return {}
	return {"slot": best_slot, "label": best_label, "value": best_value}


## Display name of the species in a team slot, or "Unknown" when unavailable.
func _species_display_name_at(team: Array, slot: int) -> String:
	if slot < 0 or slot >= team.size():
		return "Unknown"
	var entry = team[slot]
	if not entry is Dictionary:
		return "Unknown"
	var key := str(entry.get("name_key", ""))
	return _format_species_name(key) if not key.is_empty() else "Unknown"


## Species key -> display name ("monster.name.beetdown" -> "Beetdown").
## Mirrors Creature Comforts' log_formatter.format_species_name: prefer a
## TranslationServer entry, then strip the key prefix and capitalize.
func _format_species_name(species_key: String) -> String:
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(species_key)
		if translated != species_key:
			return translated
	var name_key := species_key
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	return name_key.capitalize()
