extends RefCounted
## BrainRotCatalog - the single source of truth for reaction detection metadata.
##
## Detection and wording are separate:
## - This file owns the reaction entries, ids, battle rules, and the run-scoped
##   condition checks. Checks return a match ({case, params}) or {} - no user text.
## - catalog/reaction_text.gd owns every line a player reads.
##
## Entry shape:
##   {
##     "kind": KIND_REACTION,                      # required
##     "id": String,                               # required, unique
##     "title": String,                            # required, toast title
##     "icon": String,                             # optional, badge text; derived from id when absent
##     "species": String,                          # optional, species name_key for the monster icon
##     "scopes": [SCOPE_RUN | SCOPE_BATTLE, ...],  # required
##     "sound": {"file": String, "volume_db": float},  # optional
##   }
##
## Reaction checks:
##   run_match(id, snapshot)       -> {"case": String, "params": Dictionary}, or {}
##   battle_rule(id)               -> {"value": int, "op": "eq"|"gt", "metrics": [label, ...], "species"?: String}

const KIND_REACTION := "reaction"

const SCOPE_RUN := "run"
const SCOPE_BATTLE := "battle"

## Battle metric label -> unit record key. Labels are what battle rules use.
const BATTLE_METRICS := {
	"damage": "damage_dealt",
	"heal": "healing_done",
	"shield": "shield_granted",
	"burn": "burn_inflicted",
	"poison": "poison_inflicted",
	"shock": "shock_inflicted",
}

## Evaluation order for battle metrics. The first matching metric in a slot wins.
const BATTLE_METRIC_ORDER := ["damage", "heal", "shield", "burn", "poison", "shock"]

## High-score icon kinds: a species icon (the unit that set the record) or a
## trainer portrait (the trainer whose run set the record).
const ICON_UNIT := "unit"
const ICON_TRAINER := "trainer"

## High-score metric label -> metadata. `key` is the per-unit battle record key
## (absent for battle/run-level metrics); `icon` is ICON_UNIT or ICON_TRAINER.
## The first six labels are the per-unit battle metrics; the last three are
## battle/run-level records.
const HIGH_SCORE_METRICS := {
	"damage": {"key": "damage_dealt", "icon": ICON_UNIT},
	"heal": {"key": "healing_done", "icon": ICON_UNIT},
	"shield": {"key": "shield_granted", "icon": ICON_UNIT},
	"burn": {"key": "burn_inflicted", "icon": ICON_UNIT},
	"poison": {"key": "poison_inflicted", "icon": ICON_UNIT},
	"shock": {"key": "shock_inflicted", "icon": ICON_UNIT},
	"longest_battle": {"icon": ICON_TRAINER},
	"most_casts": {"key": "cast_count", "icon": ICON_UNIT},
	"most_trinkets": {"icon": ICON_TRAINER},
}

## Display/evaluation order for the high-score table. The per-unit battle metrics
## come first (matching BATTLE_METRIC_ORDER), then the battle/run-level records.
const HIGH_SCORE_METRIC_ORDER := [
	"damage", "heal", "shield", "burn", "poison", "shock",
	"longest_battle", "most_casts", "most_trinkets",
]

## Reaction ids. Definitions and tests reference these instead of string literals.
const SIX_SEVEN := "six_seven"
const SIX_NINE := "six_nine"
const FOUR_TWENTY := "four_twenty"
const SIX_SIX_SIX := "six_six_six"
const OVER_9000 := "over_9000"
const APES_TOGETHER := "apes_together"
const BIG_DOG := "big_dog_best_dog"
const OH_YEAH := "oh_yeah"
const HERD_U_LIEK_MUDKIPZ := "herd_u_liek_mudkipz"
const DOUBLE_RAINBOW := "double_rainbow"
const HARAMBE := "harambe"
const TROGDOR := "trogdor"
const NOT_THE_BEES := "not_the_bees"
const TETSUO := "tetsuo"

const ENTRIES := [
	{
		"kind": KIND_REACTION,
		"id": SIX_SEVEN,
		"title": "SIX SEVEN!",
		"icon": "67",
		"icon_file": "67.png",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_NINE,
		"title": "NICE!",
		"icon": "69",
		"icon_file": "nice.png",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": FOUR_TWENTY,
		"title": "BLAZE IT!",
		"icon": "420",
		"icon_file": "snoop420.png",
		"sound": {"file": "420.ogg"},
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_SIX_SIX,
		"title": "HAIL SATAN!",
		"icon": "666",
		"icon_file": "666.png",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OVER_9000,
		"title": "IT'S OVER 9000!",
		"icon": "9000",
		"icon_file": "over9000.png",
		"sound": {"file": "over-9000.ogg"},
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": APES_TOGETHER,
		"title": "APES TOGETHER, STRONG!",
		"icon": "AT",
		"species": "monster.name.sunsage",
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": BIG_DOG,
		"title": "BIG DOG, BEST DOG!",
		"icon": "BD",
		"species": "monster.name.cinnabark",
		"scopes": [SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OH_YEAH,
		"title": "OH YEAH!",
		"icon": "OY",
		"species": "monster.name.beetdown",
		"sound": {"file": "ohYeah.ogg"},
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": HERD_U_LIEK_MUDKIPZ,
		"title": "HERD U LIEK MUDKIPZ!",
		"icon": "HM",
		"species": "monster.name.dewlotl",
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": DOUBLE_RAINBOW,
		"title": "Double Rainbow!",
		"icon_file": "dubRainbow.png",
		"sound": {"file": "dubRainbow.ogg"},
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": HARAMBE,
		"title": "Dicks out for Harambe!",
		"species": "monster.name.sarudo",
		"sound": {"file": "harambe.ogg"},
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": TROGDOR,
		"title": "BURNINATING THE COUNTRYSIDE!",
		"species": "monster.name.furnadon",
		"sound": {"file": "trogdor.ogg"},
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": NOT_THE_BEES,
		"title": "NOT THE BEES!",
		"species": "monster.name.bumblebolt",
		"sound": {"file": "not-the-bees.ogg"},
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": TETSUO,
		"title": "TETSUO!",
		"species": "monster.name.tengusto",
		"sound": {"file": "tetsuo.ogg"},
		"scopes": [SCOPE_RUN],
	}
]


## Run-scoped "owns a monster" rules, keyed by reaction id. A row matches when the
## run's team or bench contains a monster satisfying every present field:
##   trainer: required trainer_id (absent = any trainer)
##   species: required name_key (absent = any species)
##   level:   required level (-1 = any level)
##   shiny:   true = must be shiny (absent = no requirement)
##   case:    match case name
const OWN_RULES := {
	APES_TOGETHER: {"trainer": "twins", "species": "monster.name.sunsage", "level": -1, "case": "owned"},
	OH_YEAH: {"species": "monster.name.beetdown", "level": 3, "case": "owned"},
	HERD_U_LIEK_MUDKIPZ: {"species": "monster.name.dewlotl", "level": 3, "case": "owned"},
	TROGDOR: {"species": "monster.name.furnadon", "level": 3, "case": "owned"},
	NOT_THE_BEES: {"species": "monster.name.bumblebolt", "level": 3, "case": "owned"},
	DOUBLE_RAINBOW: {"trainer": "twins", "level": 3, "shiny": true, "case": "owned"},
}

## Run-scoped lives/day/wins/income rules, keyed by reaction id. `lives` must match,
## then day and wins are checked against `target` in priority order, with `income`
## as the fallback.
const LIVES_RULES := {
	SIX_SEVEN: {"lives": 6, "target": 7, "income": 67},
	SIX_NINE: {"lives": 6, "target": 9, "income": 69},
}

## Run-scoped income rules, keyed by reaction id. `op` is "eq" (exactly) or "gt"
## (greater than).
const INCOME_RULES := {
	FOUR_TWENTY: {"value": 420, "op": "eq"},
	SIX_SIX_SIX: {"value": 666, "op": "eq"},
	OVER_9000: {"value": 9000, "op": "gt"},
}


## Every reaction entry, in stable order.
static func reactions() -> Array:
	return ENTRIES


## Entry matching an id, or {} when absent.
static func entry(id: String) -> Dictionary:
	for candidate in ENTRIES:
		if str(candidate.get("id", "")) == id:
			return candidate
	return {}


## Toast title for an id. Unknown ids fall back to the id itself.
static func title_for(id: String) -> String:
	var found := entry(id)
	if found.is_empty():
		return id
	return str(found.get("title", id))


## Static species name_key authored on a reaction entry, or "" when absent.
static func species_for(id: String) -> String:
	return str(entry(id).get("species", ""))


## Badge text for an id: the entry's explicit "icon" when present, otherwise a
## value derived from the id string. Unknown/empty ids yield "?".
static func icon_file_for(id: String) -> String:
	return str(entry(id).get("icon_file", ""))


static func icon_for(id: String) -> String:
	var found := entry(id)
	if not found.is_empty():
		var explicit = found.get("icon")
		if typeof(explicit) == TYPE_STRING and not str(explicit).is_empty():
			return str(explicit)
	return _derive_icon(id)


## Derive badge text from an id when no explicit icon is authored. Number words
## (zero..twenty) become digits and are joined; otherwise the uppercase initials
## of the underscore-separated tokens are used, capped at three characters.
static func _derive_icon(id: String) -> String:
	var cleaned := str(id).strip_edges()
	if cleaned.is_empty():
		return "?"
	var number_words := {
		"zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
		"five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
		"ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
		"fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
		"eighteen": "18", "nineteen": "19", "twenty": "20",
	}
	var digits := ""
	for token in cleaned.split("_"):
		var lower := str(token).to_lower()
		if number_words.has(lower):
			digits += str(number_words[lower])
	if not digits.is_empty():
		return digits
	var initials := ""
	for token in cleaned.split("_"):
		var part := str(token).strip_edges()
		if part.is_empty():
			continue
		initials += part.substr(0, 1).to_upper()
		if initials.length() >= 3:
			break
	if initials.is_empty():
		return "?"
	return initials


## Reaction id -> sound row, for the table-driven audio player.
static func sounds() -> Dictionary:
	var out := {}
	for candidate in ENTRIES:
		var id := str(candidate.get("id", ""))
		var sound = candidate.get("sound")
		if not id.is_empty() and sound is Dictionary:
			out[id] = sound
	return out


# --- Reaction checks -------------------------------------------------------

## Match for a run-scoped reaction, or {}. When several conditions match at once,
## exactly one case is chosen by fixed priority (lives_day_wins > lives_day >
## lives_wins > income), so one toast never mixes two conditions.
static func run_match(id: String, snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {}
	if OWN_RULES.has(id):
		return _own_match(snapshot, OWN_RULES[id])
	if LIVES_RULES.has(id):
		var lives_row: Dictionary = LIVES_RULES[id]
		return _lives_day_wins_income_match(
			snapshot,
			int(lives_row["lives"]),
			int(lives_row["target"]),
			int(lives_row["income"]),
		)
	if INCOME_RULES.has(id):
		var income_row: Dictionary = INCOME_RULES[id]
		return _income_match(snapshot, int(income_row["value"]), str(income_row["op"]))
	return {}


## Battle comparison for a battle-scoped reaction, or {} when it has none.
## `op` is "eq" (exactly) or "gt" (greater than). An optional `species` key
## restricts the match to units whose team slot resolves to that species name_key
## (Big Dog is Cinnabark-only).
static func battle_rule(id: String) -> Dictionary:
	match id:
		SIX_SEVEN:
			return {"value": 67, "op": "eq", "metrics": BATTLE_METRIC_ORDER}
		SIX_NINE:
			return {"value": 69, "op": "eq", "metrics": BATTLE_METRIC_ORDER}
		FOUR_TWENTY:
			return {"value": 420, "op": "eq", "metrics": BATTLE_METRIC_ORDER}
		SIX_SIX_SIX:
			return {"value": 666, "op": "eq", "metrics": BATTLE_METRIC_ORDER}
		OVER_9000:
			return {"value": 9000, "op": "gt", "metrics": ["heal", "burn", "poison", "shock"]}
		BIG_DOG:
			return {"value": 1000000, "op": "gt", "metrics": ["shield"], "species": "monster.name.cinnabark"}
	return {}


## Shared priority for the lives/day/wins/income rules. Lives must match; day and
## wins are checked against the same target; income is the fallback.
static func _lives_day_wins_income_match(snapshot: Dictionary, lives_expected: int, target: int, income_expected: int) -> Dictionary:
	var lives = _int(snapshot, "lives")
	var day = _int(snapshot, "current_round")
	var wins = _int(snapshot, "current_wins")
	var income = _int(snapshot, "income")

	var lives_ok := lives != null and int(lives) == lives_expected
	var day_ok := day != null and int(day) == target
	var wins_ok := wins != null and int(wins) == target

	if lives_ok and day_ok and wins_ok:
		return {"case": "lives_day_wins", "params": {"lives": lives_expected, "day": target, "wins": target}}
	if lives_ok and day_ok:
		return {"case": "lives_day", "params": {"lives": lives_expected, "day": target}}
	if lives_ok and wins_ok:
		return {"case": "lives_wins", "params": {"lives": lives_expected, "wins": target}}
	if income != null and int(income) == income_expected:
		return {"case": "income", "params": {"income": income_expected}}
	return {}


## Income rule: "eq" (exactly) or "gt" (greater than).
static func _income_match(snapshot: Dictionary, expected: int, op: String = "eq") -> Dictionary:
	var income = _int(snapshot, "income")
	if income == null:
		return {}
	var actual := int(income)
	if op == "gt":
		if actual > expected:
			return {"case": "income", "params": {"income": actual}}
		return {}
	if actual == expected:
		return {"case": "income", "params": {"income": expected}}
	return {}


## Match a run snapshot against an OWN_RULES row. Returns {case, params} or {}.
static func _own_match(snapshot: Dictionary, rule: Dictionary) -> Dictionary:
	var trainer := str(rule.get("trainer", ""))
	if not trainer.is_empty() and str(snapshot.get("trainer_id", "")) != trainer:
		return {}
	var species := str(rule.get("species", ""))
	var level := int(rule.get("level", -1))
	var shiny := bool(rule.get("shiny", false))
	for monster in _monsters(snapshot):
		if not species.is_empty() and str(monster.get("name_key", "")) != species:
			continue
		if level >= 0:
			var monster_level = monster.get("level")
			if typeof(monster_level) != TYPE_INT or int(monster_level) != level:
				continue
		if shiny and not bool(monster.get("shiny", false)):
			continue
		return {"case": str(rule.get("case", "owned")), "params": {}}
	return {}


## Every monster entry in the run's team then bench, in order. Non-dictionary
## entries are skipped; the reader emits {} for a null monster, so this is safe.
static func _monsters(snapshot: Dictionary) -> Array:
	var out: Array = []
	for list_name in ["team", "bench"]:
		var list = snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if monster is Dictionary:
				out.append(monster)
	return out


## HARAMBE: a Sarudo was sold between two shop snapshots.
##
## A raw count drop is not enough: buying a third Sarudo combines three into one
## higher-level Sarudo, which also reduces the count. Only treat it as a sell when
## the max Sarudo level did not increase (a combine always raises the max level).
static func sold_match(previous: Dictionary, current: Dictionary) -> Dictionary:
	if previous.is_empty() or current.is_empty():
		return {}
	if _count_species(previous, "monster.name.sarudo") <= _count_species(current, "monster.name.sarudo"):
		return {}
	if _max_species_level(current, "monster.name.sarudo") > _max_species_level(previous, "monster.name.sarudo"):
		return {}
	return {"case": "sold", "params": {}}


## TETSUO: a Tengusto gained a Poison or Shock permanent buff between two shop
## snapshots. Compares the summed Poison+Shock permanent buffs across owned
## Tengusto (team + bench); fires when the total increased.
static func buff_gain_match(previous: Dictionary, current: Dictionary) -> Dictionary:
	if previous.is_empty() or current.is_empty():
		return {}
	if _tengusto_poison_shock_total(current) > _tengusto_poison_shock_total(previous):
		return {"case": "gained", "params": {}}
	return {}


## Summed Poison + Shock permanent buffs across owned Tengusto (team + bench).
static func _tengusto_poison_shock_total(snapshot: Dictionary) -> float:
	var total := 0.0
	for monster in _monsters(snapshot):
		if str(monster.get("name_key", "")) != "monster.name.tengusto":
			continue
		total += _monster_poison_shock(monster)
	return total


## Poison + Shock permanent buffs on one monster snapshot.
static func _monster_poison_shock(monster: Dictionary) -> float:
	var total := 0.0
	for key in ["perm_poison", "perm_shock"]:
		var value = monster.get(key)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			total += float(value)
	return total


## Number of team/bench monsters with `species_key`.
static func _count_species(snapshot: Dictionary, species_key: String) -> int:
	var count := 0
	for monster in _monsters(snapshot):
		if str(monster.get("name_key", "")) == species_key:
			count += 1
	return count


## Highest level among team/bench monsters with `species_key` (0 when none).
static func _max_species_level(snapshot: Dictionary, species_key: String) -> int:
	var max_level := 0
	for monster in _monsters(snapshot):
		if str(monster.get("name_key", "")) != species_key:
			continue
		var level = monster.get("level")
		if typeof(level) == TYPE_INT and int(level) > max_level:
			max_level = int(level)
	return max_level


## Integer value of a snapshot key, or null when missing/non-int.
static func _int(snapshot: Dictionary, key: String):
	var value = snapshot.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	return null
