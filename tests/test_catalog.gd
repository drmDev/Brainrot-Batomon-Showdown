extends "test_runner.gd"
## Schema tests for catalog/brain_rot_catalog.gd and its reaction text table.

const Catalog = preload("../catalog/brain_rot_catalog.gd")
const ReactionText = preload("../catalog/reaction_text.gd")
const NotificationRequest = preload("../notifications/notification_request.gd")


func test_ids_are_unique() -> void:
	var seen := {}
	for entry in Catalog.ENTRIES:
		var id := str(entry.get("id", ""))
		assert_false(id.is_empty(), "empty id")
		assert_false(seen.has(id), "duplicate id: " + id)
		seen[id] = true
		assert_false(str(entry.get("title", "")).is_empty(), "missing title for " + id)
		assert_eq(str(entry.get("kind", "")), Catalog.KIND_REACTION, "%s: must be a reaction" % id)


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
				[Catalog.SCOPE_RUN, Catalog.SCOPE_BATTLE].has(str(scope)),
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
		# An empty snapshot never matches, but the dispatcher must return a Dictionary.
		assert_true(Catalog.run_match(id, {}) is Dictionary, id)


func test_battle_checks_are_reachable() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		if not entry.get("scopes", []).has(Catalog.SCOPE_BATTLE):
			continue
		var rule := Catalog.battle_rule(id)
		assert_false(rule.is_empty(), "missing battle rule for " + id)
		assert_true(rule.get("metrics") is Array, "missing metrics for " + id)


func test_every_reaction_has_text_templates() -> void:
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		assert_gt(ReactionText.cases(id).size(), 0, "missing reaction text for " + id)
		for case_name in ReactionText.cases(id):
			var template := ReactionText.template_for(id, case_name)
			assert_false(template.is_empty(), "empty template for %s/%s" % [id, case_name])


func test_every_template_placeholder_is_known() -> void:
	var regex := RegEx.new()
	regex.compile("\\{(\\w+)\\}")
	for id in ReactionText.TEMPLATES:
		for case_name in ReactionText.TEMPLATES[id]:
			var template := str(ReactionText.TEMPLATES[id][case_name])
			for m in regex.search_all(template):
				assert_true(
					ReactionText.KNOWN_PLACEHOLDERS.has(str(m.get_string(1))),
					"unknown placeholder in %s/%s: %s" % [id, case_name, m.get_string(0)]
				)


func test_registered_rows_cover_every_scope() -> void:
	var seen := {}
	for row in Catalog.registered_rows():
		seen["%s|%s" % [str(row["row"].get("id", "")), str(row["scope"])]] = true
	for entry in Catalog.reactions():
		var id := str(entry.get("id", ""))
		for scope in entry.get("scopes", []):
			assert_true(seen.has("%s|%s" % [id, str(scope)]), "%s missing %s" % [id, str(scope)])


func test_every_entry_has_short_icon_text() -> void:
	for entry in Catalog.ENTRIES:
		var id := str(entry.get("id", ""))
		var icon := Catalog.icon_for(id)
		assert_false(icon.is_empty(), "empty icon for " + id)
		assert_true(icon.length() <= 4, "icon too long for " + id + ": " + icon)


func test_non_monster_reactions_have_icon_textures() -> void:
	var expected := {
		Catalog.SIX_SEVEN: "67.png",
		Catalog.SIX_NINE: "nice.png",
		Catalog.FOUR_TWENTY: "snoop420.png",
		Catalog.SIX_SIX_SIX: "666.png",
		Catalog.OVER_9000: "over9000.png",
		Catalog.DOUBLE_RAINBOW: "dubRainbow.png",
	}
	for id in expected:
		var path := "res://assets/icons/" + str(expected[id])
		assert_true(FileAccess.file_exists(path), "missing icon: " + path)
		var request = NotificationRequest.new(NotificationRequest.KIND_REACTION, id, "title", "detail")
		assert_true(request.icon_texture is Texture2D, "missing texture for " + id)


func test_monster_reactions_do_not_author_icon_file() -> void:
	for id in [Catalog.APES_TOGETHER, Catalog.BIG_DOG, Catalog.OH_YEAH, Catalog.HERD_U_LIEK_MUDKIPZ, Catalog.HARAMBE]:
		assert_eq(str(Catalog.entry(id).get("icon_file", "")), "", id)


func test_species_metadata_is_a_valid_name_key_when_present() -> void:
	for entry in Catalog.ENTRIES:
		if not entry.has("species"):
			continue
		var id := str(entry.get("id", ""))
		var species := str(entry.get("species", ""))
		assert_false(species.is_empty(), "empty species for " + id)
		assert_true(species.begins_with("monster.name."), "species must be a name_key for " + id)


func test_monster_run_reactions_have_species() -> void:
	assert_eq(str(Catalog.entry(Catalog.APES_TOGETHER).get("species", "")), "monster.name.sunsage")
	assert_eq(str(Catalog.entry(Catalog.OH_YEAH).get("species", "")), "monster.name.beetdown")
	assert_eq(str(Catalog.entry(Catalog.HERD_U_LIEK_MUDKIPZ).get("species", "")), "monster.name.dewlotl")
	assert_eq(str(Catalog.entry(Catalog.HARAMBE).get("species", "")), "monster.name.sarudo")


func test_big_dog_has_static_cinnabark_species() -> void:
	assert_eq(str(Catalog.entry(Catalog.BIG_DOG).get("species", "")), "monster.name.cinnabark")


func test_explicit_icon_wins_over_derived() -> void:
	assert_eq(Catalog.icon_for(Catalog.SIX_SEVEN), "67")
	assert_eq(Catalog.icon_for(Catalog.FOUR_TWENTY), "420")
	assert_eq(Catalog.icon_for(Catalog.OVER_9000), "9000")


func test_icon_derivation_from_unknown_ids() -> void:
	assert_eq(Catalog.icon_for("six_seven_extra"), "67")
	assert_eq(Catalog.icon_for("not_real_id"), "NRI")
	assert_eq(Catalog.icon_for(""), "?")
