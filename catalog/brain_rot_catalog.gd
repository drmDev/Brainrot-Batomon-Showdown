extends RefCounted
## BrainRotCatalog - the single source of truth for every reaction.
##
## Adding an entry is one metadata row in ENTRIES plus one check function below.
## Removing an entry is deleting that row, its check function, and its tests.
## There is no condition DSL: each check is plain typed GDScript.
##
## Entry shape:
##   {
##     "kind": KIND_REACTION,                      # required
##     "id": String,                               # required, unique
##     "title": String,                            # required, toast title
##     "description": String,                      # required, toast body / preview text
##     "icon": String,                             # optional, badge text; derived from id when absent
##     "species": String,                          # optional, species name_key for the monster icon
##     "scopes": [SCOPE_RUN | SCOPE_BATTLE | SCOPE_OUTCOME, ...],  # required
##     "message": String,                          # optional, "{detail}" is replaced
##     "sound": {"file": String, "volume_db": float},  # optional
##   }
##
## Reaction checks:
##   run_detail(id, snapshot)      -> detail String, or "" when it does not match
##   battle_rule(id)               -> {"value": int, "strict": bool, "metrics": [label, ...], "species"?: String}
##   outcome_detail(id, outcome)   -> detail String, or "" when it does not match

const KIND_REACTION := "reaction"

const SCOPE_RUN := "run"
const SCOPE_BATTLE := "battle"
const SCOPE_OUTCOME := "outcome"

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
const SEVEN_OR_MORE_LIVES := "7_or_more_lives"
const APES_TOGETHER := "apes_together"
const BIG_DOG := "big_dog_best_dog"
const OH_YEAH := "oh_yeah"
const HERD_U_LIEK_MUDKIPZ := "herd_u_liek_mudkipz"

const ENTRIES := [
	{
		"kind": KIND_REACTION,
		"id": SIX_SEVEN,
		"title": "SIX SEVEN!",
		"description": "Lives 6 with Day or Wins 7, income 67, or a battle total of 67",
		"icon": "67",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_NINE,
		"title": "SIX NINE!",
		"description": "Lives 6 with Day or Wins 9, income 69, or a battle total of 69",
		"icon": "69",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": FOUR_TWENTY,
		"title": "BLAZE IT!",
		"description": "Income 420 or a battle total of 420",
		"icon": "420",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_SIX_SIX,
		"title": "NUMBER OF THE BEAST!",
		"description": "Income 666 or a battle total of 666",
		"icon": "666",
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OVER_9000,
		"title": "IT'S OVER 9000!",
		"description": "Income over 9000, or 9000+ heal/burn/poison/shock in one battle",
		"icon": "9000",
		"sound": {"file": "over-9000.ogg"},
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SEVEN_OR_MORE_LIVES,
		"title": "YOU LOOK GREAT TODAY!",
		"description": "10 wins with 7+ lives at the end of a battle",
		"icon": "7+",
		"sound": {"file": "ff_fanfare.ogg"},
		"scopes": [SCOPE_OUTCOME],
	},
	{
		"kind": KIND_REACTION,
		"id": APES_TOGETHER,
		"title": "APES TOGETHER, STRONG!",
		"description": "Double sunsage!",
		"icon": "AT",
		"species": "monster.name.sunsage",
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": BIG_DOG,
		"title": "BIG DOG, BEST DOG!",
		"description": "Reach over 1 mil shield with Cinnabark",
		"icon": "BD",
		"species": "monster.name.cinnabark",
		"scopes": [SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OH_YEAH,
		"title": "OH YEAH!",
		"description": "Double kool aid man!",
		"icon": "OY",
		"species": "monster.name.beetdown",
		"scopes": [SCOPE_RUN],
	},
	{
		"kind": KIND_REACTION,
		"id": HERD_U_LIEK_MUDKIPZ,
		"title": "HERD U LIEK MUDKIPZ!",
		"description": "Double Dewlotls!",
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


## Human-readable description of an entry, for the dev toast preview.
static func describe_entry(entry_data: Dictionary) -> String:
	return str(entry_data.get("description", ""))


## Every registered reaction scope, for dev tooling and schema tests.
static func registered_rows() -> Array:
	var rows: Array = []
	for entry in reactions():
		var id := str(entry.get("id", ""))
		for scope in entry.get("scopes", []):
			rows.append({"scope": str(scope), "row": {"id": id}})
	return rows


# --- Reaction checks -------------------------------------------------------

## Detail line for a run-scoped reaction, or "" when it does not match.
static func run_detail(id: String, snapshot: Dictionary) -> String:
	match id:
		SIX_SEVEN:
			return _six_seven_run(snapshot)
		SIX_NINE:
			return _six_nine_run(snapshot)
		FOUR_TWENTY:
			return _income_detail(snapshot, 420)
		SIX_SIX_SIX:
			return _income_detail(snapshot, 666)
		OVER_9000:
			return _income_gt_detail(snapshot, 9000)
		APES_TOGETHER:
			return _apes_together_detail(snapshot)
		OH_YEAH:
			return _twins_evolution_detail(snapshot, "monster.name.beetdown", "Beetdown")
		HERD_U_LIEK_MUDKIPZ:
			return _twins_evolution_detail(snapshot, "monster.name.dewlotl", "Dewlotl")
	return ""


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


## Detail line for an outcome-scoped reaction, or "" when it does not match.
static func outcome_detail(id: String, outcome: Dictionary) -> String:
	match id:
		SEVEN_OR_MORE_LIVES:
			return _seven_or_more_lives_detail(outcome)
	return ""


static func _six_seven_run(snapshot: Dictionary) -> String:
	var parts: PackedStringArray = []
	var base := _lives_day_wins_run(snapshot, 6, 7)
	if not base.is_empty():
		parts.append(base)
	var income := _income_detail(snapshot, 67)
	if not income.is_empty():
		parts.append(income)
	return ", ".join(parts)


static func _six_nine_run(snapshot: Dictionary) -> String:
	var parts: PackedStringArray = []
	var base := _lives_day_wins_run(snapshot, 6, 9)
	if not base.is_empty():
		parts.append(base)
	var income := _income_detail(snapshot, 69)
	if not income.is_empty():
		parts.append(income)
	return ", ".join(parts)


## "Lives 6, Day 7" / "Lives 6, Wins 7" / "Lives 6, Day 7, Wins 7", or "".
static func _lives_day_wins_run(snapshot: Dictionary, lives_expected: int, day_or_wins: int) -> String:
	var lives = _int(snapshot, "lives")
	if lives == null or int(lives) != lives_expected:
		return ""
	var parts: PackedStringArray = ["Lives %d" % lives_expected]
	var day = _int(snapshot, "current_round")
	var wins = _int(snapshot, "current_wins")
	if day != null and int(day) == day_or_wins:
		parts.append("Day %d" % day_or_wins)
	if wins != null and int(wins) == day_or_wins:
		parts.append("Wins %d" % day_or_wins)
	if parts.size() == 1:
		return ""
	return ", ".join(parts)


static func _income_detail(snapshot: Dictionary, expected: int) -> String:
	var income = _int(snapshot, "income")
	if income == null or int(income) != expected:
		return ""
	return "Income %d" % expected


static func _income_gt_detail(snapshot: Dictionary, threshold: int) -> String:
	var income = _int(snapshot, "income")
	if income == null or int(income) <= threshold:
		return ""
	return "Income %d" % int(income)


static func _apes_together_detail(snapshot: Dictionary) -> String:
	var trainer = snapshot.get("trainer_id")
	if typeof(trainer) != TYPE_STRING or str(trainer) != "twins":
		return ""
	for list_name in ["team", "bench"]:
		var list = snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if not monster is Dictionary:
				continue
			if str(monster.get("name_key", "")) != "monster.name.sunsage":
				continue
			var level = monster.get("level")
			if typeof(level) != TYPE_INT:
				continue
			if int(level) >= 3:
				return "Trainer twins, Sunsage level %d" % int(level)
	return ""


## Twins double-evolution: owns a level-3 evolved unit named by `species_key`.
static func _twins_evolution_detail(snapshot: Dictionary, species_key: String, display_name: String) -> String:
	var trainer = snapshot.get("trainer_id")
	if typeof(trainer) != TYPE_STRING or str(trainer) != "twins":
		return ""
	for list_name in ["team", "bench"]:
		var list = snapshot.get(list_name)
		if not list is Array:
			continue
		for monster in list:
			if not monster is Dictionary:
				continue
			if str(monster.get("name_key", "")) != species_key:
				continue
			var level = monster.get("level")
			if typeof(level) != TYPE_INT:
				continue
			if int(level) >= 3:
				return "Trainer twins, %s level %d" % [display_name, int(level)]
	return ""



static func _seven_or_more_lives_detail(outcome: Dictionary) -> String:
	var wins = _int(outcome, "wins")
	var lives = _int(outcome, "lives")
	if wins == null or lives == null:
		return ""
	if int(wins) != 10 or int(lives) < 7:
		return ""
	return "Wins %d, Lives %d" % [int(wins), int(lives)]


## Integer value of a snapshot key, or null when missing/non-int.
static func _int(snapshot: Dictionary, key: String):
	var value = snapshot.get(key)
	if typeof(value) == TYPE_INT:
		return int(value)
	return null
