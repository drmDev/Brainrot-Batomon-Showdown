extends RefCounted
## ToastCatalog - registered achievement and reaction toasts for developer tooling.
##
## Builds display entries from the existing evaluator registries, so the dev toast
## preview always matches what gameplay can actually show. Pure data: no nodes, no
## game state, no achievement store. Previewing an entry never changes progress or
## save data; it only builds a NotificationRequest with duplicate display allowed.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const ReactionPlayer = preload("../reactions/reaction_player.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")

const KIND_ACHIEVEMENT := NotificationRequest.KIND_ACHIEVEMENT
const KIND_REACTION := NotificationRequest.KIND_REACTION


## Every registered achievement and reaction as
## {kind, id, label, title, description}. Achievements come first, in evaluator
## order; reactions follow in registry order with duplicate ids collapsed
## (six_seven appears in both the run and battle tables).
static func entries() -> Array:
	var out: Array = []

	for definition in AchievementEvaluator.ALL_ACHIEVEMENTS:
		var id := str(definition.get("id", ""))
		if id.is_empty():
			continue
		var title := str(definition.get("title", id))
		out.append({
			"kind": KIND_ACHIEVEMENT,
			"id": id,
			"label": "Achievement - %s" % title,
			"title": title,
			"description": str(definition.get("description", "")),
		})

	var seen := {}
	for reaction in ReactionEvaluator.REACTIONS:
		_append_reaction(out, seen, reaction, true)
	for reaction in ReactionEvaluator.BATTLE_REACTIONS:
		_append_reaction(out, seen, reaction, false)

	return out


## Build the NotificationRequest used to preview an entry.
##
## allow_duplicate is true so repeated previews are shown even while the same
## toast is visible or queued. Nothing else is touched: no achievement store, no
## save data, and no game state.
static func make_request(entry: Dictionary) -> NotificationRequest:
	return NotificationRequest.new(
		str(entry.get("kind", "")),
		str(entry.get("id", "")),
		str(entry.get("title", "")),
		str(entry.get("description", "")),
		NotificationRequest.DEFAULT_DURATION_MS,
		true,
	)


## Entry matching kind + id, or {} when absent.
static func find(all_entries: Array, kind: String, id: String) -> Dictionary:
	for entry in all_entries:
		if str(entry.get("kind", "")) == kind and str(entry.get("id", "")) == id:
			return entry
	return {}


## Append one reaction entry unless its id was already registered.
static func _append_reaction(out: Array, seen: Dictionary, reaction, run_scoped: bool) -> void:
	var id := str(reaction.get("id", ""))
	if id.is_empty() or seen.has(id):
		return
	seen[id] = true
	var title := str(ReactionPlayer.REACTION_TITLES.get(id, id))
	out.append({
		"kind": KIND_REACTION,
		"id": id,
		"label": "Reaction - %s" % title,
		"title": title,
		"description": _reaction_description(reaction, run_scoped),
	})


## Representative detail text for a reaction preview. Run reactions mirror the
## [Lives, Day, Wins] / income triggers; battle reactions show the threshold.
static func _reaction_description(reaction: Dictionary, run_scoped: bool) -> String:
	if run_scoped:
		var parts: PackedStringArray = []
		if reaction.has("lives"):
			parts.append("Lives %d" % int(reaction.get("lives")))
		if reaction.has("day"):
			parts.append("Day %d" % int(reaction.get("day")))
		if reaction.has("wins"):
			parts.append("Wins %d" % int(reaction.get("wins")))
		if reaction.has("income"):
			if str(reaction.get("income_comparison", ReactionEvaluator.COMPARISON_EQUALS)) == ReactionEvaluator.COMPARISON_GREATER_THAN:
				parts.append("Income > %d" % int(reaction.get("income")))
			else:
				parts.append("Income %d" % int(reaction.get("income")))
		return ", ".join(parts)
	var value := int(reaction.get("value", 0))
	if str(reaction.get("comparison", ReactionEvaluator.COMPARISON_EQUALS)) == ReactionEvaluator.COMPARISON_GREATER_THAN:
		return "Battle total > %d" % value
	return "Battle total %d" % value
