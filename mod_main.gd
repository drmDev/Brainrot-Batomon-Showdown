extends Node
## Brain Rot - reaction detection and toast.
##
## Polls the live run and battle state every 500 ms, reads them into snapshots via
## snapshots/game_snapshot_reader.gd, evaluates reactions via
## reactions/reaction_evaluator.gd, and shows toasts through the shared
## notifications/notification_host.gd.
##
## Responsibilities kept here: initialization, polling, and coordination.
## Snapshot reading, rules, UI, battle-completion detection, and debug capture live
## in their own files.
##
## Logging mirrors Creature Comforts: one append handle kept open for the session,
## writing to user://brain_rot/inspect.log. Console output is unchanged; user-visible
## events go to both console and file, diagnostics go to the file with a time prefix.

const VERSION := "1.4"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
# Verified in BatomonHelperBridge (reads shop_state.manager/view). The shop is the
# start of a day, the only phase where run-scoped reactions are evaluated.
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const MOD_BASE_DIR := "res://mods/BrainRot"

# Polling interval (matches the game's shop/battle state cadence)
const POLL_INTERVAL_MS := 500

# Shared helpers and the session logger (extracted from mod_main).
const NodeUtils = preload("catalog/node_utils.gd")
const ModLogger = preload("core/mod_logger.gd")
const ModVolumeSettings = preload("hud/mod_volume_settings.gd")
const MemoriesButtonController = preload("hud/memories_button_controller.gd")
const RunTracker = preload("core/run_tracker.gd")
const BattleLogger = preload("debug/battle_logger.gd")
const ReactionCoordinator = preload("reactions/reaction_coordinator.gd")
const ToastPreviewController = preload("dev/toast_preview_controller.gd")

# Toasts are always on; there is no settings gate.

# Snapshot reading + battle-completion detection + shared toast host.
var _battle_completion = null
var _notification_host = null
var _toast_layer: CanvasLayer = null
var _snapshot_reader = null
var _state_capture = null

# Developer-only toast preview controller (dev/toast_preview_controller.gd).
var _toast_preview = ToastPreviewController.new()

# User settings (currently only Mod Volume) from core/mod_config.gd.
var _config = null
# Mod Volume slider row and volume access (hud/mod_volume_settings.gd).
var _volume_settings = ModVolumeSettings.new(null)

# Reactions: snapshot-driven conditions that log, submit toasts, and play sounds.
var _reaction_coordinator = ReactionCoordinator.new()

# Persistent per-metric high scores and the shop's Brain Rot Memories panel.
var _high_scores: Dictionary = {}
# Persistent earned-reaction achievements (core/achievement_store.gd).
var _achievements: Dictionary = {}
# Shop Memories button controller (hud/memories_button_controller.gd).
var _memories_button = null

# Self-updater: checks the GitHub release manifest and swaps files (core/auto_updater.gd).
var _updater = null

var _next_poll := 0
var _was_battle := false
var _initialization_started := false
var _initialized := false

# Session logger (extracted to core/mod_logger.gd; no-ops until open() is called).
var _logger = ModLogger.new()

# Run-transition detector (core/run_tracker.gd) and debug logger (debug/battle_logger.gd).
var _run_tracker = RunTracker.new()
var _debug_logger = null


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

	_setup_config()
	_setup_core()
	_setup_reactions()
	_setup_auto_updater()

	# The systems are live and must run even if the log file cannot be opened;
	# the logger no-ops when its file handle is null.
	_initialized = true
	var abs_log_path: String = _logger.open(VERSION)
	if not abs_log_path.is_empty():
		print("Brain Rot %s loaded - logging to %s" % [VERSION, abs_log_path])
	_setup_dev_tools()


## Load the mod's own settings module and bind it to the Mod Loader (may be null
## when running standalone). Mod Volume is not declared in mod.json, so it is
## persisted in the mod's own file rather than the loader's store.
func _setup_config() -> void:
	var ModConfig = load(MOD_BASE_DIR.path_join("core/mod_config.gd"))
	if ModConfig == null:
		return
	_config = ModConfig.new()
	_config.setup(get_node_or_null("/root/ModLoader"))
	_config.use_store(ModConfig.STORE_PATH)
	_volume_settings.set_config(_config)


func _setup_core() -> void:
	"""Initialize snapshot reading, battle-completion detection, and the toast host."""
	var base_dir := MOD_BASE_DIR

	var GameSnapshotReader = load(base_dir.path_join("snapshots/game_snapshot_reader.gd"))
	_snapshot_reader = GameSnapshotReader.new(NodeUtils.has_property)

	var BattleCompletionDetector = load(base_dir.path_join("battle/battle_completion_detector.gd"))
	_battle_completion = BattleCompletionDetector.new()

	var StateCapture = load(base_dir.path_join("debug/state_capture.gd"))
	_state_capture = StateCapture.new()
	_debug_logger = BattleLogger.new(_logger, _state_capture)

	var HighScores = load(base_dir.path_join("battle/high_scores.gd"))
	if HighScores != null:
		_high_scores = HighScores.load_store()

	var AchievementStore = load(base_dir.path_join("core/achievement_store.gd"))
	if AchievementStore != null:
		_achievements = AchievementStore.load_store()

	# Dedicated layer so toasts can appear over the battle results screen.
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 100
	_toast_layer.name = "BrainRot_Layer"
	add_child(_toast_layer)

	# Shared toast queue for reactions.
	var NotificationManager = load(base_dir.path_join("notifications/notification_manager.gd"))
	var NotificationHost = load(base_dir.path_join("notifications/notification_host.gd"))
	_notification_host = NotificationHost.new(NotificationManager.new(), _toast_layer)
	_notification_host.name = "NotificationHost"
	_toast_layer.add_child(_notification_host)

	# Shop button that opens the Brain Rot Memories panel. The achievements store
	# is handed over by reference so earned state stays in sync as reactions fire.
	var MemoriesPanel = load(base_dir.path_join("hud/memories_panel.gd"))
	if MemoriesPanel != null:
		var memories_panel = MemoriesPanel.new()
		memories_panel.name = "MemoriesPanel"
		memories_panel.set_achievements(_achievements)
		_toast_layer.add_child(memories_panel)
		_memories_button = MemoriesButtonController.new(memories_panel, _logger)


func _setup_reactions() -> void:
	"""Initialize the reaction evaluator, player, and reaction sounds."""
	_reaction_coordinator.setup(self, _logger, _submit_notification, _volume_settings.current_volume)
	_reaction_coordinator.set_achievements(_achievements)


## Self-updater: checks the GitHub release manifest and swaps files (core/auto_updater.gd).
## Brain Rot has no settings, so auto-update is always on; the updater disables itself on a
## developer install (a folder with .git or dev/run_tests.ps1).
func _setup_auto_updater() -> void:
	var AutoUpdater = load(MOD_BASE_DIR.path_join("core/auto_updater.gd"))
	if AutoUpdater == null:
		return
	_updater = AutoUpdater.new()
	_updater.name = "AutoUpdater"
	add_child(_updater)
	_updater.setup(VERSION, get_script().resource_path.get_base_dir(), true)
	_updater.start()


## Community Mod Loader hook (Settings > Mods). The loader appends custom entries
## after every declared row. Brain Rot declares no settings, so the Mod Volume
## slider is the only row. The row itself is built by hud/mod_volume_settings.gd.
func make_custom_settings_menu_entries() -> Array:
	return _volume_settings.make_settings_entries(self)


## Developer-only toast preview. Disabled unless dev/dev_config.gd says otherwise,
## so retail sessions create no extra UI.
func _setup_dev_tools() -> void:
	_toast_preview.setup(_toast_layer, _logger, _reaction_coordinator.play_preview)


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
	var state = main.get("current_state") if NodeUtils.has_property(main, "current_state") else null
	var is_battle := NodeUtils.script_is(state, BATTLE_SCRIPT)
	var is_shop := NodeUtils.script_is(state, SHOP_SCRIPT)

	var run = _get_run_data()
	var run_snapshot: Dictionary = _snapshot_reader.read_run(run) if _snapshot_reader != null else {}
	_check_run_transition(run, run_snapshot)

	# Run-scoped reactions are evaluated only in the shop (the start of a day).
	# The game promotes the completed run into RunManager.data before the visual
	# battle ends, so lives/wins/income there already reflect the post-battle
	# result. Polling mid-battle would fire 6 7 / 6 9 before the player sees the
	# next day. Battle-scoped reactions still fire at battle_over.
	_reaction_coordinator.poll_reactions(run_snapshot, is_shop)
	_debug_logger.log_run_progress(run_snapshot)

	var battle_snapshot: Dictionary = {}
	if is_battle:
		# A new battle starts fresh battle-scoped reaction tracking.
		if not _was_battle:
			_reaction_coordinator.reset_battle()
			_debug_logger.log_battle_probe(state)

		# Battle-scoped reactions are evaluated once the battle is over, against the
		# final unit totals. The detector owns that timing; the completion is consumed
		# only after a usable snapshot exists, so a partial read is retried next poll.
		if _battle_completion != null and _battle_completion.is_pending(state):
			# During battle the player's run is the replay copy the game hands the
			# battle state (verified in MyBattleStats/BatoEyes and BatomonHelperBridge);
			# RunManager.data may already be the promoted/completed run.
			var player_run = _get_battle_player_run(state, run)
			battle_snapshot = _snapshot_reader.read_battle(state, player_run)
			var usable: bool = _snapshot_reader.is_battle_snapshot_usable(battle_snapshot)
			_logger.log_event("BATTLE COMPLETE | usable=%s units=%s team=%s trainer=%s" % [
				str(usable),
				str(battle_snapshot.get("battle_units").size()) if battle_snapshot.get("battle_units") is Array else "absent",
				str(battle_snapshot.get("team").size()) if battle_snapshot.get("team") is Array else "absent",
				str(battle_snapshot.get("trainer_id", "absent")),
			])
			if usable:
				_battle_completion.consume()
				_debug_logger.log_battle_units(battle_snapshot)
				_record_high_scores(battle_snapshot)
				_reaction_coordinator.poll_battle_reactions(battle_snapshot)
	elif _was_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _battle_completion != null:
			_battle_completion.reset()

	_was_battle = is_battle
	if _memories_button != null:
		_memories_button.update(is_shop, state, _high_scores)
	_maybe_capture(battle_snapshot if is_battle else run_snapshot)


## Record persistent per-metric high scores from a completed battle snapshot.
## Saves only when a metric improves and logs each new record.
func _record_high_scores(battle_snapshot: Dictionary) -> void:
	if _high_scores.is_empty():
		return
	var HighScores = load(MOD_BASE_DIR.path_join("battle/high_scores.gd"))
	if HighScores == null:
		return
	var improved: Dictionary = HighScores.record_battle(_high_scores, battle_snapshot)
	if improved.is_empty():
		return
	HighScores.save_store(_high_scores)
	for metric in improved:
		var row: Dictionary = improved[metric]
		_logger.log_event("HIGH SCORE | %s %d by %s (was %d)" % [
			str(metric),
			int(row.get("value", 0)),
			HighScores.format_unit(str(row.get("unit", ""))),
			int(row.get("previous", 0)),
		])


## The player's run during battle: the replay copy when the battle state exposes it,
## otherwise RunManager.data.
func _get_battle_player_run(state, run):
	if NodeUtils.has_property(state, "_replay_p1_data"):
		var replay = state.get("_replay_p1_data")
		if is_instance_valid(replay):
			return replay
	return run


## Forward a NotificationRequest to the shared host (no-op when unavailable).
func _submit_notification(request) -> void:
	if _notification_host != null:
		_notification_host.submit(request)


## Detect a run transition from data we already read and reset run-scoped state.
## The detection logic lives in core/run_tracker.gd; this only applies the resets.
func _check_run_transition(run, run_snapshot: Dictionary) -> void:
	var reason: String = _run_tracker.check(run, run_snapshot)
	if reason.is_empty():
		return
	_logger.print_notice("Brain Rot: run reset (%s)" % reason)
	_reaction_coordinator.reset_run()
	if _battle_completion != null:
		_battle_completion.reset()


## Write the snapshot to the debug dump directory when capture is enabled.
func _maybe_capture(snapshot: Dictionary) -> void:
	if _state_capture == null or snapshot.is_empty():
		return
	_state_capture.capture(snapshot)


# Utility functions

func _get_run_data():
	"""Return RunManager.data (the run) or null."""
	var run_manager = get_node_or_null("/root/RunManager")
	if run_manager == null or not NodeUtils.has_property(run_manager, "data"):
		return null
	return run_manager.get("data")


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
