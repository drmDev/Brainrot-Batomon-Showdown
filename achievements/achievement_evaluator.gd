extends RefCounted
## AchievementEvaluator - detects earned achievements from game snapshots.
##
## Rules only: this class never touches live game objects, files, or UI. It consumes
## the plain Dictionaries produced by achievements/game_snapshot_reader.gd:
##   poll(run_snapshot)            -> Array of newly earned achievement dictionaries
##   poll_battle(battle_snapshot)  -> Array of newly earned achievement dictionaries
## Both return an empty Array most polls. The caller owns persistence
## (achievement_store) and display (achievement_panel).
##
## Definitions live in catalog/brain_rot_catalog.gd. Each achievement entry lists
## one or more `rules`; this file dispatches on the rule name and keeps the stateful
## logic typed here. Adding a simple achievement is one catalog block; a new rule
## shape adds one handler below.
##
## Snapshot contract (see game_snapshot_reader.gd): unknown values are ABSENT keys.
## Defaults live here, in the rules: a monster without "level" counts as level 1, and
## a run without "trainer_id" has no trainer.
##
## Rules:
## - RULE_GENTLEMAN_RHIZUKA (run): a level-2 Rhizuka (the trainer's common level-2
##   strat) is owned no later than Day 5. Day is the snapshot's current_round.
## - RULE_TWINS_EVOLUTION (run): a level-2 pre-evolution evolves into its level-3
##   form. Twins doubles the leveled unit, so the evolution produces two level-3
##   units. The rule's `post_key` names the evolved species.
## - RULE_GALVANINE_SHOCK (battle): a single Galvanine unit inflicts 1000+ shock in
##   one battle.
## - RULE_CINNABARK_SHIELD (battle): a single Cinnabark unit generates more than
##   1,000,000 shield in one battle. Evaluated once the battle is over (the detector
##   decides when), so the toast lands on the results screen.
##
## Occurrence: tracked per (achievement id, rule name). An achievement is considered
## awarded when any of its rules has fired. Entries with `track: false` are stateless
## (the caller owns once-per-battle semantics).

const Catalog = preload("../catalog/brain_rot_catalog.gd")

const TWINS_TRAINER_ID := "twins"
const BEETDOWN_KEY := "monster.name.beetdown"
const DEWLOTL_KEY := "monster.name.dewlotl"
const EVOLVED_LEVEL := 3      # Twins double-evolution produces level-3 units
const EVOLUTION_COPIES := 1   # One level-3 evolved unit is enough (Twins grants the copy)

const GENTLEMAN_TRAINER_ID := "gentleman"
const RHIZUKA_KEY := "monster.name.rhizuka"
const RHIZUKA_MIN_LEVEL := 2   # The level-2 Rhizuka strat
const GENTLEMAN_DAY_LIMIT := 5  # Latest day the level-2 Rhizuka still counts

const CINNABARK_KEY := "monster.name.cinnabark"
const GALVANINE_KEY := "monster.name.galvanine"
const GALVANINE_SHOCK_THRESHOLD := 1000  # At least this much shock in one battle
const PLAYER_TEAM_ID := 0  # battle_units team_id used for the player's side
const BIG_DOG_SHIELD_THRESHOLD := 1000000.0  # Strictly over one million shield

# Awarded this run, keyed by "<achievement id>|<rule name>".
var _awarded: Dictionary = {}


## Poll a run snapshot for newly earned achievements. Returns an Array of achievement
## dictionaries (empty most polls).
func poll(run_snapshot: Dictionary) -> Array:
	if run_snapshot.is_empty():
		_reset()
		return []

	var trainer_id := str(run_snapshot.get("trainer_id", ""))
	var is_gentleman := trainer_id == GENTLEMAN_TRAINER_ID
	var is_twins := trainer_id == TWINS_TRAINER_ID
	if not is_gentleman and not is_twins:
		_reset()
		return []

	var owned := _collect_owned_species(run_snapshot)
	var earned: Array = []

	for entry in Catalog.achievements():
		var id := str(entry.get("id", ""))
		if id.is_empty() or _is_awarded(entry):
			continue
		for rule in entry.get("rules", []):
			if str(rule.get("scope", "")) != Catalog.SCOPE_RUN:
				continue
			if not _run_rule_applies(str(rule.get("name", "")), is_gentleman, is_twins):
				continue
			if _run_rule_matches(rule, run_snapshot, owned):
				_mark_awarded(id, str(rule.get("name", "")))
				earned.append(_award_payload(entry))
				break

	# Preserve the original reset behavior: a trainer that cannot use a rule clears
	# that rule's awards so a later run with the same trainer can award again.
	if not is_gentleman:
		_clear_awards_for_rule(Catalog.RULE_GENTLEMAN_RHIZUKA)
	if not is_twins:
		_clear_awards_for_rule(Catalog.RULE_TWINS_EVOLUTION)

	return earned


## Poll a completed battle snapshot for battle-scoped achievements. Returns newly
## earned achievement dictionaries.
##
## The caller (battle_completion_detector + mod_main) decides WHEN this runs: once per
## completed battle, with a usable snapshot. This function is a pure rule check.
func poll_battle(battle_snapshot: Dictionary) -> Array:
	if battle_snapshot.is_empty():
		return []
	if not bool(battle_snapshot.get("battle_over", false)):
		return []

	var earned: Array = []
	for entry in Catalog.achievements():
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var tracked := bool(entry.get("track", true))
		if tracked and _is_awarded(entry):
			continue
		for rule in entry.get("rules", []):
			if str(rule.get("scope", "")) != Catalog.SCOPE_BATTLE:
				continue
			if _battle_rule_matches(rule, battle_snapshot):
				if tracked:
					_mark_awarded(id, str(rule.get("name", "")))
				earned.append(_award_payload(entry))
				break
	return earned


## Clear all run-scoped tracking. Call at a verified run transition so consecutive
## runs with the same trainer cannot retain flags or baselines.
func reset_run() -> void:
	_reset()


func _reset() -> void:
	_awarded.clear()


## Does this rule apply to the current trainer? Run rules are trainer-gated.
func _run_rule_applies(rule_name: String, is_gentleman: bool, is_twins: bool) -> bool:
	match rule_name:
		Catalog.RULE_GENTLEMAN_RHIZUKA:
			return is_gentleman
		Catalog.RULE_TWINS_EVOLUTION:
			return is_twins
	return false


## Does a run-scoped rule match the snapshot?
func _run_rule_matches(rule: Dictionary, run_snapshot: Dictionary, owned: Dictionary) -> bool:
	match str(rule.get("name", "")):
		Catalog.RULE_GENTLEMAN_RHIZUKA:
			return _matches_gentleman_rhizuka(run_snapshot, owned)
		Catalog.RULE_TWINS_EVOLUTION:
			return _matches_twins_evolution(rule, owned)
	return false


## Does a battle-scoped rule match the snapshot?
func _battle_rule_matches(rule: Dictionary, battle_snapshot: Dictionary) -> bool:
	match str(rule.get("name", "")):
		Catalog.RULE_GALVANINE_SHOCK:
			return _max_galvanine_shock(battle_snapshot) >= GALVANINE_SHOCK_THRESHOLD
		Catalog.RULE_CINNABARK_SHIELD:
			return _max_cinnabark_unit_shield(battle_snapshot) > BIG_DOG_SHIELD_THRESHOLD
	return false


## Gentleman: owns a level-2 Rhizuka on Day 5 or earlier.
func _matches_gentleman_rhizuka(run_snapshot: Dictionary, owned: Dictionary) -> bool:
	var day := int(run_snapshot.get("current_round", -1))
	if day < 1 or day > GENTLEMAN_DAY_LIMIT:
		return false

	var record: Dictionary = owned.get(RHIZUKA_KEY, {})
	var levels: Dictionary = record.get("levels", {})
	for level in levels:
		if int(level) >= RHIZUKA_MIN_LEVEL:
			return true
	return false


## Twins: owns a level-3 evolved unit named by the rule's `post_key`.
func _matches_twins_evolution(rule: Dictionary, owned: Dictionary) -> bool:
	var post_key := str(rule.get("post_key", ""))
	if post_key.is_empty():
		return false
	var record: Dictionary = owned.get(post_key, {})
	var levels: Dictionary = record.get("levels", {})
	return int(levels.get(EVOLVED_LEVEL, 0)) >= EVOLUTION_COPIES


## Highest shock inflicted by a SINGLE player-side Galvanine unit record.
func _max_galvanine_shock(battle_snapshot: Dictionary) -> int:
	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return 0
	var team = battle_snapshot.get("team")
	if not team is Array:
		return 0

	var best := 0
	for unit in units:
		if not unit is Dictionary:
			continue
		if not unit.has("team_id") or not unit.has("slot_index") or not unit.has("shock_inflicted"):
			continue
		if int(unit.get("team_id")) != PLAYER_TEAM_ID:
			continue
		var slot := int(unit.get("slot_index"))
		if slot < 0 or slot >= team.size():
			continue
		if _monster_species_key(team[slot]) != GALVANINE_KEY:
			continue
		best = maxi(best, int(unit.get("shock_inflicted")))
	return best


## Highest shield generated by a SINGLE player-side Cinnabark unit record.
## The fight is simulated up front, so these totals are final by the time it is over.
func _max_cinnabark_unit_shield(battle_snapshot: Dictionary) -> float:
	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return 0.0

	var team = battle_snapshot.get("team")
	if not team is Array:
		return 0.0

	var best := 0.0
	for unit in units:
		if not unit is Dictionary:
			continue
		if not unit.has("team_id") or not unit.has("slot_index") or not unit.has("shield_granted"):
			continue
		var shield = unit.get("shield_granted")
		if shield == null:
			continue
		if int(unit.get("team_id")) != PLAYER_TEAM_ID:
			continue
		var slot := int(unit.get("slot_index"))
		if slot < 0 or slot >= team.size():
			continue
		if _monster_species_key(team[slot]) != CINNABARK_KEY:
			continue
		best = maxf(best, float(shield))
	return best


## Award key for one (achievement, rule) pair.
func _award_key(id: String, rule_name: String) -> String:
	return "%s|%s" % [id, rule_name]


## Has any rule of this achievement already fired this run?
func _is_awarded(entry: Dictionary) -> bool:
	var id := str(entry.get("id", ""))
	for rule in entry.get("rules", []):
		if _awarded.has(_award_key(id, str(rule.get("name", "")))):
			return true
	return false


func _mark_awarded(id: String, rule_name: String) -> void:
	_awarded[_award_key(id, rule_name)] = true


## Clear every award produced by one rule, leaving other rules' awards intact.
func _clear_awards_for_rule(rule_name: String) -> void:
	var suffix := "|" + rule_name
	for key in _awarded.keys():
		if str(key).ends_with(suffix):
			_awarded.erase(key)


## The dictionary shape the caller persists and displays.
func _award_payload(entry: Dictionary) -> Dictionary:
	return {
		"id": str(entry.get("id", "")),
		"title": str(entry.get("title", "")),
		"description": str(entry.get("description", "")),
	}


## One pass over team + bench: species key -> {"count": int, "levels": {level: count}}.
func _collect_owned_species(run_snapshot: Dictionary) -> Dictionary:
	var species := {}
	for list_name in ["team", "bench"]:
		var list = run_snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			var key := _monster_species_key(monster)
			if key.is_empty():
				continue
			var level := int(monster.get("level", 1)) if monster is Dictionary else 1
			var record: Dictionary = species.get(key, {"count": 0, "levels": {}})
			record["count"] = int(record["count"]) + 1
			var levels: Dictionary = record["levels"]
			levels[level] = int(levels.get(level, 0)) + 1
			species[key] = record
	return species


## Species name_key of a snapshot monster entry, or "" when unavailable.
func _monster_species_key(monster) -> String:
	if not monster is Dictionary:
		return ""
	return str(monster.get("name_key", ""))
