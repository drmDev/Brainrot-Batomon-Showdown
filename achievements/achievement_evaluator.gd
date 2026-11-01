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
## Snapshot contract (see game_snapshot_reader.gd): unknown values are ABSENT keys.
## Defaults live here, in the rules: a monster without "level" counts as level 1, and
## a run without "trainer_id" has no trainer.
##
## Achievements:
## - "So I started blasting" (poll, run snapshot)
##   Trainer: Gentleman
##   Trigger: a level-2 Rhizuka (the trainer's common level-2 strat) is owned no later
##   than Day 5. Day is read from the snapshot's current_round (the field the mod
##   already logs as "Day"). State-based: awards as soon as the condition is true.
## - "Oh Yeah!" / "Herd U Liek Mudkipz" (poll, run snapshot)
##   Trainer: Twins
##   Trigger: a level-2 pre-evolution evolves into its level-3 form. Twins doubles the
##   leveled unit, so the evolution produces two level-3 units.
##     Beetbud (level 2) -> Beetdown (level 3)      -> "Oh Yeah!"
##     Frillet (level 2) -> Dewlotl (level 3)       -> "Herd U Liek Mudkipz"
##   Detection arms when the level-2 pre-evolution is seen and awards when the evolved
##   count rises by at least 2 from that baseline. The game can apply the Twins double
##   across several polls (see the runtime log: one Dewlotl appears, then the second on
##   the next poll), so the baseline stays armed for a short window instead of requiring
##   both copies in one poll. Arming avoids awarding on a plain purchase.
## - "Big Dog, Best Dog" (poll_battle, battle snapshot)
##   Trigger: a single Cinnabark unit generates more than 1,000,000 shield in one battle.
##   Evaluated once the battle is over (the detector decides when), so the toast lands
##   on the results screen. Reads the snapshot's battle_units records:
##     battle_units[]: team_id == 0 (player side), slot_index (board slot), shield_granted
##   These fields are the ones the verified examples/MyBattleStats mod reads.
##   Species is resolved by mapping slot_index to the player run's team slot, because
##   battle unit records do not expose a species key.
##   Semantics: PER UNIT, not per slot. Two sub-threshold records in the same slot do
##   not add up. Twins duplicates that share a slot are therefore judged individually.

const TWINS_TRAINER_ID := "twins"
const BEETBUD_KEY := "monster.name.beetbud"
const BEETDOWN_KEY := "monster.name.beetdown"
const FRILLET_KEY := "monster.name.frillet"
const DEWLOTL_KEY := "monster.name.dewlotl"
const PRE_EVOLVE_LEVEL := 2  # Pre-evolution at this level evolves into its level-3 form
const EVOLUTION_ARM_WINDOW_MS := 2000  # Spans the game's multi-poll evolution animation

const GENTLEMAN_TRAINER_ID := "gentleman"
const RHIZUKA_KEY := "monster.name.rhizuka"
const RHIZUKA_MIN_LEVEL := 2   # The level-2 Rhizuka strat
const GENTLEMAN_DAY_LIMIT := 5  # Latest day the level-2 Rhizuka still counts

const CINNABARK_KEY := "monster.name.cinnabark"
const PLAYER_TEAM_ID := 0  # battle_units team_id used for the player's side
const BIG_DOG_SHIELD_THRESHOLD := 1000000.0  # Strictly over one million shield

const OH_YEAH := {
	"id": "oh_yeah",
	"title": "Oh Yeah!",
	"description": "Made double kool aid man level 3s at once !",
}

const HERD_U_LIEK_MUDKIPZ := {
	"id": "herd_u_liek_mudkipz",
	"title": "Herd U Liek Mudkipz",
	"description": "Made double Dewlotl level 3s at once !",
}

const SO_I_STARTED_BLASTING := {
	"id": "so_i_started_blasting",
	"title": "So I started blasting",
	"description": "Got a level 2 Rhizuka by Day 5 !",
}

const BIG_DOG := {
	"id": "big_dog_best_dog",
	"title": "Big Dog, Best Dog",
	"description": "Reach over 1 mil shield with Cinnabark",
}

## Twins double-evolution achievements: same rule, different species pair.
const EVOLUTION_ACHIEVEMENTS := [
	{"achievement": OH_YEAH, "pre_key": BEETBUD_KEY, "post_key": BEETDOWN_KEY},
	{"achievement": HERD_U_LIEK_MUDKIPZ, "pre_key": FRILLET_KEY, "post_key": DEWLOTL_KEY},
]

# Armed evolution baselines: achievement id -> {"baseline_post": int, "expires_ms": int}.
var _evolution_armed: Dictionary = {}
# Evolved-unit count from the previous poll, per achievement id.
var _last_post_counts: Dictionary = {}

# Gentleman Rhizuka achievement: awarded this run (suppresses repeat polling).
var _rhizuka_awarded := false

# Injectable clock. Empty in production (falls back to Time.get_ticks_msec()).
# Tests pass a controllable Callable so the evolution arm window is deterministic.
var _now_fn: Callable


func _init(now_fn: Callable = Callable()) -> void:
	_now_fn = now_fn


## Current time in milliseconds. Production uses the engine clock; tests inject.
func _now() -> int:
	if _now_fn.is_valid():
		return int(_now_fn.call())
	return Time.get_ticks_msec()


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
	if is_gentleman:
		earned.append_array(_poll_gentleman(run_snapshot, owned))
	else:
		_rhizuka_awarded = false

	if not is_twins:
		_reset_evolution_state()
		return earned

	var now := _now()
	for def in EVOLUTION_ACHIEVEMENTS:
		var achievement: Dictionary = def["achievement"]
		var id := str(achievement.get("id", ""))
		var pre_record: Dictionary = owned.get(str(def["pre_key"]), {})
		var post_record: Dictionary = owned.get(str(def["post_key"]), {})
		var pre_levels: Dictionary = pre_record.get("levels", {})
		var pre_count := int(pre_levels.get(PRE_EVOLVE_LEVEL, 0))
		var post_count := int(post_record.get("count", 0))

		# Arm on the level-2 pre-evolution, recording the evolved count to beat. The
		# previous poll's count is the baseline so a same-poll double still counts.
		var armed: Dictionary = _evolution_armed.get(id, {})
		if pre_count > 0:
			if armed.is_empty():
				armed = {"baseline_post": int(_last_post_counts.get(id, post_count))}
			armed["expires_ms"] = now + EVOLUTION_ARM_WINDOW_MS
			_evolution_armed[id] = armed

		if not armed.is_empty():
			# Twins doubles the leveled unit, so the evolved count rises by 2. The two
			# copies may land in separate polls, hence the armed window.
			if post_count >= int(armed.get("baseline_post", 0)) + 2:
				_evolution_armed.erase(id)
				earned.append(achievement.duplicate(true))
			elif now > int(armed.get("expires_ms", 0)):
				_evolution_armed.erase(id)
		_last_post_counts[id] = post_count

	return earned


## Gentleman: owns a level-2 Rhizuka on Day 5 or earlier.
func _poll_gentleman(run_snapshot: Dictionary, owned: Dictionary) -> Array:
	if _rhizuka_awarded:
		return []

	var day := int(run_snapshot.get("current_round", -1))
	if day < 1 or day > GENTLEMAN_DAY_LIMIT:
		return []

	var record: Dictionary = owned.get(RHIZUKA_KEY, {})
	var levels: Dictionary = record.get("levels", {})
	for level in levels:
		if int(level) >= RHIZUKA_MIN_LEVEL:
			_rhizuka_awarded = true
			return [SO_I_STARTED_BLASTING.duplicate(true)]
	return []


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

	if _max_cinnabark_unit_shield(battle_snapshot) > BIG_DOG_SHIELD_THRESHOLD:
		return [BIG_DOG.duplicate(true)]
	return []


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
		if not _is_cinnabark(team[slot]):
			continue
		best = maxf(best, float(shield))
	return best


## Does this snapshot team entry belong to the Cinnabark species?
func _is_cinnabark(entry) -> bool:
	return _monster_species_key(entry) == CINNABARK_KEY


## Clear all run-scoped tracking. Call at a verified run transition so consecutive
## runs with the same trainer cannot retain flags or baselines.
func reset_run() -> void:
	_reset()


func _reset() -> void:
	_reset_evolution_state()
	_rhizuka_awarded = false


## Clear only the Twins evolution baselines (keeps the Gentleman flag).
func _reset_evolution_state() -> void:
	_evolution_armed.clear()
	_last_post_counts.clear()


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
