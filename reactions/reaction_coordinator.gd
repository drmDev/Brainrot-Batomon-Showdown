extends RefCounted
## Reaction coordinator for Brain Rot.
##
## Extracted from mod_main.gd. Owns the evaluator, player, sounds, and species
## icons, plus the run/battle polling that drives them. mod_main only decides
## when to poll; this decides what to do with the snapshots.

const MOD_BASE_DIR := "res://mods/BrainRot"
const ModLogger = preload("../core/mod_logger.gd")

var _logger = ModLogger.new()
var _evaluator = null
var _player = null
var _sounds = null
var _species_icons = null
var _last_shop_snapshot: Dictionary = {}
var _run_reaction_gate_state := ""


## Build the evaluator, sounds, species icons, and player. `host` owns the audio
## players; `logger` is the session logger; `submit_notification` forwards toasts;
## `volume` is the current Mod Volume provider.
func setup(host: Node, logger, submit_notification: Callable, volume: Callable) -> void:
	_logger = logger

	var ReactionEvaluator = load(MOD_BASE_DIR.path_join("reactions/reaction_evaluator.gd"))
	_evaluator = ReactionEvaluator.new()

	var ReactionSounds = load(MOD_BASE_DIR.path_join("audio/reaction_sounds.gd"))
	if ReactionSounds != null:
		_sounds = ReactionSounds.new(host, Callable(), volume)

	# Species icon lookup for monster-involving reactions. Copied from Creature
	# Comforts (core/species_icons.gd) so Brain Rot stays standalone.
	var SpeciesIcons = load(MOD_BASE_DIR.path_join("catalog/species_icons.gd"))
	if SpeciesIcons != null:
		_species_icons = SpeciesIcons.new()

	# Reactions log, submit to the shared toast queue, forward their id to the
	# table-driven sound sink, and resolve a monster icon when one is involved.
	var ReactionPlayer = load(MOD_BASE_DIR.path_join("reactions/reaction_player.gd"))
	var icon_fn: Callable = _species_icons.icon_for if _species_icons != null else Callable()
	_player = ReactionPlayer.new(logger.print_notice, submit_notification, _play_sound, icon_fn)


## Play the extra audio for a reaction, if the table has one.
func _play_sound(id: String) -> void:
	if _sounds != null:
		_sounds.play_for(id)


## Poll the run snapshot for newly triggered reactions and play them.
##
## `is_shop` gates run-scoped evaluation to the start of a day. Outside the shop
## (battle, battle results, transitions) the committed post-battle lives/wins are
## already in RunManager.data, so polling would reveal the result before the
## player sees the next day. The evaluator stays phase-agnostic; this only decides
## when to call it.
func poll_reactions(run_snapshot: Dictionary, is_shop: bool) -> void:
	if _evaluator == null or _player == null:
		return
	_note_run_reaction_gate(is_shop)
	if not is_shop:
		_last_shop_snapshot = {}
		return
	_player.play_all(_evaluator.poll(run_snapshot))
	_player.play_all(_evaluator.poll_sold(_last_shop_snapshot, run_snapshot))
	_player.play_all(_evaluator.poll_buff(_last_shop_snapshot, run_snapshot))
	_last_shop_snapshot = run_snapshot


## Log the run-reaction phase gate only when it changes, so the first real session
## can confirm the gate holds without spamming the 500 ms poll.
func _note_run_reaction_gate(is_shop: bool) -> void:
	var state := "shop" if is_shop else "deferred"
	if state == _run_reaction_gate_state:
		return
	_run_reaction_gate_state = state
	if is_shop:
		_logger.log_event("RUN REACTIONS | active (shop)")
	else:
		_logger.log_event("RUN REACTIONS | deferred (not shop)")


## Poll a completed battle snapshot for battle-scoped reactions (final unit totals).
func poll_battle_reactions(battle_snapshot: Dictionary) -> void:
	if _evaluator == null or _player == null:
		return
	var triggered: Array = _evaluator.poll_battle(battle_snapshot)
	_logger.log_event("REACTION BATTLE | %d triggered" % triggered.size())
	_player.play_all(triggered)


## Reset run-scoped reaction state (the sold/buff baseline and the evaluator).
func reset_run() -> void:
	_last_shop_snapshot = {}
	if _evaluator != null:
		_evaluator.reset_run()


## Reset battle-scoped reaction tracking.
func reset_battle() -> void:
	if _evaluator != null:
		_evaluator.reset_battle()


## Show a reaction match exactly as gameplay would, without evaluating rules or
## touching progress/saves.
func play_preview(match: Dictionary) -> void:
	if _player != null:
		_player.play(match, true)
