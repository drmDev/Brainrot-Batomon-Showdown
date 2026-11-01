extends RefCounted
## AchievementEvaluator - detects earned achievements from live run state.
##
## Poll-based: mod_main calls poll(run) on every poll and poll_battle(state, run) while
## in the battle state. Both return an Array of newly earned achievement dictionaries
## (empty most polls). The caller owns persistence (achievement_store) and display
## (achievement_panel).
##
## Achievements:
## - "So I started blasting" (poll, run state)
##   Trainer: Gentleman
##   Trigger: a level-2 Rhizuka (the trainer's common level-2 strat) is owned no later
##   than Day 5. Day is read from run.current_round (the field the mod already logs as
##   "Day"). State-based: awards as soon as the condition is true.
## - "Oh Yeah!" / "Herd U Liek Mudkipz" (poll, run state)
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
## - "Big Dog, Best Dog" (poll_battle, battle state)
##   Trigger: a Cinnabark unit generates more than 1,000,000 shield in one battle.
##   Evaluated once the battle is over, so the toast lands on the results screen.
##   Reads the visible battle simulation's unit records:
##     battle_state.simulation.data.battle_units[]
##       team_id == 0 (player side), slot_index (board slot), shield_granted
##   These fields are the ones the verified examples/MyBattleStats mod reads.
##   Species is resolved by mapping slot_index to the player run's team slot, because
##   battle unit records do not expose a species key.

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

# Big Dog tracking: award at most once per battle state instance.
var _battle_state_id := 0
var _big_dog_awarded := false

# Shared property probe (mod_main passes its _has_property Callable).
var _has_prop: Callable
# Injectable clock. Empty in production (falls back to Time.get_ticks_msec()).
# Tests pass a controllable Callable so the evolution arm window is deterministic.
var _now_fn: Callable


func _init(has_property_fn: Callable, now_fn: Callable = Callable()) -> void:
	_has_prop = has_property_fn
	_now_fn = now_fn


## Current time in milliseconds. Production uses the engine clock; tests inject.
func _now() -> int:
	if _now_fn.is_valid():
		return int(_now_fn.call())
	return Time.get_ticks_msec()


## Poll the run for newly earned achievements. Returns an Array of achievement dicts.
func poll(run) -> Array:
	if run == null or not is_instance_valid(run):
		_reset()
		return []

	var trainer_id := str(run.get("trainer_id")) if _has_prop.call(run, "trainer_id") else ""
	var is_gentleman := trainer_id == GENTLEMAN_TRAINER_ID
	var is_twins := trainer_id == TWINS_TRAINER_ID
	if not is_gentleman and not is_twins:
		_reset()
		return []

	var owned := _collect_owned_species(run)

	var earned: Array = []
	if is_gentleman:
		earned.append_array(_poll_gentleman(run, owned))
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
func _poll_gentleman(run, owned: Dictionary) -> Array:
	if _rhizuka_awarded:
		return []

	var day := int(run.get("current_round")) if _has_prop.call(run, "current_round") else -1
	if day < 1 or day > GENTLEMAN_DAY_LIMIT:
		return []

	var record: Dictionary = owned.get(RHIZUKA_KEY, {})
	var levels: Dictionary = record.get("levels", {})
	for level in levels:
		if int(level) >= RHIZUKA_MIN_LEVEL:
			_rhizuka_awarded = true
			return [SO_I_STARTED_BLASTING.duplicate(true)]
	return []


## Poll the active battle state for battle-scoped achievements. Returns newly earned
## achievement dicts. Called every poll while inside the battle state.
##
## Evaluated only once the battle has finished (simulation.data.battle_over) so the toast
## appears on the results screen, matching the Achievement Notifications setting wording.
func poll_battle(state, run) -> Array:
	if state == null or not is_instance_valid(state):
		reset_battle()
		return []

	var instance_id: int = state.get_instance_id()
	if instance_id != _battle_state_id:
		_battle_state_id = instance_id
		_big_dog_awarded = false

	if _big_dog_awarded:
		return []
	if run == null or not is_instance_valid(run):
		return []

	var sim = state.get("simulation") if _has_prop.call(state, "simulation") else null
	if sim == null or not is_instance_valid(sim):
		return []
	var data = sim.get("data") if _has_prop.call(sim, "data") else null
	if data == null or not _has_prop.call(data, "battle_over") or not bool(data.get("battle_over")):
		return []

	var max_shield := _max_cinnabark_shield(data, run)
	if max_shield > BIG_DOG_SHIELD_THRESHOLD:
		_big_dog_awarded = true
		return [BIG_DOG.duplicate(true)]
	return []


## Highest single-slot shield total generated by a Cinnabark on the player's side.
## The fight is simulated up front, so these totals are final by the time it is over.
func _max_cinnabark_shield(data, run) -> float:
	if not _has_prop.call(data, "battle_units"):
		return 0.0
	var units = data.get("battle_units")
	if not units is Array:
		return 0.0

	var team = run.get("team") if _has_prop.call(run, "team") else null
	if not team is Array:
		return 0.0

	# Sum shield per board slot (Twins duplicates can share a slot).
	var shield_by_slot := {}
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if not _has_prop.call(unit, "team_id") or not _has_prop.call(unit, "slot_index") or not _has_prop.call(unit, "shield_granted"):
			continue
		var team_id = unit.get("team_id")
		var slot_value = unit.get("slot_index")
		var shield_value = unit.get("shield_granted")
		if team_id == null or slot_value == null or shield_value == null:
			continue
		if int(team_id) != PLAYER_TEAM_ID:
			continue
		var slot := int(slot_value)
		shield_by_slot[slot] = float(shield_by_slot.get(slot, 0.0)) + float(shield_value)

	var best := 0.0
	for slot in shield_by_slot.keys():
		if slot < 0 or slot >= team.size():
			continue
		if not _is_cinnabark(team[slot]):
			continue
		best = maxf(best, float(shield_by_slot[slot]))
	return best


## Does this live team monster belong to the Cinnabark species?
func _is_cinnabark(monster) -> bool:
	return _monster_species_key(monster) == CINNABARK_KEY


## Clear battle-scoped tracking. Call when leaving the battle phase.
func reset_battle() -> void:
	_battle_state_id = 0
	_big_dog_awarded = false


func _reset() -> void:
	_reset_evolution_state()
	_rhizuka_awarded = false


## Clear only the Twins evolution baselines (keeps the Gentleman flag).
func _reset_evolution_state() -> void:
	_evolution_armed.clear()
	_last_post_counts.clear()


## One pass over team + bench: species key -> {"count": int, "levels": {level: count}}.
func _collect_owned_species(run) -> Dictionary:
	var species := {}
	for list_name in ["team", "bench"]:
		if not _has_prop.call(run, list_name):
			continue
		var list = run.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			var key := _monster_species_key(monster)
			if key.is_empty():
				continue
			var level := int(monster.get("level")) if _has_prop.call(monster, "level") else 1
			var record: Dictionary = species.get(key, {"count": 0, "levels": {}})
			record["count"] = int(record["count"]) + 1
			var levels: Dictionary = record["levels"]
			levels[level] = int(levels.get(level, 0)) + 1
			species[key] = record
	return species


## Species name_key of a live monster, or "" when unavailable.
func _monster_species_key(monster) -> String:
	if monster == null or not is_instance_valid(monster):
		return ""
	if not _has_prop.call(monster, "data"):
		return ""
	var data = monster.get("data")
	if data == null or not _has_prop.call(data, "name_key"):
		return ""
	return str(data.get("name_key"))
