extends RefCounted
## ReactionText - the single source of truth for every reaction line a player reads.
##
## Detection and presentation are separate: the catalog/evaluator produce a match
## Dictionary ({id, case, params, species_key}), and this file turns that match into
## the toast body and the log detail. The dev preview calls the same render(), so it
## cannot drift from what gameplay shows.
##
## Wording lives entirely in TEMPLATES, keyed by reaction id then case. To reword a
## reaction, edit the string here - no detection code, UI, or evaluator changes.
##
## Placeholders (fill-in-the-blank):
##   {species}  -> species display name, resolved from params.species_key
##   {metric}   -> metric word, resolved from params.metric via METRIC_WORDS
##   {value}    -> abbreviated number (1.2M / 9.0K / raw) from params.value
##   {level}    -> integer level from params.level
##   {income}   -> integer shop income from params.income
##   {lives}    -> integer lives from params.lives
##   {day}      -> integer day from params.day
##   {wins}     -> integer wins from params.wins

const Catalog = preload("brain_rot_catalog.gd")

## All fill-in-the-blank template names. `placeholders()` only reports these.
const KNOWN_PLACEHOLDERS := ["species", "metric", "value", "income"]

## Reaction id -> case -> template. Case names come from the catalog/evaluator, not
## from here; render() warns when an id/case is missing and falls back to the title.
const TEMPLATES := {
	"six_seven": {
		"lives_day_wins": "6 lives left, 7 wins, Day 7.",
		"lives_day": "6 lives left, Day 7.",
		"lives_wins": "6 lives left, 7 wins.",
		"income": "Your shop income hit exactly 67.",
		"battle": "{species} contributed exactly 67 {metric} in battle.",
	},
	"six_nine": {
		"lives_day_wins": "6 lives left, 9 wins, Day 9.",
		"lives_day": "6 lives left, Day 9.",
		"lives_wins": "6 lives left, 9 wins.",
		"income": "Your shop income hit exactly 69.",
		"battle": "{species} contributed exactly 69 {metric} in battle.",
	},
	"four_twenty": {
		"income": "Your shop income hit exactly 420.",
		"battle": "{species} contributed exactly 420 {metric} in battle.",
	},
	"six_six_six": {
		"income": "Your shop income hit exactly 666.",
		"battle": "{species} contributed exactly 666 {metric} in battle.",
	},
	"over_9000": {
		"income": "Your shop income is {income}!",
		"battle": "{species} hit {value} {metric} in battle.",
	},
	"apes_together": {
		"owned": "With Twins, made two Sunsages!",
	},
	"oh_yeah": {
		"owned": "(Kool-Aid Man): Here comes the Beetdown!",
	},
	"herd_u_liek_mudkipz": {
		"owned": "A wizard has turned you into a mudkip. Is this awesome (Y/N)?",
	},
	"double_rainbow": {
		"owned": "As Twins, made double shinies!",
	},
	"harambe": {
		"sold": "Sarudo has been sold. Gone, but never forgotten. <3",
	},
	"trogdor": {
		"owned": "Level 3 Furnadon!",
	},
	"not_the_bees": {
		"owned": "Bumblebolt reminds you to just bee yourself.",
	},
	"tetsuo": {
		"gained": "Tengusto is coming close to reaching his final form!",
	},
	"big_dog_best_dog": {
		"battle": "{species} put up {value} shield in battle. What a good boy!",
	},
}

## Reaction id -> short unlock-condition description, shown on the Cheevos tab
## only for completed reactions (undiscovered ones keep their conditions secret).
const DESCRIPTIONS := {
	"six_seven": "Reach day 7 with 6 lives, or 7 wins with 6 lives.",
	"six_nine": "Reach day 9 with 6 lives, or 9 wins with 6 lives.",
	"four_twenty": "Reach 420 shop income.",
	"six_six_six": "Reach 666 shop income.",
	"over_9000": "Reach over 9000 shop income.",
	"apes_together": "Own two Sunsages as Twins.",
	"big_dog_best_dog": "Put up over 1,000,000 shield with a Cinnabark.",
	"oh_yeah": "Own a level-3 Beetdown.",
	"herd_u_liek_mudkipz": "Own a level-3 Dewlotl.",
	"double_rainbow": "Own a level-3 shiny monster as Twins.",
	"harambe": "Sell a Sarudo.",
	"trogdor": "Own a level-3 Furnadon.",
	"not_the_bees": "Own a level-3 Bumblebolt.",
	"tetsuo": "Give a Tengusto a Poison or Shock permanent buff.",
}

## Battle metric label -> the word used in templates.
const METRIC_WORDS := {
	"damage": "damage",
	"heal": "healing",
	"shield": "shield",
	"burn": "burn",
	"poison": "poison",
	"shock": "shock",
}


## The unlock-condition description for a reaction, or "" when unknown.
static func description_for(id: String) -> String:
	return str(DESCRIPTIONS.get(id, ""))


## Case names registered for a reaction, in TEMPLATES order.
static func cases(id: String) -> Array:
	var table = TEMPLATES.get(id)
	if not table is Dictionary:
		return []
	return table.keys()


## Which placeholders a template uses, in the canonical KNOWN_PLACEHOLDERS order.
## The dev preview shows one input per placeholder returned here.
static func placeholders(id: String, case_name: String) -> Array:
	var template := template_for(id, case_name)
	var out: Array = []
	for placeholder in KNOWN_PLACEHOLDERS:
		if template.contains("{" + placeholder + "}"):
			out.append(placeholder)
	return out


## User-facing line for a match. Missing id/case falls back to the reaction title and
## warns, so a bad match is still visible but never crashes.
static func render(id: String, case_name: String, params: Dictionary) -> String:
	var template := template_for(id, case_name)
	if template.is_empty():
		push_warning("Brain Rot: no reaction text for %s/%s" % [id, case_name])
		return Catalog.title_for(id)
	return _fill(template, params)


## The raw template, or "" when the id/case is unknown.
static func template_for(id: String, case_name: String) -> String:
	var table = TEMPLATES.get(id)
	if not table is Dictionary:
		return ""
	var value = table.get(case_name)
	return str(value) if value != null else ""


static func _fill(template: String, params: Dictionary) -> String:
	var out := template
	for placeholder in KNOWN_PLACEHOLDERS:
		var token: String = "{" + str(placeholder) + "}"
		if out.contains(token):
			out = out.replace(token, value_for(placeholder, params))
	return out


## Value for one placeholder, as a String. Missing/unknown values become "".
static func value_for(placeholder: String, params: Dictionary) -> String:
	match placeholder:
		"species":
			return format_species_name(str(params.get("species_key", "")))
		"metric":
			return metric_word(str(params.get("metric", "")))
		"value":
			return abbreviate_number(int(params.get("value", 0)))
		"income":
			return str(int(params.get("income", 0)))
	return ""


## Metric label -> natural word, or the label itself when unknown.
static func metric_word(label: String) -> String:
	return METRIC_WORDS.get(label, label)


## Abbreviate a large number for the toast: 1,000,000+ becomes "1.0M", 1,000+ becomes
## "1.0K". Smaller values are shown as-is.
static func abbreviate_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (float(value) / 1000.0)
	return str(value)


## Species key -> display name ("monster.name.beetdown" -> "Beetdown").
## Mirrors Creature Comforts' log_formatter.format_species_name: prefer a
## TranslationServer entry, then strip the key prefix and capitalize.
static func format_species_name(species_key: String) -> String:
	if species_key.is_empty():
		return "Unknown"
	if TranslationServer.has_method("translate"):
		var translated := TranslationServer.translate(species_key)
		if translated != species_key:
			return translated
	var name_key := species_key
	if "." in name_key:
		name_key = name_key.split(".")[-1]
	return name_key.capitalize()
