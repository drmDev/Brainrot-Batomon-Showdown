extends "test_runner.gd"
## Unit tests for core/mod_config.gd (the Mod Volume setting).

const ModConfig = preload("../core/mod_config.gd")

const TEST_STORE := "user://brain_rot/test_mod_config.cfg"


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_STORE))


func test_default_volume_is_100() -> void:
	var config = ModConfig.new()
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)


func test_set_mod_volume_clamps_to_range() -> void:
	var config = ModConfig.new()
	config.set_mod_volume(150)
	assert_eq(config.mod_volume(), ModConfig.MOD_VOLUME_MAX)
	config.set_mod_volume(-10)
	assert_eq(config.mod_volume(), ModConfig.MOD_VOLUME_MIN)


func test_set_mod_volume_persists_and_reloads() -> void:
	_cleanup()
	var config = ModConfig.new()
	config.use_store(TEST_STORE)
	config.set_mod_volume(40)
	assert_eq(config.mod_volume(), 40)

	var reloaded = ModConfig.new()
	reloaded.use_store(TEST_STORE)
	assert_eq(reloaded.mod_volume(), 40)
	_cleanup()


func test_missing_store_keeps_default() -> void:
	_cleanup()
	var config = ModConfig.new()
	config.use_store(TEST_STORE)
	assert_eq(config.mod_volume(), ModConfig.DEFAULT_MOD_VOLUME)
	_cleanup()


func test_setting_same_volume_is_a_no_op() -> void:
	_cleanup()
	var config = ModConfig.new()
	config.use_store(TEST_STORE)
	config.set_mod_volume(100)
	assert_false(FileAccess.file_exists(TEST_STORE), "no-op set must not write the store")
	_cleanup()