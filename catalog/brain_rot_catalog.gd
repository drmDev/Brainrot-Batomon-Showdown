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
##   battle_rule(id)               -> {"value": int, "strict": bool, "metrics": [label, ...], "species"?: String}

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

const ENTRIES := [
	{
		"kind": KIND_REACTION,
		"id": SIX_SEVEN,
		"title": "SIX SEVEN!",
		"icon": "67",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_NINE,
		"title": "NICE!",
		"icon": "69",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": FOUR_TWENTY,
		"title": "BLAZE IT!",
		"icon": "420",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_SIX_SIX,
		"title": "HAIL SATAN!",
		"icon": "666",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OVER_9000,
		"title": "IT'S OVER 9000!",
		"icon": "9000",
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
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": HERD_U_LIEK_MUDKIPZ,
		"title": "HERD U LIEK MUDKIPZ!",
		"icon": "HM",
		"species": "monster.name.dewlotl",
		"scopes": [SCOPE_RUN],
	}
]


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


## Badge text for an id: the entry's explicit "icon" when present, otherwise a
## value derived from the id string. Unknown/empty ids yield "?".
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


## Every registered reaction scope, for dev tooling and schema tests.
static func registered_rows() -> Array:
	var rows: Array = []
	for entry in reactions():
		var id := str(entry.get("id", ""))
		for scope in entry.get("scopes", []):
			rows.append({"scope": str(scope), "row": {"id": id}})
	return rows


# --- Reaction checks -------------------------------------------------------

## Match for a run-scoped reaction, or {}. When several conditions match at once,
## exactly one case is chosen by fixed priority (lives_day_wins > lives_day >
## lives_wins > income), so one toast never mixes two conditions.
static func run_match(id: String, snapshot: Dictionary) -> Dictionary:
	match id:
		SIX_SEVEN:
			return _six_seven_match(snapshot)
		SIX_NINE:
			return _six_nine_match(snapshot)
		FOUR_TWENTY:
			return _income_match(snapshot, 420)
		SIX_SIX_SIX:
			return _income_match(snapshot, 666)
		OVER_9000:
			return _income_gt_match(snapshot, 9000)
		APES_TOGETHER:
			return _apes_together_match(snapshot)
		OH_YEAH:
			return _twins_evolution_match(snapshot, "monster.name.beetdown")
		HERD_U_LIEK_MUDKIPZ:
			return _twins_evolution_match(snapshot, "monster.name.dewlotl")
	return {}


## Battle comparison for a battle-scoped reaction, or {} when it has none.
## `strict` means "greater than"; otherwise the comparison is equality. An optional
## `species` key restricts the match to units whose team slot resolves to that
## species name_key (Big Dog is Cinnabark-only).
static func battle_rule(id: String) -> Dictionary:
	match id:
		SIX_SEVEN:
			return {"value": 67, "strict": false, "metrics": BATTLE_METRIC_ORDER}
		SIX_NINE:
			return {"value": 69, "strict": false, "metrics": BATTLE_METRIC_ORDER}
		FOUR_TWENTY:
			return {"value": 420, "strict": false, "metrics": BATTLE_METRIC_ORDER}
		SIX_SIX_SIX:
			return {"value": 666, "strict": false, "metrics": BATTLE_METRIC_ORDER}
		OVER_9000:
			return {"value": 9000, "strict": true, "metrics": ["heal", "burn", "poison", "shock"]}
		BIG_DOG:
			return {"value": 1000000, "strict": true, "metrics": ["shield"], "species": "monster.name.cinnabark"}
	return {}


static func _six_seven_match(snapshot: Dictionary) -> Dictionary:
	return _lives_day_wins_income_match(snapshot, 6, 7, 67)


static func _six_nine_match(snapshot: Dictionary) -> Dictionary:
	return _lives_day_wins_income_match(snapshot, 6, 9, 69)


## Shared priority for six_seven / six_nine. Lives must be lives_expected; day and
## wins match the same target; income is the fallback.
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


static func _income_match(snapshot: Dictionary, expected: int) -> Dictionary:
	var income = _int(snapshot, "income")
	if income != null and int(income) == expected:
		return {"case": "income", "params": {"income": expected}}
	return {}


static func _income_gt_match(snapshot: Dictionary, threshold: int) -> Dictionary:
	var income = _int(snapshot, "income")
	if income != null and int(income) > threshold:
		return {"case": "income", "params": {"income": int(income)}}
	return {}


static func _apes_together_match(snapshot: Dictionary) -> Dictionary:
	return _twins_evolution_match(snapshot, "monster.name.sunsage")


## Twins reaction: trainer is Twins and the team/bench contains the species. The
## evolved form is the only way that species can exist for Twins, so no level check.
static func _twins_evolution_match(snapshot: Dictionary, species_key: String) -> Dictionary:
	var trainer = snapshot.get("trainer_id")
	if typeof(trainer) != TYPE_STRING or str(trainer) != "twins":
		return {}
	for list_name in ["team", "bench"]:
		var list = snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if not monster is Dictionary:
				continue
			if str(monster.get("name_key", "")) == species_key:
				return {"case": "evolved", "params": {}}
	return {}


## Integer value of a snapshot key, or null when missing/non-int.
static func _int(snapshot: Dictionary, key: String):
	var value = snapshot.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	return null
