extends "test_runner.gd"
## Unit tests for catalog/trainer_icons.gd (adapted from Creature Comforts).

const TrainerIcons = preload("../catalog/trainer_icons.gd")


## Stand-in for res://game/trainers/trainer_portrait.gd: a script with a Kind enum
## and a static crop_for(trainer, kind), exactly the shape the game exposes.
class FakePortrait:
	extends RefCounted
	enum Kind { SMALL, LARGE }
	static var crop: Texture2D = null
	static var last_kind := -1

	static func crop_for(_trainer, kind) -> Texture2D:
		last_kind = kind
		return crop


## A portrait script without crop_for, to exercise the property fallback.
class NoCropPortrait:
	extends RefCounted
	enum Kind { SMALL }


class FakeTrainer:
	extends RefCounted
	var id := ""
	var portrait: Texture2D = null


class FakeDb:
	extends RefCounted
	var trainers := {}
	var lookups := 0

	func get_trainer_by_id(id: String):
		lookups += 1
		return trainers.get(id)


func _texture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))


func _db(trainer_id: String, portrait: Texture2D = null) -> FakeDb:
	var db := FakeDb.new()
	var trainer := FakeTrainer.new()
	trainer.id = trainer_id
	trainer.portrait = portrait
	db.trainers[trainer_id] = trainer
	return db


func test_icon_uses_game_portrait_crop_small() -> void:
	TrainerIcons.reset()
	var tex := _texture()
	FakePortrait.crop = tex
	assert_eq(TrainerIcons.icon_for("chef", _db("chef"), FakePortrait), tex)
	assert_eq(FakePortrait.last_kind, FakePortrait.Kind.SMALL)


func test_icon_falls_back_to_trainer_texture_property() -> void:
	TrainerIcons.reset()
	var tex := _texture()
	assert_eq(TrainerIcons.icon_for("chef", _db("chef", tex), NoCropPortrait), tex)


func test_icon_falls_back_when_crop_returns_null() -> void:
	TrainerIcons.reset()
	var tex := _texture()
	FakePortrait.crop = null
	assert_eq(TrainerIcons.icon_for("chef", _db("chef", tex), FakePortrait), tex)


func test_unknown_trainer_is_null() -> void:
	TrainerIcons.reset()
	FakePortrait.crop = _texture()
	assert_eq(TrainerIcons.icon_for("missing", _db("chef"), FakePortrait), null)


func test_blank_trainer_id_is_null() -> void:
	TrainerIcons.reset()
	FakePortrait.crop = _texture()
	assert_eq(TrainerIcons.icon_for("", _db("chef"), FakePortrait), null)
	assert_eq(TrainerIcons.icon_for("   ", _db("chef"), FakePortrait), null)


func test_without_database_is_null() -> void:
	TrainerIcons.reset()
	assert_eq(TrainerIcons.icon_for("chef", null, FakePortrait), null)


func test_no_texture_anywhere_is_null() -> void:
	TrainerIcons.reset()
	FakePortrait.crop = null
	assert_eq(TrainerIcons.icon_for("chef", _db("chef"), FakePortrait), null)


func test_found_portrait_is_cached() -> void:
	TrainerIcons.reset()
	var tex := _texture()
	FakePortrait.crop = tex
	var db := _db("chef")
	assert_eq(TrainerIcons.icon_for("chef", db, FakePortrait), tex)
	assert_eq(TrainerIcons.icon_for("chef", db, FakePortrait), tex)
	assert_eq(db.lookups, 1)


func test_miss_is_not_cached() -> void:
	TrainerIcons.reset()
	FakePortrait.crop = null
	var db := _db("chef")
	assert_eq(TrainerIcons.icon_for("chef", db, FakePortrait), null)
	var tex := _texture()
	FakePortrait.crop = tex
	assert_eq(TrainerIcons.icon_for("chef", db, FakePortrait), tex)
