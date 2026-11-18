extends "test_runner.gd"
## Unit tests for notifications/toast_catalog.gd (dev toast preview data).
##
## The catalog must expose every registered reaction exactly once and build
## duplicate-allowed requests for repeated previews.

const ToastCatalog = preload("../notifications/toast_catalog.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")


func _reaction_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if str(entry.get("kind", "")) == NotificationRequest.KIND_REACTION:
			out.append(entry)
	return out


func test_entries_include_every_registered_reaction_once() -> void:
	var entries := ToastCatalog.entries()
	var expected_ids := {}
	for registered in Catalog.reactions():
		expected_ids[str(registered.get("id", ""))] = true

	for id in expected_ids:
		var found := ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, id)
		assert_false(found.is_empty(), "missing reaction " + id)
		assert_false(str(found.get("title", "")).is_empty(), "missing title for " + id)

	var reactions := _reaction_entries(entries)
	assert_eq(reactions.size(), expected_ids.size(), "reaction ids must not duplicate")



func test_every_entry_has_a_non_empty_label_and_title() -> void:
	for entry in ToastCatalog.entries():
		assert_false(str(entry.get("label", "")).is_empty(), "empty label for " + str(entry.get("id", "")))
		assert_false(str(entry.get("title", "")).is_empty(), "empty title for " + str(entry.get("id", "")))


func test_make_request_allows_repeated_previews() -> void:
	var entry: Dictionary = ToastCatalog.entries()[0]
	var request = ToastCatalog.make_request(entry)
	assert_true(request.allow_duplicate, "preview requests must bypass dedupe")
	assert_true(request.is_valid())


func test_make_request_copies_entry_presentation() -> void:
	var entry := {
		"kind": NotificationRequest.KIND_REACTION,
		"id": Catalog.FOUR_TWENTY,
		"label": "Reaction - Blaze It",
		"title": "Blaze It",
		"description": "Battle total 420",
	}
	var request = ToastCatalog.make_request(entry)
	assert_eq(request.kind, NotificationRequest.KIND_REACTION)
	assert_eq(
		request.event_key,
		NotificationRequest.key_for(
			NotificationRequest.KIND_REACTION,
			Catalog.FOUR_TWENTY,
		),
	)
	assert_eq(request.header, NotificationRequest.HEADER_UNLOCKED)
	assert_eq(request.title, "Blaze It")
	assert_eq(request.description, "Battle total 420")
	assert_eq(request.id, Catalog.FOUR_TWENTY)
	assert_eq(request.icon, "420")


func test_find_requires_kind_and_id() -> void:
	var entries := ToastCatalog.entries()
	assert_true(ToastCatalog.find(entries, "other_kind", "oh_yeah").is_empty())
	assert_true(ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, "not_real").is_empty())


func test_entries_include_species_for_monster_reactions() -> void:
	var entries := ToastCatalog.entries()
	var apes := ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, Catalog.APES_TOGETHER)
	assert_eq(str(apes.get("species", "")), "monster.name.sunsage")
	var numeric := ToastCatalog.find(entries, NotificationRequest.KIND_REACTION, Catalog.SIX_SEVEN)
	assert_eq(str(numeric.get("species", "")), "")


func test_reaction_uses_unlocked_header() -> void:
	assert_eq(
		NotificationRequest.header_for(NotificationRequest.KIND_REACTION),
		NotificationRequest.HEADER_UNLOCKED,
	)
	assert_eq(NotificationRequest.header_for("other_kind"), "")
