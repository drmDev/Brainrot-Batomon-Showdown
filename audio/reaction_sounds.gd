extends RefCounted
## ReactionSounds - table-driven one-shot sounds for reactions.
##
## The table is derived from catalog/brain_rot_catalog.gd, so a reaction's
## `sound` block is the only place its audio is declared. Gameplay and the dev
## toast preview both call play_for(id), so they cannot drift.
##
## Rows: {"file": String}. One UiSound is created per FILE (rows sharing a file
## share a player) and loaded lazily on first play.

const UiSound = preload("ui_sound.gd")
const Catalog = preload("../catalog/brain_rot_catalog.gd")

static var REACTION_SOUNDS := Catalog.sounds()

var _host: Node
var _enabled: Callable
var _volume: Callable
var _players: Dictionary = {}  # file name -> UiSound


## host: node that owns the AudioStreamPlayers. enabled: optional gate.
## volume: optional 0-100 provider (the Mod Volume slider).
func _init(host: Node = null, enabled: Callable = Callable(), volume: Callable = Callable()) -> void:
	_host = host
	_enabled = enabled
	_volume = volume


## Play the sound registered for a reaction id. Unknown ids are a no-op.
func play_for(reaction_id: String) -> void:
	var file_name := file_for(reaction_id)
	if file_name.is_empty():
		return
	_player_for(file_name).play()


## Registered file name for a reaction id, or "" when it has no sound.
func file_for(reaction_id: String) -> String:
	var row = REACTION_SOUNDS.get(reaction_id)
	if not row is Dictionary:
		return ""
	return str(row.get("file", ""))


func has_sound(reaction_id: String) -> bool:
	return not file_for(reaction_id).is_empty()


func _player_for(file_name: String):
	if _players.has(file_name):
		return _players[file_name]
	var sound = UiSound.new()
	sound.setup(_host, file_name, _enabled, _volume)
	_players[file_name] = sound
	return sound
