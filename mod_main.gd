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

const VERSION := "1.2"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"
# Verified in BatomonHelperBridge (reads shop_state.manager/view). The shop is the
# start of a day, the only phase where run-scoped reactions are evaluated.
const SHOP_SCRIPT := "res://game/states/shop_state.gd"
const MOD_BASE_DIR := "res://mods/BrainRot"

# Mod Volume slider (make_custom_settings_menu_entries). The loader draws declared
# settings as a stepper, so volume is a custom HSlider persisted by core/mod_config.gd.
const SLIDER_STEP := 5
# The loader's own text theme; generic Labels added by a mod do not inherit it.
const SETTINGS_TEXT_THEME := "res://assets/ui/themes/text/description_text.tres"

# Log file (same layout as Creature Comforts, different path)
const OUTPUT_DIR := "user://brain_rot"
const LOG_FILE := "inspect.log"

# Polling interval (matches the game's shop/battle state cadence)
const POLL_INTERVAL_MS := 500

# Toasts are always on; there is no settings gate.

# Snapshot reading + battle-completion detection + shared toast host.
var _battle_completion = null
var _notification_host = null
var _toast_layer: CanvasLayer = null
var _snapshot_reader = null
var _state_capture = null

# Developer-only toast preview (created only when dev/dev_config.gd enables it).
var _toast_preview_panel = null

# User settings (currently only Mod Volume) from core/mod_config.gd.
var _config = null
# One-shot preview player for the Mod Volume slider (created on first release).
var _settings_preview = null

# Reactions: snapshot-driven conditions that log, submit toasts, and play sounds.
var _reaction_evaluator = null
var _reaction_player = null
var _reaction_sounds = null
var _species_icons = null
var _last_progress_signature := ""
# Previous shop-phase run snapshot, for detecting sold monsters between polls.
var _last_shop_snapshot: Dictionary = {}

# Persistent per-metric high scores and the shop's Brain Rot Memories panel.
var _high_scores: Dictionary = {}
var _memories_panel = null

# Self-updater: checks the GitHub release manifest and swaps files (core/auto_updater.gd).
var _updater = null

# Run-scoped reaction phase gate. "shop" while the shop is active, "deferred"
# otherwise. Only changes are logged, not every 500 ms poll.
var _run_reaction_gate_state := ""

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

	_setup_config()
	_setup_core()
	_setup_reactions()
	_setup_auto_updater()

	# The systems are live and must run even if the log file cannot be opened;
	# _log_message already no-ops when _log_file is null.
	_initialized = true
	_setup_log_file()
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


func _setup_core() -> void:
	"""Initialize snapshot reading, battle-completion detection, and the toast host."""
	var base_dir := MOD_BASE_DIR

	var GameSnapshotReader = load(base_dir.path_join("snapshots/game_snapshot_reader.gd"))
	_snapshot_reader = GameSnapshotReader.new(_has_property)

	var BattleCompletionDetector = load(base_dir.path_join("battle/battle_completion_detector.gd"))
	_battle_completion = BattleCompletionDetector.new()

	var StateCapture = load(base_dir.path_join("debug/state_capture.gd"))
	_state_capture = StateCapture.new()

	var HighScores = load(base_dir.path_join("battle/high_scores.gd"))
	if HighScores != null:
		_high_scores = HighScores.load_store()

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

	# Shop button that opens the Brain Rot Memories high-score panel.
	var MemoriesPanel = load(base_dir.path_join("hud/memories_panel.gd"))
	if MemoriesPanel != null:
		_memories_panel = MemoriesPanel.new()
		_memories_panel.name = "MemoriesPanel"
		_toast_layer.add_child(_memories_panel)


func _setup_reactions() -> void:
	"""Initialize the reaction evaluator, player, and reaction sounds."""
	var base_dir := MOD_BASE_DIR

	var ReactionEvaluator = load(base_dir.path_join("reactions/reaction_evaluator.gd"))
	_reaction_evaluator = ReactionEvaluator.new()

	var ReactionSounds = load(base_dir.path_join("audio/reaction_sounds.gd"))
	if ReactionSounds != null:
		_reaction_sounds = ReactionSounds.new(self, Callable(), Callable(self, "_current_mod_volume"))

	# Species icon lookup for monster-involving reactions. Copied from Creature
	# Comforts (core/species_icons.gd) so Brain Rot stays standalone.
	var SpeciesIcons = load(base_dir.path_join("catalog/species_icons.gd"))
	if SpeciesIcons != null:
		_species_icons = SpeciesIcons.new()

	# Reactions log, submit to the shared toast queue, forward their id to the
	# table-driven sound sink, and resolve a monster icon when one is involved.
	var ReactionPlayer = load(base_dir.path_join("reactions/reaction_player.gd"))
	var icon_fn: Callable = _species_icons.icon_for if _species_icons != null else Callable()
	_reaction_player = ReactionPlayer.new(_print_notice, _submit_notification, _play_reaction_sound, icon_fn)


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
## after every declared row. Brain Rot declares no settings, so this slider is the
## only row. It is the only volume control: Mod Volume is not declared in mod.json
## (the loader would draw a left/right stepper), and its value is stored by
## core/mod_config.gd.
##
## The settings panel does not theme generic Labels/Sliders, so a bare row draws
## blank; both controls are styled here (the loader's text theme plus explicit
## track/grabber colours from hud/styles.gd).
func make_custom_settings_menu_entries() -> Array:
	var ModConfig = load(MOD_BASE_DIR.path_join("core/mod_config.gd"))
	var Styles = load(MOD_BASE_DIR.path_join("hud/styles.gd"))
	if ModConfig == null or Styles == null:
		return []

	var volume := _read_mod_volume()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.name = "ModVolumeLabel"
	label.theme = load(SETTINGS_TEXT_THEME)
	label.text = _mod_volume_text(volume)
	box.add_child(label)

	var slider := HSlider.new()
	slider.name = "ModVolumeSlider"
	slider.min_value = float(ModConfig.MOD_VOLUME_MIN)
	slider.max_value = float(ModConfig.MOD_VOLUME_MAX)
	slider.step = float(SLIDER_STEP)
	slider.value = float(volume)
	# The menu treats a VBox row's second child as the navigable control, so the
	# label must stay first and the slider second.
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(160, 22)
	slider.tooltip_text = "Volume of the sounds Brain Rot plays."
	Styles.apply_slider(slider)
	box.add_child(slider)

	# Text follows the drag; the file is written once on release (or when focus
	# leaves the slider, which covers gamepad/keyboard changes).
	slider.value_changed.connect(func(value: float):
		label.text = _mod_volume_text(int(value)))
	slider.drag_ended.connect(func(_value_changed: bool):
		_commit_mod_volume(int(slider.value))
		_preview_sound())
	slider.focus_exited.connect(func():
		_commit_mod_volume(int(slider.value)))
	slider.tree_exiting.connect(func():
		_commit_mod_volume(int(slider.value)))

	return [box]


func _read_mod_volume() -> int:
	if _config != null:
		return _config.mod_volume()
	return 100


## Released, focus-out, and tree-exit all commit; set_mod_volume() clamps and
## skips the file write when the value did not change, so only the first counts.
func _commit_mod_volume(value: int) -> void:
	if _config == null:
		return
	_config.set_mod_volume(value)


func _mod_volume_text(value: int) -> String:
	return "Mod Volume: %d%%" % value


## Current volume for the sound players, 0-100. Read on every play so moving the
## slider affects the next sound without rebuilding any player.
func _current_mod_volume() -> int:
	if _config != null:
		return _config.mod_volume()
	return 100


## Play a sound at the newly saved volume so the slider can be judged by ear.
func _preview_sound() -> void:
	if _config == null:
		return
	if _settings_preview == null:
		var UiSound = load(MOD_BASE_DIR.path_join("audio/ui_sound.gd"))
		if UiSound == null:
			return
		_settings_preview = UiSound.new()
		_settings_preview.setup(self, "click.ogg", Callable(), Callable(self, "_current_mod_volume"))
	_settings_preview.play()


## Play the extra audio for a reaction, if the table has one.
func _play_reaction_sound(id: String) -> void:
	if _reaction_sounds != null:
		_reaction_sounds.play_for(id)


## Developer-only toast preview. Disabled unless dev/dev_config.gd says otherwise,
## so retail sessions create no extra UI.
func _setup_dev_tools() -> void:
	var DevConfig = load(MOD_BASE_DIR.path_join("dev/dev_config.gd"))
	if DevConfig == null or not DevConfig.is_enabled():
		return

	var Catalog = load(MOD_BASE_DIR.path_join("catalog/brain_rot_catalog.gd"))
	var ToastPreviewPanel = load(MOD_BASE_DIR.path_join("hud/toast_preview_panel.gd"))
	if Catalog == null or ToastPreviewPanel == null or _toast_layer == null:
		return

	_toast_preview_panel = ToastPreviewPanel.new(Catalog.reactions(), _preview_toast)
	_toast_preview_panel.name = "ToastPreviewPanel"
	_toast_layer.add_child(_toast_preview_panel)
	_print_notice("Brain Rot: dev toast preview enabled")


## Show a reaction match exactly as gameplay would, without evaluating rules or
## touching progress/saves.
func _preview_toast(match: Dictionary) -> void:
	if _reaction_player == null:
		return
	_reaction_player.play(match, true)


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
	var is_shop := _script_is(state, SHOP_SCRIPT)

	var run = _get_run_data()
	var run_snapshot: Dictionary = _snapshot_reader.read_run(run) if _snapshot_reader != null else {}
	_check_run_transition(run, run_snapshot)

	# Run-scoped reactions are evaluated only in the shop (the start of a day).
	# The game promotes the completed run into RunManager.data before the visual
	# battle ends, so lives/wins/income there already reflect the post-battle
	# result. Polling mid-battle would fire 6 7 / 6 9 before the player sees the
	# next day. Battle-scoped reactions still fire at battle_over.
	_poll_reactions(run_snapshot, is_shop)
	_log_run_progress(run_snapshot)

	var battle_snapshot: Dictionary = {}
	if is_battle:
		# A new battle starts fresh battle-scoped reaction tracking.
		if not _was_battle:
			if _reaction_evaluator != null:
				_reaction_evaluator.reset_battle()
			_log_battle_probe(state)

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
			_log_event("BATTLE COMPLETE | usable=%s units=%s team=%s trainer=%s" % [
				str(usable),
				str(battle_snapshot.get("battle_units").size()) if battle_snapshot.get("battle_units") is Array else "absent",
				str(battle_snapshot.get("team").size()) if battle_snapshot.get("team") is Array else "absent",
				str(battle_snapshot.get("trainer_id", "absent")),
			])
			if usable:
				_battle_completion.consume()
				_log_battle_units(battle_snapshot)
				_record_high_scores(battle_snapshot)
				_poll_battle_reactions(battle_snapshot)
	elif _was_battle:
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _battle_completion != null:
			_battle_completion.reset()

	_was_battle = is_battle
	_update_memories_panel(is_shop)
	_maybe_capture(battle_snapshot if is_battle else run_snapshot)


## Poll the run snapshot for newly triggered reactions and play them.
##
## `is_shop` gates run-scoped evaluation to the start of a day. Outside the shop
## (battle, battle results, transitions) the committed post-battle lives/wins are
## already in RunManager.data, so polling would reveal the result before the
## player sees the next day. The evaluator stays phase-agnostic; this only decides
## when to call it.
func _poll_reactions(run_snapshot: Dictionary, is_shop: bool) -> void:
	if _reaction_evaluator == null or _reaction_player == null:
		return
	_note_run_reaction_gate(is_shop)
	if not is_shop:
		_last_shop_snapshot = {}
		return
	_reaction_player.play_all(_reaction_evaluator.poll(run_snapshot))
	_reaction_player.play_all(_reaction_evaluator.poll_sold(_last_shop_snapshot, run_snapshot))
	_reaction_player.play_all(_reaction_evaluator.poll_buff(_last_shop_snapshot, run_snapshot))
	_last_shop_snapshot = run_snapshot


## Log the run-reaction phase gate only when it changes, so the first real session
## can confirm the gate holds without spamming the 500 ms poll.
func _note_run_reaction_gate(is_shop: bool) -> void:
	var state := "shop" if is_shop else "deferred"
	if state == _run_reaction_gate_state:
		return
	_run_reaction_gate_state = state
	if is_shop:
		_log_event("RUN REACTIONS | active (shop)")
	else:
		_log_event("RUN REACTIONS | deferred (not shop)")


## Poll a completed battle snapshot for battle-scoped reactions (final unit totals).
func _poll_battle_reactions(battle_snapshot: Dictionary) -> void:
	if _reaction_evaluator == null or _reaction_player == null:
		return
	var triggered: Array = _reaction_evaluator.poll_battle(battle_snapshot)
	_log_event("REACTION BATTLE | %d triggered" % triggered.size())
	_reaction_player.play_all(triggered)


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
		_log_event("HIGH SCORE | %s %d by %s (was %d)" % [
			str(metric),
			int(row.get("value", 0)),
			HighScores.format_unit(str(row.get("unit", ""))),
			int(row.get("previous", 0)),
		])


## Show the Brain Rot Memories button only while the shop is active, and keep
## its table in sync with the current high-score store.
func _update_memories_panel(is_shop: bool) -> void:
	if _memories_panel == null:
		return
	if is_shop:
		_memories_panel.set_scores(_high_scores)
		_memories_panel.show_button()
	else:
		_memories_panel.hide_panel()


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
	_last_shop_snapshot = {}
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
