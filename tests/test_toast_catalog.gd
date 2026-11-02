extends "test_runner.gd"
## Unit tests for notifications/toast_catalog.gd (dev toast preview data).
##
## The catalog must expose every registered achievement and reaction, exactly
## once, and build duplicate-allowed requests for repeated previews.

const ToastCatalog = preload("../notifications/toast_catalog.gd")
const AchievementEvaluator = preload("../achievements/achievement_evaluator.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")


func _achievement_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if str(entry.get("kind", "")) == NotificationRequest.KIND_ACHIEVEMENT:
			out.append(entry)
	return out


func _reaction_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if str(entry.get("kind", "")) == NotificationRequest.KIND_REACTION:
			out.append(entry)
	return out


func test_entries_include_every_registered_achievement() -> void:
	var entries := ToastCatalog.entries()
	for definition in AchievementEvaluator.ALL_ACHIEVEMENTS:
		var id := str(definition.get("id", ""))
		var found := ToastCatalog.find(entries, NotificationRequest.KIND_ACHIEVEMENT, id)
		assert_false(found.is_empty(), "missing achievement " + id)
		assert_eq(str(found.get("title", "")), str(definition.get("title", "")))
		assert_eq(str(found.get("description", "")), str(definition.get("description", "")))


func test_entries_include_every_registered_reaction_once() -> void:
	var entries := ToastCatalog.entries()
	var expected_ids := {}
	for registered in ReactionEvaluator.registered_rows():
		expected_ids[str(registered["row"].get("id", ""))] = true

	for id in expected_ids:
		var found := ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, id)
		assert_false(found.is_empty(), "missing reaction " + id)
		assert_false(str(found.get("title", "")).is_empty(), "missing title for " + id)

	var reactions := _reaction_entries(entries)
	assert_eq(reactions.size(), expected_ids.size(), "reaction ids must not duplicate")


func test_flawless_victory_preview_uses_committed_totals() -> void:
	var entries := ToastCatalog.entries()
	var found := ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, "flawless_victory")
	assert_false(found.is_empty(), "flawless_victory must be in the catalog")
	assert_eq(str(found.get("title", "")), "Flawless Victory")
	assert_eq(str(found.get("description", "")), "Wins 10, Lives 10")


func test_every_entry_has_a_non_empty_label_and_title() -> void:
	for entry in ToastCatalog.entries():
		assert_false(str(entry.get("label", "")).is_empty(), "empty label for " + str(entry.get("id", "")))
		assert_false(str(entry.get("title", "")).is_empty(), "empty title for " + str(entry.get("id", "")))


func test_achievement_entries_precede_reaction_entries() -> void:
	var entries := ToastCatalog.entries()
	assert_gt(_achievement_entries(entries).size(), 0)
	assert_gt(_reaction_entries(entries).size(), 0)
	assert_eq(
		str(entries[0].get("kind", "")),
		NotificationRequest.KIND_ACHIEVEMENT,
		"achievements should be listed first"
	)


func test_make_request_allows_repeated_previews() -> void:
	var entry: Dictionary = ToastCatalog.entries()[0]
	var request = ToastCatalog.make_request(entry)
	assert_true(request.allow_duplicate, "preview requests must bypass dedupe")
	assert_true(request.is_valid())


func test_make_request_copies_entry_presentation() -> void:
	var entry := {
		"kind": NotificationRequest.KIND_REACTION,
		"id": "four_twenty",
		"label": "Reaction - Blaze It",
		"title": "Blaze It",
		"description": "Battle total 420",
	}
	var request = ToastCatalog.make_request(entry)
	assert_eq(request.kind, NotificationRequest.KIND_REACTION)
	assert_eq(request.event_key, NotificationRequest.key_for(NotificationRequest.KIND_REACTION, "four_twenty"))
	assert_eq(request.header, NotificationRequest.HEADER_REACTION)
	assert_eq(request.title, "Blaze It")
	assert_eq(request.description, "Battle total 420")


func test_find_requires_kind_and_id() -> void:
	var entries := ToastCatalog.entries()
	assert_true(ToastCatalog.find(entries, NotificationRequest.KIND_ACHIEVEMENT, "not_real").is_empty())
	assert_true(ToastCatalog.find(entries, "other_kind", "oh_yeah").is_empty())
