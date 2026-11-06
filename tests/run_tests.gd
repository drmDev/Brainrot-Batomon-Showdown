extends SceneTree
## Headless test entry point for Brain Rot.
##
## Run with:
##   godot --headless --script tests/run_tests.gd
## Exits 0 when all tests pass, 1 otherwise.

var _test_scripts := {
	"achievement_evaluator": preload("test_achievement_evaluator.gd"),
	"achievement_store": preload("test_achievement_store.gd"),
	"battle_completion_detector": preload("test_battle_completion_detector.gd"),
	"achievements_schema": preload("test_achievements_schema.gd"),
	"dev_config": preload("test_dev_config.gd"),
	"mod_main_preview": preload("test_mod_main_preview.gd"),
	"mod_main_reactions": preload("test_mod_main_reactions.gd"),
	"reaction_sounds": preload("test_reaction_sounds.gd"),
	"ui_sound": preload("test_ui_sound.gd"),
	"fixture_replay": preload("test_fixture_replay.gd"),
	"game_snapshot_reader": preload("test_game_snapshot_reader.gd"),
	"state_capture": preload("test_state_capture.gd"),
	"reaction_definitions": preload("test_reaction_definitions.gd"),
	"reaction_evaluator": preload("test_reaction_evaluator.gd"),
	"reaction_player": preload("test_reaction_player.gd"),
	"toast_catalog": preload("test_toast_catalog.gd"),
	"toast_preview_panel": preload("test_toast_preview_panel.gd"),
}


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			filter = arg.substr("--test=".length())

	var total_failures := 0
	var total_assertions := 0
	var total_suites := 0

	for suite_name in _test_scripts:
		var script = _test_scripts[suite_name]
		var suite = script.new()
		var failures: int = suite.run_all(filter)
		total_failures += failures
		total_assertions += suite.assertion_count()
		total_suites += 1

		if failures == 0:
			print("PASS  %s (%d assertions)" % [suite_name, suite.assertion_count()])
		else:
			print("FAIL  %s (%d failures)" % [suite_name, failures])
			for failure in suite.failures():
				print("      %s: %s" % [failure["test"], failure["message"]])

	print("")
	print("Ran %d suites, %d assertions, %d failures." % [total_suites, total_assertions, total_failures])
	quit(0 if total_failures == 0 else 1)
