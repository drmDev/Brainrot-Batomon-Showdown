extends Node
## Batomon Achievements - standalone achievement detection, persistence, and toast.
##
## Polls the live run and battle state every 500 ms, evaluates achievements via
## achievements/achievement_evaluator.gd, persists completion through
## achievements/achievement_store.gd, and shows a bottom-right toast through
## achievements/achievement_panel.gd when the Achievement Notifications setting is on.
##
## This mod is self-contained: it does not depend on Creature Comforts.

const VERSION := "9.0.0.3"
const MOD_ID := "batomon_achievements"
const BATTLE_SCRIPT := "res://game/states/battle_state.gd"

# Polling interval (matches the game's shop/battle state cadence)
const POLL_INTERVAL_MS := 500

# Optional debug capture. When set to an absolute directory, each changed run/battle
# snapshot is written there as JSON for replay under tests/ (see dev/QUALITY.md).
# Unset during normal play, so nothing is written.
const DUMP_ENV_VAR := "BATOMON_ACHIEVEMENTS_DUMP_DIR"

# Settings (defaults match mod.json)
const DEFAULT_ACHIEVEMENT_NOTIFICATIONS := false

var _achievement_notifications := DEFAULT_ACHIEVEMENT_NOTIFICATIONS
var _settings_load_attempted := false
var _settings_warning_shown := false

# Achievement system: poll-based detection + JSON persistence + bottom-right panel
var _battle_completion = null
var _achievement_evaluator = null
var _achievement_store = null
var _achievement_panel = null
var _achievement_layer: CanvasLayer = null

var _next_poll := 0
var _last_phase := ""
var _initialization_started := false
var _initialized := false

# Debug-capture state (only used when DUMP_ENV_VAR is set).
var _dump_dir := ""
var _last_dump_signature := ""
var _dump_counter := 0


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
		push_warning("Batomon Achievements: ModLoader.get_config() not available, using defaults")


func _initialize_mod() -> void:
	if _initialization_started:
		return
	_initialization_started = true

	_load_settings()
	_setup_achievement_system()

	_initialized = true
	print("Batomon Achievements %s loaded" % VERSION)


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
	var base_dir := "res://mods/BatomonAchievements"

	var BattleCompletionDetector = load(base_dir.path_join("achievements/battle_completion_detector.gd"))
	_battle_completion = BattleCompletionDetector.new()

	var AchievementEvaluator = load(base_dir.path_join("achievements/achievement_evaluator.gd"))
	_achievement_evaluator = AchievementEvaluator.new(_has_property)

	# Store the JSON at the mod root (next to mod_main.gd).
	var AchievementStore = load(base_dir.path_join("achievements/achievement_store.gd"))
	_achievement_store = AchievementStore.new(base_dir)

	# Dedicated layer so the toast can appear over the battle results screen.
	_achievement_layer = CanvasLayer.new()
	_achievement_layer.layer = 100
	_achievement_layer.name = "BatomonAchievements_Layer"
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

	# Run-scoped achievements are evaluated every poll (the Twins transformation
	# happens in the shop, but polling all phases keeps the team baseline current).
	_poll_achievements()

	if is_battle:
		# Battle-scoped achievements are evaluated once the battle is over.
		if _battle_completion != null and _battle_completion.poll(state):
			_poll_battle_achievements(state)
	elif _last_phase == "battle":
		# Reset battle-scoped tracking only when actually leaving the battle phase.
		if _battle_completion != null:
			_battle_completion.reset()
		if _achievement_evaluator != null:
			_achievement_evaluator.reset_battle()

	_last_phase = "battle" if is_battle else ""
	_maybe_dump_state(state, is_battle)


## Poll the run for newly earned achievements, persist them, and show the panel.
func _poll_achievements() -> void:
	if _achievement_evaluator == null:
		return
	var run = _get_run_data()
	if run == null or not is_instance_valid(run):
		return

	_award_achievements(_achievement_evaluator.poll(run))


## Poll the active battle for battle-scoped achievements (Big Dog, Best Dog).
func _poll_battle_achievements(state) -> void:
	if _achievement_evaluator == null:
		return
	var run = _get_run_data()
	if run == null or not is_instance_valid(run):
		return

	_award_achievements(_achievement_evaluator.poll_battle(state, run))


## Persist and display newly earned achievements (deduplicated by the store).
func _award_achievements(earned: Array) -> void:
	if _achievement_store == null or _achievement_panel == null:
		return
	for achievement in earned:
		var id := str(achievement.get("id", ""))
		if id.is_empty() or _achievement_store.is_completed(id):
			continue
		var title := str(achievement.get("title", ""))
		var description := str(achievement.get("description", ""))
		if title.is_empty() or description.is_empty():
			continue

		_achievement_store.mark_completed(id)
		print("Batomon Achievements: EARNED | %s | %s" % [id, title])
		if _achievement_notifications:
			_achievement_panel.show_achievement(title, description)


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


## Write a run/battle snapshot when DUMP_ENV_VAR is set and the snapshot changed.
func _maybe_dump_state(state, is_battle: bool) -> void:
	if _dump_dir.is_empty():
		_dump_dir = OS.get_environment(DUMP_ENV_VAR)
		if _dump_dir.is_empty():
			return
		DirAccess.make_dir_recursive_absolute(_dump_dir)

	var snapshot := _serialize_state(_get_run_data(), state, is_battle)
	var signature := JSON.stringify(snapshot)
	if signature == _last_dump_signature:
		return
	_last_dump_signature = signature
	_dump_counter += 1

	var file_path := _dump_dir.path_join("state_%06d_%d.json" % [_dump_counter, Time.get_ticks_msec()])
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_warning("Batomon Achievements: cannot write state dump: " + file_path)
		return
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()


## Serialize only the fields the achievement evaluator reads. This doubles as a
## written contract for the game data the rules depend on.
func _serialize_state(run, state, is_battle: bool) -> Dictionary:
	var snapshot := {"kind": "battle" if is_battle else "run"}
	if run != null and is_instance_valid(run):
		if _has_property(run, "trainer_id"):
			snapshot["trainer_id"] = str(run.get("trainer_id"))
		if _has_property(run, "current_round"):
			snapshot["current_round"] = int(run.get("current_round"))
		for list_name in ["team", "bench"]:
			if _has_property(run, list_name):
				snapshot[list_name] = _serialize_monsters(run.get(list_name))
	if is_battle and state != null and is_instance_valid(state):
		var sim = state.get("simulation") if _has_property(state, "simulation") else null
		if sim != null and is_instance_valid(sim):
			var data = sim.get("data") if _has_property(sim, "data") else null
			if data != null:
				if _has_property(data, "battle_over"):
					snapshot["battle_over"] = bool(data.get("battle_over"))
				if _has_property(data, "battle_units"):
					snapshot["battle_units"] = _serialize_battle_units(data.get("battle_units"))
	return snapshot


func _serialize_monsters(monsters) -> Array:
	var out: Array = []
	if not monsters is Array:
		return out
	for monster in monsters:
		var entry := {}
		if monster != null and is_instance_valid(monster):
			if _has_property(monster, "data"):
				var data = monster.get("data")
				if data != null and _has_property(data, "name_key"):
					entry["name_key"] = str(data.get("name_key"))
			if _has_property(monster, "level"):
				entry["level"] = int(monster.get("level"))
		out.append(entry)
	return out


func _serialize_battle_units(units) -> Array:
	var out: Array = []
	if not units is Array:
		return out
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		var entry := {}
		if _has_property(unit, "team_id"):
			entry["team_id"] = int(unit.get("team_id"))
		if _has_property(unit, "slot_index"):
			entry["slot_index"] = int(unit.get("slot_index"))
		if _has_property(unit, "shield_granted"):
			entry["shield_granted"] = float(unit.get("shield_granted"))
		out.append(entry)
	return out


func _is_loaded_by_mod_loader() -> bool:
	if not is_inside_tree():
		return false
	var parent_node = get_parent()
	return parent_node != null and parent_node == get_node_or_null("/root/ModLoader")
