extends RefCounted
## BrainRotCatalog - the single source of truth for every achievement and reaction.
##
## Adding an entry is one metadata row in ENTRIES plus one check function below.
## Removing an entry is deleting that row, its check function, and its tests.
## There is no condition DSL: each check is plain typed GDScript.
##
## Entry shape (shared):
##   {
##     "kind": KIND_ACHIEVEMENT | KIND_REACTION,  # required
##     "id": String,                              # required, unique across BOTH kinds
##     "title": String,                           # required, toast title
##     "description": String,                     # required, toast body / preview text
##     "persist": bool,                           # required; true = saved to achievements.json
##   }
##
## Reaction entries add:
##   {
##     "scopes": [SCOPE_RUN | SCOPE_BATTLE | SCOPE_OUTCOME, ...],  # required
##     "message": String,                         # optional, "{detail}" is replaced
##     "sound": {"file": String, "volume_db": float},  # optional
##   }
##
## Achievement entries add:
##   {
##     "track": bool,                             # optional, default true; false = stateless
##     "rules": [{"name": RULE_*, "scope": SCOPE_RUN | SCOPE_BATTLE, ...args}, ...],
##   }
##
## Reaction checks:
##   run_detail(id, snapshot)      -> detail String, or "" when it does not match
##   battle_rule(id)               -> {"value": int, "strict": bool, "metrics": [label, ...]}
##   outcome_detail(id, outcome)   -> detail String, or "" when it does not match
##
## Achievement rules are dispatched by the achievement evaluator, which keeps the
## stateful logic (trainer gating, owned-species collection, award tracking).

const KIND_ACHIEVEMENT := "achievement"
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

## Achievement ids.
const OH_YEAH := "oh_yeah"
const HERD_U_LIEK_MUDKIPZ := "herd_u_liek_mudkipz"
const SO_I_STARTED_BLASTING := "so_i_started_blasting"
const BIG_DOG := "big_dog_best_dog"

## Achievement rule names. The achievement evaluator dispatches on these.
const RULE_GENTLEMAN_RHIZUKA := "gentleman_rhizuka"
const RULE_TWINS_EVOLUTION := "twins_evolution"
const RULE_CINNABARK_SHIELD := "cinnabark_shield"

const RULES := [
	RULE_GENTLEMAN_RHIZUKA,
	RULE_TWINS_EVOLUTION,
	RULE_CINNABARK_SHIELD,
]

const ENTRIES := [
	# --- Reactions ---
	{
		"kind": KIND_REACTION,
		"id": SIX_SEVEN,
		"title": "6 7",
		"description": "Lives 6 with Day or Wins 7, income 67, or a battle total of 67",
		"persist": false,
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_NINE,
		"title": "6 9",
		"description": "Lives 6 with Day or Wins 9, income 69, or a battle total of 69",
		"persist": false,
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": FOUR_TWENTY,
		"title": "Blaze It",
		"description": "Income 420 or a battle total of 420",
		"persist": false,
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SIX_SIX_SIX,
		"title": "Number of the Beast",
		"description": "Income 666 or a battle total of 666",
		"persist": false,
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": OVER_9000,
		"title": "It's Over 9000!",
		"description": "Income over 9000, or 9000+ heal/burn/poison/shock in one battle",
		"persist": false,
		"sound": {"file": "over-9000.ogg"},
		"scopes": [SCOPE_RUN, SCOPE_BATTLE],
	},
	{
		"kind": KIND_REACTION,
		"id": SEVEN_OR_MORE_LIVES,
		"title": "You look great today!",
		"description": "10 wins with 7+ lives at the end of a battle",
		"persist": false,
		"sound": {"file": "ff_fanfare.ogg"},
		"scopes": [SCOPE_OUTCOME],
	},
	{
		"kind": KIND_REACTION,
		"id": APES_TOGETHER,
		"title": "Apes together, strong",
		"description": "Double sunsage!",
		"persist": false,
		"scopes": [SCOPE_RUN],
	},

	# --- Achievements ---
	{
		"kind": KIND_ACHIEVEMENT,
		"id": OH_YEAH,
		"title": "Oh Yeah!",
		"description": "Double kool aid man!",
		"persist": true,
		"track": true,
		"rules": [
			{
				"name": RULE_TWINS_EVOLUTION,
				"scope": SCOPE_RUN,
				"post_key": "monster.name.beetdown",
			},
		],
	},
	{
		"kind": KIND_ACHIEVEMENT,
		"id": HERD_U_LIEK_MUDKIPZ,
		"title": "Herd U Liek Mudkipz",
		"description": "Double Dewlotls!",
		"persist": true,
		"track": true,
		"rules": [
			{
				"name": RULE_TWINS_EVOLUTION,
				"scope": SCOPE_RUN,
				"post_key": "monster.name.dewlotl",
			},
		],
	},
	{
		"kind": KIND_ACHIEVEMENT,
		"id": SO_I_STARTED_BLASTING,
		"title": "So I started blasting",
		"description": "Got a level 2 Rhizuka by Day 5",
		"persist": true,
		"track": true,
		"rules": [
			{"name": RULE_GENTLEMAN_RHIZUKA, "scope": SCOPE_RUN},
		],
	},
	{
		"kind": KIND_ACHIEVEMENT,
		"id": BIG_DOG,
		"title": "Big Dog, Best Dog",
		"description": "Reach over 1 mil shield with Cinnabark",
		"persist": true,
		"track": false,
		"rules": [
			{"name": RULE_CINNABARK_SHIELD, "scope": SCOPE_BATTLE},
		],
	},
]


## Every entry of one kind, in stable order.
static func entries_of_kind(kind: String) -> Array:
	var out: Array = []
	for entry in ENTRIES:
		if str(entry.get("kind", "")) == kind:
			out.append(entry)
	return out


## Every reaction entry, in stable order.
static func reactions() -> Array:
	return entries_of_kind(KIND_REACTION)


## Every achievement entry, in stable order.
static func achievements() -> Array:
	return entries_of_kind(KIND_ACHIEVEMENT)


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
	return ""


## Battle comparison for a battle-scoped reaction, or {} when it has none.
## `strict` means "greater than"; otherwise the comparison is equality.
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
