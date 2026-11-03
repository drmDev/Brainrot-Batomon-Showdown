extends RefCounted
## ToastCatalog - registered achievement and reaction toasts for developer tooling.
##
## Builds display entries from the existing evaluator registries, so the dev toast
## preview always matches what gameplay can actually show. Pure data: no nodes, no
## game state, no achievement store. Previewing an entry never changes progress or
## save data; it only builds a NotificationRequest with duplicate display allowed.

const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")
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
	for entry in ReactionEvaluator.registered_rows():
		_append_reaction(out, seen, entry["row"], str(entry["scope"]))

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


## Append one reaction entry unless its id was already registered. The title and
## description come from the reaction definition, so the preview cannot drift.
static func _append_reaction(out: Array, seen: Dictionary, reaction, scope: String) -> void:
	var id := str(reaction.get("id", ""))
	if id.is_empty() or seen.has(id):
		return
	seen[id] = true
	var title := ReactionDefinitions.title_for(id)
	out.append({
		"kind": KIND_REACTION,
		"id": id,
		"label": "Reaction - %s" % title,
		"title": title,
		"description": ReactionDefinitions.describe_trigger(reaction),
	})
