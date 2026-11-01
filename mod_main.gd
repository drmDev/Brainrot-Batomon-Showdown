extends Node
## Brain Rot - achievement detection, persistence, and toast.
##
## Polls the live run and battle state every 500 ms, reads them into snapshots via
## achievements/game_snapshot_reader.gd, evaluates achievements via
## achievements/achievement_evaluator.gd, persists completion through
## achievements/achievement_store.gd, and shows a bottom-right toast through
## achievements/achievement_panel.gd when the Achievement Notifications setting is on.
##
## Responsibilities kept here: initialization, settings, polling, and coordination.
## Snapshot reading, rules, persistence, UI, battle-completion detection, and debug
## capture live in their own files.

const VERSION := "0.0.0.5"
const MOD_ID := "brain_rot"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Polling interval (matches the game's shop/battle state cadence)
const POLL_INTERVAL_MS := 500

# Settings (defaults match mod.json)
const DEFAULT_ACHIEVEMENT_NOTIFICATIONS := false

var _achievement_notifications := DEFAULT_ACHIEVEMENT_NOTIFICATIONS
var _settings_load_attempted := false
var _settings_warning_shown := false

# Achievement system: snapshot reading + poll-based detection + JSON persistence + panel
var _battle_completion = null
var _achievement_evaluator = null
var _achievement_store = null
var _achievement_panel = null
var _achievement_layer: CanvasLayer = null
var _snapshot_reader = null
var _state_capture = null

var _next_poll := 0
var _last_phase := ""
var _initialization_started := false
var _initialized := false

# Run-transition tracking (inferred from data we already read; no game signals).
# Keys: run_instance_id, trainer_id, current_round. Empty until the first run.
var _run_tracking: Dictionary = {}


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _load_settings() -> void:
	if not is_inside_tree():
		return
	if _settings_load_attempted:
		return

	var mod_loader = get_node_or_null("/root/ModLoader")
	if mod_loader == null:
		return

	_settings_load_attempted = true

	if mod_loader.has_method("get_config"):
		_achievement_notifications = mod_loader.get_config(MOD_ID, "achievement_notifications", DEFAULT_ACHIEVEMENT_NOTIFICATIONS)

		# Connect to config_changed signal for live updates
		if mod_loader.has_signal("config_changed") and not mod_loader.is_connected("config_changed", _on_config_changed):
			mod_loader.connect("config_changed", _on_config_changed)
	elif not _settings_warning_shown:
		_settings_warning_shown = true
		push_warning("Brain Rot: ModLoader.get_config() not available, using defaults")


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true

	_load_settings()
	_setup_achievement_system()

	_initialized = true
	print("Brain Rot %s loaded" % VERSION)


func _on_config_changed(mod_id: String, key: String, value) -> void:
	"""Handle live config changes from ModLoader."""
	if mod_id != MOD_ID:
		return

	if key == "achievement_notifications" and value is bool:
		_achievement_notifications = value
		if not _achievement_notifications and _achievement_panel != null:
			_achievement_panel.hide_panel()


func _setup_achievement_system() -> void:
	"""Initialize the achievement detection, persistence, and panel system."""
	var base_dir := "res://mods/BrainRot"

	var GameSnapshotReader = load(base_dir.path_join("achievements/game_snapshot_reader.gd"))
	_snapshot_reader = GameSnapshotReader.new(_has_property)

	var BattleCompletionDetector = load(base_dir.path_join("achievements/battle_completion_detector.gd"))
	_battle_completion = BattleCompletionDetector.new()

	var AchievementEvaluator = load(base_dir.path_join("achievements/achievement_evaluator.gd"))
	_achievement_evaluator = AchievementEvaluator.new()

	# Store the JSON at the mod root (next to mod_main.gd).
	var AchievementStore = load(base_dir.path_join("achievements/achievement_store.gd"))
	_achievement_store = AchievementStore.new(base_dir)

	var StateCapture = load(base_dir.path_join("debug/state_capture.gd"))
	_state_capture = StateCapture.new()

	# Dedicated layer so the toast can appear over the battle results screen.
	_achievement_layer = CanvasLayer.new()
	_achievement_layer.layer = 100
	_achievement_layer.name = "BrainRot_Layer"
	add_child(_achievement_layer)

	var AchievementPanel = load(base_dir.path_join("achievements/achievement_panel.gd"))
	_achievement_panel = AchievementPanel.new()
	_achievement_panel.name = "AchievementPanel"
	_achievement_layer.add_child(_achievement_panel)


func _process(_delta: float) -> void:
	if not _initialized:
		return

	var now := Time.get_ticks_msec()
	if now < _next_poll:
		return
	_next_poll = now + POLL_INTERVAL_MS
	_inspect_current_phase()


func _inspect_current_phase() -> void:
	var main = get_tree().current_scene
	var state = main.get("current_state") if _has_property(main, "current_state") else null
	var is_battle := _script_is(state, BATTLE_SCRIPT)

	var run = _get_run_data()
	var run_snapshot: Dictionary = _snapshot_reader.read_run(run) if _snapshot_reader != null else {}
	_check_run_transition(run, run_snapshot)

	# Run-scoped achievements are evaluated every poll (the Twins transformation
	# happens in the shop, but polling all phases keeps the team baseline current).
	_poll_achievements(run_snapshot)

	var battle_snapshot: Dictionary = {}
	if is_battle:
		# Battle-scoped achievements are evaluated once the battle is over. The
		# detector owns that timing; the completion is consumed only after a usable
		# snapshot exists, so a partial read is retried next poll.
		if _battle_completion != null and _battle_completion.is_pending(state):
			battle_snapshot = _snapshot_reader.read_battle(state, run)
			if _snapshot_reader.is_battle_snapshot_usable(battle_snapshot):
				_battle_completion.consume()
				_log_battle_attribution(battle_snapshot)
				_poll_battle_achievements(battle_snapshot)
	elif _last_phase == "battle":
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _battle_completion != null:
			_battle_completion.reset()

	_last_phase = "battle" if is_battle else ""
	_maybe_capture(battle_snapshot if is_battle else run_snapshot)


## Poll the run snapshot for newly earned achievements, persist them, and show the panel.
func _poll_achievements(run_snapshot: Dictionary) -> void:
	if _achievement_evaluator == null:
		return
	_award_achievements(_achievement_evaluator.poll(run_snapshot))


## Poll a completed battle snapshot for battle-scoped achievements (Big Dog, Best Dog).
func _poll_battle_achievements(battle_snapshot: Dictionary) -> void:
	if _achievement_evaluator == null:
		return
	_award_achievements(_achievement_evaluator.poll_battle(battle_snapshot))


## Persist newly earned achievements (deduplicated by the store). The panel is
## optional: unlocks are saved even when it is absent or notifications are disabled.
func _award_achievements(earned: Array) -> void:
	if _achievement_store == null:
		return
	for achievement in earned:
		var id := str(achievement.get("id", ""))
		if id.is_empty() or _achievement_store.is_completed(id):
			continue
		var title := str(achievement.get("title", ""))
		var description := str(achievement.get("description", ""))
		if title.is_empty() or description.is_empty():
			continue

		if not _achievement_store.mark_completed(id):
			continue
		print("Brain Rot: EARNED | %s | %s" % [id, title])
		if _achievement_notifications and _achievement_panel != null:
			_achievement_panel.show_achievement(title, description)


## Detect a run transition from data we already read and reset run-scoped state.
##
## No verified run-start/run-end signal exists (Creature Comforts only compares
## trainer_id between snapshots), so transitions are inferred from:
##   - the run becoming unavailable,
##   - a different run object instance,
##   - a different trainer_id,
##   - current_round going backwards.
## Each trigger is logged so the first real session can confirm which one fires.
func _check_run_transition(run, run_snapshot: Dictionary) -> void:
	if run_snapshot.is_empty():
		# Run unavailable (menu, transition). Forget tracking so the next run resets.
		_run_tracking = {}
		return

	var instance_id: int = run.get_instance_id() if is_instance_valid(run) else 0
	var trainer_id := str(run_snapshot.get("trainer_id", ""))
	var current_round := int(run_snapshot.get("current_round", 0))

	if _run_tracking.is_empty():
		_run_tracking = {
			"run_instance_id": instance_id,
			"trainer_id": trainer_id,
			"current_round": current_round,
		}
		return

	var reason := ""
	if instance_id != int(_run_tracking.get("run_instance_id", 0)):
		reason = "new run object"
	elif trainer_id != str(_run_tracking.get("trainer_id", "")):
		reason = "trainer changed"
	elif current_round < int(_run_tracking.get("current_round", 0)):
		reason = "day went backwards"

	if reason.is_empty():
		_run_tracking["current_round"] = current_round
		return

	print("Brain Rot: run reset (%s)" % reason)
	_run_tracking = {
		"run_instance_id": instance_id,
		"trainer_id": trainer_id,
		"current_round": current_round,
	}
	if _achievement_evaluator != null:
		_achievement_evaluator.reset_run()
	if _battle_completion != null:
		_battle_completion.reset()


## Debug aid: log per-slot unit counts and the species resolved from the team slot.
## Verifies the slot_index -> team mapping at runtime (see dev/QUALITY.md).
func _log_battle_attribution(battle_snapshot: Dictionary) -> void:
	if _state_capture == null or not _state_capture.is_enabled():
		return
	var units = battle_snapshot.get("battle_units")
	var team = battle_snapshot.get("team")
	if not units is Array or not team is Array:
		return
	var counts := {}
	for unit in units:
		if not unit is Dictionary or not unit.has("slot_index"):
			continue
		var slot := int(unit.get("slot_index"))
		counts[slot] = int(counts.get(slot, 0)) + 1
	var parts: Array = []
	for slot in counts.keys():
		var species := ""
		if slot >= 0 and slot < team.size():
			species = str(team[slot].get("name_key", "")) if team[slot] is Dictionary else ""
		parts.append("slot %d x%d -> %s" % [slot, int(counts[slot]), species if not species.is_empty() else "?"])
	print("Brain Rot: battle attribution | %s" % ", ".join(parts))


## Write the snapshot to the debug dump directory when capture is enabled.
func _maybe_capture(snapshot: Dictionary) -> void:
	if _state_capture == null or snapshot.is_empty():
		return
	_state_capture.capture(snapshot)


# Utility functions

func _has_property(obj, property: String) -> bool:
	if not is_instance_valid(obj):
		return false
	for prop in obj.get_property_list():
		if str(prop.name) == property:
			return true
	return false


func _script_is(obj, script_path: String) -> bool:
	if not is_instance_valid(obj):
		return false
	var script: Script = obj.get_script()
	while script != null:
		if str(script.resource_path) == script_path:
			return true
		script = script.get_base_script()
	return false


func _get_run_data():
	"""Return RunManager.data (the run) or null."""
	var run_manager = get_node_or_null("/root/RunManager")
	if run_manager == null or not _has_property(run_manager, "data"):
		return null
	return run_manager.get("data")


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
