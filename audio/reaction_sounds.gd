extends RefCounted
## ReactionSounds - table-driven one-shot sounds for reactions.
##
## Adding a reaction sound is one row in REACTION_SOUNDS plus the OGG file in
## assets/sounds/. Gameplay and the dev toast preview both call play_for(id), so
## they cannot drift.
##
## Rows: {"file": String, "volume_db": float optional}. One UiSound is created per
## FILE (rows sharing a file share a player) and loaded lazily on first play.

const UiSound = preload("ui_sound.gd")

const REACTION_SOUNDS := {
	"over_9000": {"file": "over-9000.ogg"},
	"flawless_victory": {"file": "ff_fanfare.ogg"},
}

var _host: Node
var _enabled: Callable
var _players: Dictionary = {}  # file name -> UiSound


## host: node that owns the AudioStreamPlayers. enabled: optional gate.
func _init(host: Node = null, enabled: Callable = Callable()) -> void:
	_host = host
	_enabled = enabled


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
	sound.setup(_host, file_name, _enabled, _volume_for(file_name))
	_players[file_name] = sound
	return sound


## Volume for a file; the first row using that file wins. Defaults to UiSound.DEFAULT.
func _volume_for(file_name: String) -> float:
	for row in REACTION_SOUNDS.values():
		if row is Dictionary and str(row.get("file", "")) == file_name:
			return float(row.get("volume_db", UiSound.VOLUME_DB))
	return UiSound.VOLUME_DB
