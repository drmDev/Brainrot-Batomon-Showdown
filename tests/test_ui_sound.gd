extends "test_runner.gd"
## Unit tests for audio/ui_sound.gd (adapted from Creature Comforts).
##
## The test runner executes before the scene tree is live, so playback tests avoid
## an active tree and check setup/guard/path logic instead.

const UiSound = preload("../audio/ui_sound.gd")


func test_play_on_detached_host_creates_no_player() -> void:
	var host := Node.new()
	var sound = UiSound.new()
	sound.setup(host, "over-9000.ogg")
	sound.play()
	assert_eq(host.get_child_count(), 0)
	host.free()


## Two sounds on one host must not share a player, or the second silently plays
## the first one's stream.
func test_two_instances_use_distinct_player_names() -> void:
	var host := Node.new()
	var first = UiSound.new()
	first.setup(host, "over-9000.ogg")
	var second = UiSound.new()
	second.setup(host, "other.ogg")
	assert_ne(first._player_name, second._player_name)
	host.free()


func test_enabled_gate_is_consulted() -> void:
	var host := Node.new()
	var called := [false]
	var sound = UiSound.new()
	sound.setup(host, "over-9000.ogg", func():
		called[0] = true
		return false)
	sound.play()
	assert_true(called[0])
	assert_eq(host.get_child_count(), 0)
	host.free()


func test_over_9000_sound_resolves_and_loads() -> void:
	var host := Node.new()
	var sound = UiSound.new()
	sound.setup(host, "over-9000.ogg")
	assert_true(FileAccess.file_exists(sound._path), "sound not found: " + sound._path)
	assert_true(sound._load_stream() != null, "cannot load: " + sound._path)
	host.free()


func test_setup_stores_a_custom_volume() -> void:
	var host := Node.new()
	var sound = UiSound.new()
	sound.setup(host, "over-9000.ogg", Callable(), -12.0)
	assert_eq(sound._volume_db, -12.0)
	host.free()
