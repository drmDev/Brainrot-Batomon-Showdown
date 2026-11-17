extends "test_runner.gd"
## Unit tests for catalog/species_icons.gd (adapted from Creature Comforts).

const SpeciesIcons = preload("../catalog/species_icons.gd")


## Stand-in for a species resource: the icon lookup key lives on name_key/id.
class FakeSpecies:
	extends RefCounted
	var name_key := ""
	var id := ""
	var texture: Texture2D = null


## Stand-in for the GameDatabase autoload.
class FakeDb:
	extends RefCounted
	var species: Array = []

	func get_all_species() -> Array:
		return species


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))


func _db(species_list: Array) -> FakeDb:
	var db := FakeDb.new()
	db.species = species_list
	return db


func _species(name_key: String, texture: Texture2D, id := "") -> FakeSpecies:
	var species := FakeSpecies.new()
	species.name_key = name_key
	species.id = id
	species.texture = texture
	return species


func test_icon_for_returns_texture_by_name_key() -> void:
	SpeciesIcons.reset()
	var tex := _texture()
	var db := _db([_species("monster.name.leafleap", tex)])
	assert_eq(SpeciesIcons.icon_for("monster.name.leafleap", db), tex)


func test_icon_for_is_case_insensitive() -> void:
	SpeciesIcons.reset()
	var tex := _texture()
	var db := _db([_species("monster.name.leafleap", tex)])
	assert_eq(SpeciesIcons.icon_for("MONSTER.NAME.LEAFLEAP", db), tex)


func test_icon_for_accepts_species_id_alias() -> void:
	SpeciesIcons.reset()
	var tex := _texture()
	var db := _db([_species("monster.name.leafleap", tex, "leafleap")])
	assert_eq(SpeciesIcons.icon_for("leafleap", db), tex)


func test_icon_for_unknown_key_is_null() -> void:
	SpeciesIcons.reset()
	var db := _db([_species("monster.name.leafleap", _texture())])
	assert_eq(SpeciesIcons.icon_for("monster.name.missing", db), null)


func test_icon_for_without_database_is_null() -> void:
	SpeciesIcons.reset()
	assert_eq(SpeciesIcons.icon_for("monster.name.leafleap", null), null)


func test_icon_for_ignores_non_texture() -> void:
	SpeciesIcons.reset()
	var species := FakeSpecies.new()
	species.name_key = "monster.name.leafleap"
	assert_eq(SpeciesIcons.icon_for("monster.name.leafleap", _db([species])), null)


func test_icon_for_empty_key_is_null() -> void:
	SpeciesIcons.reset()
	var db := _db([_species("monster.name.leafleap", _texture())])
	assert_eq(SpeciesIcons.icon_for("   ", db), null)


## A lookup made before GameDatabase is ready must not cache the empty result:
## the next call retries and finds the icon.
func test_empty_database_is_not_cached() -> void:
	SpeciesIcons.reset()
	assert_eq(SpeciesIcons.icon_for("monster.name.leafleap", _db([])), null)
	var tex := _texture()
	var ready := _db([_species("monster.name.leafleap", tex)])
	assert_eq(SpeciesIcons.icon_for("monster.name.leafleap", ready), tex)
