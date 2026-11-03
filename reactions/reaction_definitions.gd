extends RefCounted
## ReactionDefinitions - the single source of truth for reactions.
##
## Adding a reaction is one block in DEFINITIONS. The evaluator, the toast
## catalog, the reaction player titles, and the reaction sound table all read
## from this file, so a new reaction does not need edits in several places.
##
## Definition shape:
##   {
##     "id": String,                       # required, unique
##     "title": String,                    # toast title
##     "message": String,                  # optional, "{detail}" is replaced
##     "sound": {"file": String, "volume_db": float},  # optional
##     "triggers": [trigger, ...],         # required, at least one
##   }
##
## Trigger shape:
##   {"scope": SCOPE_RUN, "when": [condition, ...]}
##   {"scope": SCOPE_OUTCOME, "when": [condition, ...]}
##   {"scope": SCOPE_BATTLE, "total": [op, value], "metrics": [label, ...]}
##
## Condition shape:
##   [field, op, value]                    # a leaf
##   {"any": [leaf, leaf, ...]}            # at least one leaf must match
##
## Conditions in a `when` list are ANDed. A leaf matches only when the snapshot
## value is an int (the reader emits ints; anything else means "unknown").
##
## Scope decides occurrence:
##   SCOPE_RUN      once per run
##   SCOPE_OUTCOME  once per run, evaluated only at battle_over from the
##                  committed post-battle totals
##   SCOPE_BATTLE   once per battle, lowest player slot wins, first metric in
##                  BATTLE_METRIC_ORDER wins within that slot

const SCOPE_RUN := "run"
const SCOPE_BATTLE := "battle"
const SCOPE_OUTCOME := "outcome"

const OP_EQUALS := "eq"
const OP_NOT_EQUALS := "ne"
const OP_GREATER_THAN := "gt"
const OP_GREATER_OR_EQUAL := "gte"
const OP_LESS_THAN := "lt"
const OP_LESS_OR_EQUAL := "lte"

const OPS := [
	OP_EQUALS,
	OP_NOT_EQUALS,
	OP_GREATER_THAN,
	OP_GREATER_OR_EQUAL,
	OP_LESS_THAN,
	OP_LESS_OR_EQUAL,
]

## Run-snapshot fields: definition field name -> snapshot key + display label.
## `type` defaults to "int"; string fields allow only eq/ne.
const FIELDS := {
	"lives": {"key": "lives", "label": "Lives"},
	"day": {"key": "current_round", "label": "Day"},
	"wins": {"key": "current_wins", "label": "Wins"},
	"income": {"key": "income", "label": "Income"},
	"trainer": {"key": "trainer_id", "label": "Trainer", "type": "string"},
}

## Committed post-battle outcome fields (battle snapshot's `outcome`).
const OUTCOME_FIELDS := {
	"wins": {"key": "wins", "label": "Wins"},
	"lives": {"key": "lives", "label": "Lives"},
}

## Battle metric label -> unit record key. Labels are what definitions use.
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

const DEFINITIONS := [
	{
		"id": SIX_SEVEN,
		"title": "6 7",
		"triggers": [
			{
				"scope": SCOPE_RUN,
				"when": [
					["lives", OP_EQUALS, 6],
					{"any": [["day", OP_EQUALS, 7], ["wins", OP_EQUALS, 7]]},
				],
			},
			{"scope": SCOPE_RUN, "when": [["income", OP_EQUALS, 67]]},
			{"scope": SCOPE_BATTLE, "total": [OP_EQUALS, 67]},
		],
	},
	{
		"id": SIX_NINE,
		"title": "6 9",
		"triggers": [
			{
				"scope": SCOPE_RUN,
				"when": [
					["lives", OP_EQUALS, 6],
					{"any": [["day", OP_EQUALS, 9], ["wins", OP_EQUALS, 9]]},
				],
			},
			{"scope": SCOPE_RUN, "when": [["income", OP_EQUALS, 69]]},
			{"scope": SCOPE_BATTLE, "total": [OP_EQUALS, 69]},
		],
	},
	{
		"id": FOUR_TWENTY,
		"title": "Blaze It",
		"triggers": [
			{"scope": SCOPE_RUN, "when": [["income", OP_EQUALS, 420]]},
			{"scope": SCOPE_BATTLE, "total": [OP_EQUALS, 420]},
		],
	},
	{
		"id": SIX_SIX_SIX,
		"title": "Number of the Beast",
		"triggers": [
			{"scope": SCOPE_RUN, "when": [["income", OP_EQUALS, 666]]},
			{"scope": SCOPE_BATTLE, "total": [OP_EQUALS, 666]},
		],
	},
	{
		"id": OVER_9000,
		"title": "It's Over 9000!",
		"sound": {"file": "over-9000.ogg"},
		"triggers": [
			{"scope": SCOPE_RUN, "when": [["income", OP_GREATER_THAN, 9000]]},
			{
				"scope": SCOPE_BATTLE,
				"metrics": ["burn", "poison", "shock"],
				"total": [OP_GREATER_THAN, 9000],
			},
		],
	},
	{
		"id": SEVEN_OR_MORE_LIVES,
		"title": "You look great today!",
		"sound": {"file": "ff_fanfare.ogg"},
		"triggers": [
			{
				"scope": SCOPE_OUTCOME,
				"when": [["wins", OP_EQUALS, 10], ["lives", OP_GREATER_OR_EQUAL, 7]],
			},
		],
	},
	{
		"id": APES_TOGETHER,
		"title": "Apes together, strong",
		"triggers": [
			{
				"scope": SCOPE_RUN,
				"when": [
					["trainer", OP_EQUALS, "twins"],
					{
						"owns": {
							"species": "monster.name.sunsage",
							"level": [OP_GREATER_OR_EQUAL, 3],
						},
					},
				],
			},
		],
	},
]


## Toast title for a reaction id. Unknown ids fall back to the id itself.
static func title_for(id: String) -> String:
	for definition in DEFINITIONS:
		if str(definition.get("id", "")) == id:
			return str(definition.get("title", id))
	return id


## Reaction id -> sound row, for the table-driven audio player.
static func sounds() -> Dictionary:
	var out := {}
	for definition in DEFINITIONS:
		var id := str(definition.get("id", ""))
		var sound = definition.get("sound")
		if not id.is_empty() and sound is Dictionary:
			out[id] = sound
	return out


## Human-readable description of one trigger, for the dev toast preview.
static func describe_trigger(trigger: Dictionary) -> String:
	var scope := str(trigger.get("scope", ""))
	if scope == SCOPE_RUN:
		return _describe_conditions(trigger.get("when", []), FIELDS)
	if scope == SCOPE_OUTCOME:
		return _describe_conditions(trigger.get("when", []), OUTCOME_FIELDS)
	if scope == SCOPE_BATTLE:
		var total = trigger.get("total")
		if total is Array and total.size() == 2:
			var op := str(total[0])
			var value := int(total[1])
			if op == OP_GREATER_THAN:
				return "Battle total > %d" % value
			return "Battle total %d" % value
	return ""


static func _describe_conditions(conditions, fields: Dictionary) -> String:
	if not conditions is Array:
		return ""
	var parts: PackedStringArray = []
	for condition in conditions:
		if condition is Dictionary and condition.has("any"):
			var any_list = condition["any"]
			if any_list is Array:
				for sub in any_list:
					if sub is Array:
						var text := _describe_leaf(sub, fields)
						if not text.is_empty():
							parts.append(text)
		elif condition is Dictionary and condition.has("owns"):
			var spec = condition["owns"]
			if spec is Dictionary:
				var level_condition = spec.get("level")
				var level := 1
				if level_condition is Array and level_condition.size() == 2:
					level = int(level_condition[1])
				parts.append("%s level %d" % [
					_species_label(str(spec.get("species", ""))),
					level,
				])
		elif condition is Array:
			var text := _describe_leaf(condition, fields)
			if not text.is_empty():
				parts.append(text)
	return ", ".join(parts)


static func _describe_leaf(condition: Array, fields: Dictionary) -> String:
	if condition.size() != 3:
		return ""
	var field := str(condition[0])
	var op := str(condition[1])
	var info = fields.get(field)
	if not info is Dictionary:
		return ""
	var label := str(info.get("label", field))
	if str(info.get("type", "int")) == "string":
		var text := str(condition[2])
		if op == OP_NOT_EQUALS:
			return "%s != %s" % [label, text]
		return "%s %s" % [label, text]
	var value := int(condition[2])
	match op:
		OP_EQUALS:
			return "%s %d" % [label, value]
		OP_NOT_EQUALS:
			return "%s != %d" % [label, value]
		OP_GREATER_THAN:
			return "%s > %d" % [label, value]
		OP_GREATER_OR_EQUAL:
			return "%s >= %d" % [label, value]
		OP_LESS_THAN:
			return "%s < %d" % [label, value]
		OP_LESS_OR_EQUAL:
			return "%s <= %d" % [label, value]
	return "%s %d" % [label, value]


## "monster.name.sunsage" -> "Sunsage" for preview text.
static func _species_label(species_key: String) -> String:
	if species_key.is_empty():
		return "?"
	var name_key := species_key
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	return name_key.capitalize()
