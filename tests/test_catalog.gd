extends "test_runner.gd"
## Schema tests for catalog/brain_rot_catalog.gd.
##
## These check the metadata invariants and that every reaction's check function is
## reachable. Per-reaction behavior is covered by test_reaction_evaluator.gd.

const Catalog = preload("../catalog/brain_rot_catalog.gd")


func test_ids_are_unique_across_kinds() -> void:
	var seen := {}
	for entry in Catalog.ENTRIES:
		var id := str(entry.get("id", ""))
		assert_false(id.is_empty(), "empty id")
		assert_false(seen.has(id), "duplicate id across kinds: " + id)
		seen[id] = true
		assert_false(str(entry.get("title", "")).is_empty(), "missing title for " + id)
		assert_false(str(entry.get("description", "")).is_empty(), "missing description for " + id)
		var kind := str(entry.get("kind", ""))
		assert_true(
			kind == Catalog.KIND_ACHIEVEMENT or kind == Catalog.KIND_REACTION,
			"%s: unknown kind %s" % [id, kind]
		)


func test_persist_flags_match_kind() -> void:
	for entry in Catalog.ENTRIES:
		var id := str(entry.get("id", ""))
		var persist = entry.get("persist")
		assert_true(typeof(persist) == TYPE_BOOL, "%s: persist must be a bool" % id)
		if str(entry.get("kind", "")) == Catalog.KIND_ACHIEVEMENT:
			assert_true(bool(persist), "%s: achievements must persist" % id)
		else:
			assert_false(bool(persist), "%s: reactions must not persist" % id)


func test_every_achievement_has_known_rules() -> void:
	for entry in Catalog.achievements():
		var id := str(entry.get("id", ""))
		var rules = entry.get("rules")
		assert_true(rules is Array, "missing rules for " + id)
		if not rules is Array:
			continue
		assert_gt(rules.size(), 0, "no rules for " + id)
		for rule in rules:
			var name := str(rule.get("name", ""))
			assert_true(Catalog.RULES.has(name), "%s: unknown rule %s" % [id, name])
			var scope := str(rule.get("scope", ""))
			assert_true(
				scope == Catalog.SCOPE_RUN or scope == Catalog.SCOPE_BATTLE,
				"%s: rule %s has unknown scope %s" % [id, name, scope]
			)


func test_every_reaction_has_scopes() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		var scopes = entry.get("scopes")
		assert_true(scopes is Array, "missing scopes for " + id)
		if not scopes is Array:
			continue
		assert_gt(scopes.size(), 0, "no scopes for " + id)
		for scope in scopes:
			assert_true(
				[Catalog.SCOPE_RUN, Catalog.SCOPE_BATTLE, Catalog.SCOPE_OUTCOME].has(str(scope)),
				"%s: unknown scope %s" % [id, str(scope)]
			)


func test_every_sound_file_exists() -> void:
	for entry in Catalog.ENTRIES:
		var sound = entry.get("sound")
		if not sound is Dictionary:
			continue
		var file_name := str(sound.get("file", ""))
		assert_false(file_name.is_empty(), "empty sound file for " + str(entry.get("id", "")))
		var path := "res://assets/sounds/" + file_name
		assert_true(FileAccess.file_exists(path), "missing sound file: " + path)


func test_run_checks_are_reachable() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		if not entry.get("scopes", []).has(Catalog.SCOPE_RUN):
			continue
		# An empty snapshot never matches, but the dispatcher must return a String.
		assert_true(typeof(Catalog.run_detail(id, {})) == TYPE_STRING, id)


func test_battle_checks_are_reachable() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		if not entry.get("scopes", []).has(Catalog.SCOPE_BATTLE):
			continue
		var rule := Catalog.battle_rule(id)
		assert_false(rule.is_empty(), "missing battle rule for " + id)
		assert_true(rule.get("metrics") is Array, "missing metrics for " + id)


func test_outcome_checks_are_reachable() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		if not entry.get("scopes", []).has(Catalog.SCOPE_OUTCOME):
			continue
		assert_true(typeof(Catalog.outcome_detail(id, {})) == TYPE_STRING, id)


func test_registered_rows_cover_every_scope() -> void:
	var seen := {}
	for row in Catalog.registered_rows():
		seen["%s|%s" % [str(row["row"].get("id", "")), str(row["scope"])]] = true
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		for scope in entry.get("scopes", []):
			assert_true(seen.has("%s|%s" % [id, str(scope)]), "%s missing %s" % [id, str(scope)])
