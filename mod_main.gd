extends Node
## Brain Rot - achievement detection, persistence, and toast.
##
## Polls the live run and battle state every 500 ms, reads them into snapshots via
## achievements/game_snapshot_reader.gd, evaluates achievements via
## achievements/achievement_evaluator.gd, persists completion through
## achievements/achievement_store.gd, and shows toasts through the shared
## notifications/notification_host.gd (achievements and reactions share one queue).
##
## Responsibilities kept here: initialization, polling, and coordination.
## Snapshot reading, rules, persistence, UI, battle-completion detection, and debug
## capture live in their own files.
##
## Logging mirrors Creature Comforts: one append handle kept open for the session,
## writing to user://brain_rot/inspect.log. Console output is unchanged; user-visible
## events go to both console and file, diagnostics go to the file with a time prefix.

const VERSION := "0.0.0.22"
const MOD_ID := "brain_rot"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
const MOD_BASE_DIR := "res://mods/BrainRot"

# Log file (same layout as Creature Comforts, different path)
const OUTPUT_DIR := "user://brain_rot"
const LOG_FILE := "inspect.log"

# Polling interval (matches the game's shop/battle state cadence)
const POLL_INTERVAL_MS := 500

# Toasts are always on; there is no settings gate.

# Achievement system: snapshot reading + poll-based detection + JSON persistence + toast host
var _battle_completion = null
var _achievement_evaluator = null
var _achievement_store = null
var _notification_host = null
var _notification_request_script = null
var _achievement_layer: CanvasLayer = null
var _snapshot_reader = null
var _state_capture = null

# Developer-only toast preview (created only when dev/dev_config.gd enables it).
var _toast_catalog_script = null
var _toast_preview_panel = null

# Reactions: snapshot-driven conditions that log and submit toasts.
var _reaction_evaluator = null
var _reaction_player = null
var _last_progress_signature := ""

var _next_poll := 0
var _was_battle := false
var _initialization_started := false
var _initialized := false

# Session log handle (null when the log file could not be opened; logging no-ops).
var _log_file: FileAccess = null

# Run-transition tracking (inferred from data we already read; no game signals).
# Keys: run_id, run_instance_id, trainer_id, current_round. Empty until the first run.
var _run_tracking: Dictionary = {}


func mod_ready() -> void:
	_initialize_mod()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _is_loaded_by_mod_loader():
		_initialize_mod()


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true

	_setup_achievement_system()
	_setup_reactions()

	# The systems are live and must run even if the log file cannot be opened;
	# _log_message already no-ops when _log_file is null.
	_initialized = true
	_setup_log_file()
	_setup_dev_tools()


func _setup_achievement_system() -> void:
	"""Initialize detection, persistence, and the shared notification host."""
	var base_dir := MOD_BASE_DIR

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

	# Dedicated layer so toasts can appear over the battle results screen.
	_achievement_layer = CanvasLayer.new()
	_achievement_layer.layer = 100
	_achievement_layer.name = "BrainRot_Layer"
	add_child(_achievement_layer)

	# Shared toast queue: achievements and reactions both submit here.
	var NotificationManager = load(base_dir.path_join("notifications/notification_manager.gd"))
	var NotificationHost = load(base_dir.path_join("notifications/notification_host.gd"))
	_notification_request_script = load(base_dir.path_join("notifications/notification_request.gd"))
	_notification_host = NotificationHost.new(NotificationManager.new(), _achievement_layer)
	_notification_host.name = "NotificationHost"
	_achievement_layer.add_child(_notification_host)


func _setup_reactions() -> void:
	"""Initialize the reaction evaluator and player (console + shared toast)."""
	var base_dir := MOD_BASE_DIR

	var ReactionEvaluator = load(base_dir.path_join("reactions/reaction_evaluator.gd"))
	_reaction_evaluator = ReactionEvaluator.new()

	# Reactions log to the console/session log and submit to the shared toast queue.
	var ReactionPlayer = load(base_dir.path_join("reactions/reaction_player.gd"))
	_reaction_player = ReactionPlayer.new(_print_notice, _submit_notification)


## Developer-only toast preview. Disabled unless dev/dev_config.gd says otherwise,
## so retail sessions create no extra UI.
func _setup_dev_tools() -> void:
	var DevConfig = load(MOD_BASE_DIR.path_join("dev/dev_config.gd"))
	if DevConfig == null or not DevConfig.is_enabled():
		return

	var ToastCatalog = load(MOD_BASE_DIR.path_join("notifications/toast_catalog.gd"))
	var ToastPreviewPanel = load(MOD_BASE_DIR.path_join("hud/toast_preview_panel.gd"))
	if ToastCatalog == null or ToastPreviewPanel == null or _achievement_layer == null:
		return

	_toast_catalog_script = ToastCatalog
	_toast_preview_panel = ToastPreviewPanel.new(ToastCatalog.entries(), _preview_toast)
	_toast_preview_panel.name = "ToastPreviewPanel"
	_achievement_layer.add_child(_toast_preview_panel)
	_print_notice("Brain Rot: dev toast preview enabled")


## Show a registered toast without evaluating rules or touching progress/saves.
func _preview_toast(entry: Dictionary) -> void:
	if _toast_catalog_script == null:
		return
	_log_event("PREVIEW | %s:%s" % [
		str(entry.get("kind", "")),
		str(entry.get("id", "")),
	])
	_submit_notification(_toast_catalog_script.make_request(entry))


## Create/open the session log and write the startup banner (Creature Comforts layout).
func _setup_log_file() -> void:
	var dir_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK and dir_result != ERR_ALREADY_EXISTS:
		push_error("Brain Rot: Failed to create directory %s: %s" % [dir_path, error_string(dir_result)])
		return

	var log_path := OUTPUT_DIR.path_join(LOG_FILE)
	var abs_log_path := ProjectSettings.globalize_path(log_path)

	if not FileAccess.file_exists(log_path):
		var file := FileAccess.open(log_path, FileAccess.WRITE)
		if file == null:
			push_error("Brain Rot: Cannot create log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
			return
		file.close()

	# Keep one append handle open for the session instead of reopening per line.
	_log_file = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if _log_file == null:
		push_error("Brain Rot: Cannot open log file %s: %s" % [abs_log_path, error_string(FileAccess.get_open_error())])
		return
	_log_file.seek_end()

	_log_message("=".repeat(80))
	_log_message("Brain Rot %s" % VERSION)
	_log_message("Initialized at %s" % _timestamp())
	_log_message("Log file: %s" % abs_log_path)
	_log_message("=".repeat(80))

	print("Brain Rot %s loaded - logging to %s" % [VERSION, abs_log_path])


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
	_poll_reactions(run_snapshot)
	_log_run_progress(run_snapshot)

	var battle_snapshot: Dictionary = {}
	if is_battle:
		# A new battle starts fresh battle-scoped reaction tracking.
		if not _was_battle:
			if _reaction_evaluator != null:
				_reaction_evaluator.reset_battle()
			_log_battle_probe(state)

		# Battle-scoped achievements and reactions are evaluated once the battle is
		# over, against the final unit totals. The detector owns that timing; the
		# completion is consumed only after a usable snapshot exists, so a partial
		# read is retried next poll.
		if _battle_completion != null and _battle_completion.is_pending(state):
			# During battle the player's run is the replay copy the game hands the
			# battle state (verified in MyBattleStats/BatoEyes and BatomonHelperBridge);
			# RunManager.data may already be the promoted/completed run.
			var player_run = _get_battle_player_run(state, run)
			battle_snapshot = _snapshot_reader.read_battle(state, player_run)
			var usable: bool = _snapshot_reader.is_battle_snapshot_usable(battle_snapshot)
			_log_event("BATTLE COMPLETE | usable=%s units=%s team=%s trainer=%s" % [
				str(usable),
				str(battle_snapshot.get("battle_units").size()) if battle_snapshot.get("battle_units") is Array else "absent",
				str(battle_snapshot.get("team").size()) if battle_snapshot.get("team") is Array else "absent",
				str(battle_snapshot.get("trainer_id", "absent")),
			])
			if usable:
				_battle_completion.consume()
				_log_battle_units(battle_snapshot)
				_poll_battle_achievements(battle_snapshot)
				_poll_battle_reactions(battle_snapshot)
	elif _was_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _battle_completion != null:
			_battle_completion.reset()

	_was_battle = is_battle
	_maybe_capture(battle_snapshot if is_battle else run_snapshot)


## Poll the run snapshot for newly earned achievements, persist them, and show a toast.
func _poll_achievements(run_snapshot: Dictionary) -> void:
	if _achievement_evaluator == null:
		return
	_award_achievements(_achievement_evaluator.poll(run_snapshot))


## Poll a completed battle snapshot for battle-scoped achievements (Big Dog, Best Dog).
func _poll_battle_achievements(battle_snapshot: Dictionary) -> void:
	if _achievement_evaluator == null:
		return
	_award_achievements(_achievement_evaluator.poll_battle(battle_snapshot))


## Poll the run snapshot for newly triggered reactions and play them.
func _poll_reactions(run_snapshot: Dictionary) -> void:
	if _reaction_evaluator == null or _reaction_player == null:
		return
	_reaction_player.play_all(_reaction_evaluator.poll(run_snapshot))


## Poll a completed battle snapshot for battle-scoped reactions (final unit totals).
func _poll_battle_reactions(battle_snapshot: Dictionary) -> void:
	if _reaction_evaluator == null or _reaction_player == null:
		return
	var triggered: Array = _reaction_evaluator.poll_battle(battle_snapshot)
	_log_event("REACTION BATTLE | %d triggered" % triggered.size())
	_reaction_player.play_all(triggered)


## The player's run during battle: the replay copy when the battle state exposes it,
## otherwise RunManager.data.
func _get_battle_player_run(state, run):
	if _has_property(state, "_replay_p1_data"):
		var replay = state.get("_replay_p1_data")
		if is_instance_valid(replay):
			return replay
	return run


## Debug aid: one line per battle describing what the battle state exposes.
func _log_battle_probe(state) -> void:
	var sim = state.get("simulation") if _has_property(state, "simulation") else null
	var data = sim.get("data") if sim != null and _has_property(sim, "data") else null
	var units = data.get("battle_units") if data != null and _has_property(data, "battle_units") else null
	var over = data.get("battle_over") if data != null and _has_property(data, "battle_over") else null
	var replay = state.get("_replay_p1_data") if _has_property(state, "_replay_p1_data") else null
	_log_event("BATTLE PHASE | sim=%s data=%s over=%s units=%s replay_run=%s" % [
		str(sim != null),
		str(data != null),
		str(over),
		str(units.size()) if units is Array else "absent",
		str(replay != null),
	])


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
		_print_notice("Brain Rot: EARNED | %s | %s" % [id, title])
		_submit_achievement_notification(id, title, description)


## Submit an achievement toast through the shared notification host.
func _submit_achievement_notification(id: String, title: String, description: String) -> void:
	if _notification_request_script == null:
		return
	_submit_notification(_notification_request_script.new(
		_notification_request_script.KIND_ACHIEVEMENT,
		id,
		title,
		description,
	))


## Forward a NotificationRequest to the shared host (no-op when unavailable).
func _submit_notification(request) -> void:
	if _notification_host != null:
		_notification_host.submit(request)


## Detect a run transition from data we already read and reset run-scoped state.
##
## No verified run-start/run-end signal exists (Creature Comforts only compares
## trainer_id between snapshots), so transitions are inferred from:
##   - a different run_id (the game's own run identity),
##   - a different run object instance (only when run_id is unavailable),
##   - a different trainer_id,
##   - current_round going backwards.
## Each trigger is logged so the first real session can confirm which one fires.
##
## run_id is the primary identity because the game promotes RunManager.data to a NEW
## RunData object when a battle starts (verified in BatomonHelperBridge: it compares
## completed.run_id to the replay run's run_id). Comparing object instances alone
## produced a false "new run object" reset at every battle start.
##
## An unavailable run (menu, transition) does NOT clear tracking: the comparison on
## return is what detects a new run. Clearing here would hide a new run whose only
## evidence was the gap, and would re-arm reactions after a menu round-trip.
func _check_run_transition(run, run_snapshot: Dictionary) -> void:
	if run_snapshot.is_empty():
		return

	var run_id := str(run_snapshot.get("run_id", ""))
	var instance_id: int = run.get_instance_id() if is_instance_valid(run) else 0
	var trainer_id := str(run_snapshot.get("trainer_id", ""))
	var current_round := int(run_snapshot.get("current_round", 0))

	var tracking := {
		"run_id": run_id,
		"run_instance_id": instance_id,
		"trainer_id": trainer_id,
		"current_round": current_round,
	}
	if _run_tracking.is_empty():
		_run_tracking = tracking
		return

	var reason := ""
	var tracked_run_id := str(_run_tracking.get("run_id", ""))
	if not run_id.is_empty() and not tracked_run_id.is_empty():
		if run_id != tracked_run_id:
			reason = "run id changed"
	elif instance_id != int(_run_tracking.get("run_instance_id", 0)):
		reason = "new run object"
	if reason.is_empty() and trainer_id != str(_run_tracking.get("trainer_id", "")):
		reason = "trainer changed"
	if reason.is_empty() and current_round < int(_run_tracking.get("current_round", 0)):
		reason = "day went backwards"

	if reason.is_empty():
		_run_tracking = tracking
		return

	_print_notice("Brain Rot: run reset (%s)" % reason)
	_run_tracking = tracking
	if _achievement_evaluator != null:
		_achievement_evaluator.reset_run()
	if _reaction_evaluator != null:
		_reaction_evaluator.reset_run()
	if _battle_completion != null:
		_battle_completion.reset()


## Debug aid: log the run's day/lives/wins whenever the triple changes. Verifies the
## field mapping, the starting lives value, and when wins/lives are committed.
func _log_run_progress(run_snapshot: Dictionary) -> void:
	if _state_capture == null or not _state_capture.is_enabled():
		return
	if run_snapshot.is_empty():
		return
	var day := str(run_snapshot.get("current_round", "?"))
	var lives := str(run_snapshot.get("lives", "?"))
	var wins := str(run_snapshot.get("current_wins", "?"))
	var signature := "%s|%s|%s" % [day, lives, wins]
	if signature == _last_progress_signature:
		return
	_last_progress_signature = signature
	_log_event("RUN PROGRESS | Day %s, Lives %s, Wins %s" % [day, lives, wins])


## Debug aid: one line per player-side unit with the final metrics the reaction reads.
func _log_battle_units(battle_snapshot: Dictionary) -> void:
	var units = battle_snapshot.get("battle_units")
	if not units is Array:
		return
	var team = battle_snapshot.get("team")
	if not team is Array:
		team = []
	for unit in units:
		if not unit is Dictionary:
			continue
		if int(unit.get("team_id", -1)) != 0:
			continue
		var slot := int(unit.get("slot_index", -1))
		var species := "?"
		if slot >= 0 and slot < team.size() and team[slot] is Dictionary:
			var key := str(team[slot].get("name_key", ""))
			if not key.is_empty():
				species = key
		_log_event("BATTLE UNIT | slot %d %s dmg=%s heal=%s shield=%s burn=%s poison=%s shock=%s" % [
			slot,
			species,
			str(unit.get("damage_dealt", "?")),
			str(unit.get("healing_done", "?")),
			str(unit.get("shield_granted", "?")),
			str(unit.get("burn_inflicted", "?")),
			str(unit.get("poison_inflicted", "?")),
			str(unit.get("shock_inflicted", "?")),
		])


## Write the snapshot to the debug dump directory when capture is enabled.
func _maybe_capture(snapshot: Dictionary) -> void:
	if _state_capture == null or snapshot.is_empty():
		return
	_state_capture.capture(snapshot)


# Logging (mirrors Creature Comforts' mod_main logging helpers)

## Write one line to the session log. No-ops when the log file is unavailable.
func _log_message(message: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line(message)
	_log_file.flush()


## Timestamped diagnostic line: file only, "[HH:MM:SS] message".
func _log_event(message: String) -> void:
	_log_message("[%s] %s" % [_time_short(), message])


## User-visible line: console and file, no timestamp prefix.
func _print_notice(message: String) -> void:
	print(message)
	_log_message(message)


func _timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


func _time_short() -> String:
	var dt := Time.get_datetime_dict_from_system(false)
	return "%02d:%02d:%02d" % [dt.hour, dt.minute, dt.second]


# Utility functions

func _has_property(obj, property: String) -> bool:
	if obj == null:
		return false
	# `in` is O(1) and works for both Objects (properties) and Dictionaries (keys),
	# unlike get_property_list(), which allocates and rejects Dictionaries.
	if obj is Dictionary:
		return obj.has(property)
	if not is_instance_valid(obj):
		return false
	return property in obj


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
