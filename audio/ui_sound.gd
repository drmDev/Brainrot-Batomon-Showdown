extends RefCounted
## Reusable one-shot sound player for the mod's OGG files.
##
## Each instance owns one AudioStreamPlayer on the host node, named after its
## file, so several sounds can share a host without stealing each other's player.
## The stream is loaded lazily on the first play.
##
## `enabled` is an optional gate (e.g. a future sounds-on setting); when it
## returns false, play() is a no-op.
##
## `volume` is an optional 0-100 provider (e.g. the Mod Volume slider). It is
## read again on every play(), so moving the slider affects the next sound
## without rebuilding any player. 100 maps to VOLUME_DB.

const SOUND_DIR := "../assets/sounds/"
const PLAYER_PREFIX := "BrainRotSound_"
const VOLUME_DB := -6.0
const MAX_PERCENT := 100.0
const SILENT_DB := -80.0

var _host: Node
var _path := ""
var _player_name := ""
var _enabled: Callable
var _volume: Callable
var _stream: AudioStream
var _player: AudioStreamPlayer
var _load_attempted := false


func setup(host: Node, file_name: String, enabled: Callable = Callable(), volume: Callable = Callable()) -> void:
	_host = host
	_path = _resolve_path(file_name)
	_player_name = PLAYER_PREFIX + file_name.get_basename()
	_enabled = enabled
	_volume = volume


func play() -> void:
	if _enabled.is_valid() and not bool(_enabled.call()):
		return
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = _host.get_node_or_null(_player_name)
		if not (_player is AudioStreamPlayer):
			_player = AudioStreamPlayer.new()
			_player.name = _player_name
			_host.add_child(_player)
	_apply_volume()
	if _player.stream == null:
		_player.stream = _load_stream()
	if _player.stream == null:
		return
	_player.play()


## Map a 0-100 percentage onto dB relative to the module's ceiling.
static func volume_db_for(percent: float) -> float:
	var clamped := clampf(percent, 0.0, MAX_PERCENT)
	if clamped <= 0.0:
		return SILENT_DB
	return VOLUME_DB + linear_to_db(clamped / MAX_PERCENT)


func _apply_volume() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var percent := MAX_PERCENT
	if _volume.is_valid():
		var value = _volume.call()
		if value is int or value is float:
			percent = float(value)
	_player.volume_db = volume_db_for(percent)


func _resolve_path(file_name: String) -> String:
	return str(get_script().resource_path).get_base_dir().path_join(SOUND_DIR + file_name)


func _load_stream() -> AudioStream:
	if _load_attempted:
		return _stream
	_load_attempted = true
	if _path.is_empty() or not FileAccess.file_exists(_path):
		push_warning("Brain Rot: sound not found: %s" % _path)
		return null
	_stream = AudioStreamOggVorbis.load_from_file(_path)
	if _stream == null:
		push_warning("Brain Rot: cannot load sound: %s" % _path)
	return _stream
