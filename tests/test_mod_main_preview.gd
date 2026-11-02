extends "test_runner.gd"
## Regression tests for the dev toast preview's presentation wiring.
##
## The preview previously submitted the toast but bypassed the reaction sound sink,
## so previewing "It's Over 9000!" was silent while gameplay played the sound.

const ModMain = preload("../mod_main.gd")
const ToastCatalog = preload("../notifications/toast_catalog.gd")


class FakeSound:
	extends RefCounted
	var plays := 0

	func play() -> void:
		plays += 1


class FakeHost:
	extends RefCounted
	var submitted: Array = []

	func submit(request) -> int:
		submitted.append(request)
		return 0


func _preview(entry_id: String):
	var mod = ModMain.new()
	var sound = FakeSound.new()
	mod._over_9000_sound = sound
	mod._toast_catalog_script = ToastCatalog
	mod._notification_host = FakeHost.new()
	var entry := ToastCatalog.find(
		ToastCatalog.entries(),
		ToastCatalog.KIND_REACTION,
		entry_id,
	)
	mod._preview_toast(entry)
	return {"mod": mod, "sound": sound, "entry": entry}


func test_preview_over_9000_plays_sound_and_submits_toast() -> void:
	var result = _preview("over_9000")
	assert_false(result["entry"].is_empty(), "over_9000 must be in the catalog")
	assert_eq(result["sound"].plays, 1, "preview must use the gameplay sound mapping")
	assert_eq(result["mod"]._notification_host.submitted.size(), 1)
	result["mod"].free()


func test_preview_other_reaction_stays_silent_but_submits_toast() -> void:
	var result = _preview("six_seven")
	assert_false(result["entry"].is_empty(), "six_seven must be in the catalog")
	assert_eq(result["sound"].plays, 0)
	assert_eq(result["mod"]._notification_host.submitted.size(), 1)
	result["mod"].free()


func test_reaction_sound_mapping_only_plays_for_over_9000() -> void:
	var mod = ModMain.new()
	var sound = FakeSound.new()
	mod._over_9000_sound = sound
	mod._play_reaction_sound("over_9000")
	assert_eq(sound.plays, 1)
	mod._play_reaction_sound("six_nine")
	assert_eq(sound.plays, 1, "only over_9000 should have audio")
	mod.free()
