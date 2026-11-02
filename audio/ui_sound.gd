extends RefCounted
## Reusable one-shot sound player for the mod's OGG files.
##
## Adapted from Creature Comforts' core/ui_sound.gd. Each instance owns one
## AudioStreamPlayer on the host node, named after its file, so several sounds can
## share a host without stealing each other's player. The stream is loaded lazily on
## the first play, which keeps setup cheap and lets the host exist before it is
## added to the tree.
##
## `enabled` is an optional gate; when it returns false, play() is a no-op.
##
## Usage:
##   var sound := UiSound.new()
##   sound.setup(self, "over-9000.ogg")
##   sound.play()

const SOUND_DIR := "../assets/sounds/"
const PLAYER_PREFIX := "BrainRotSound_"
const VOLUME_DB := -6.0

var _host: Node
var _path := ""
var _player_name := ""
var _enabled: Callable
var _volume_db := VOLUME_DB
var _stream: AudioStream
var _player: AudioStreamPlayer
var _load_attempted := false


func setup(
	host: Node,
	file_name: String,
	enabled: Callable = Callable(),
	volume_db: float = VOLUME_DB
) -> void:
	_host = host
	_path = _resolve_path(file_name)
	_player_name = PLAYER_PREFIX + file_name.get_basename()
	_enabled = enabled
	_volume_db = volume_db


func play() -> void:
	if _enabled.is_valid() and not bool(_enabled.call()):
		return
	# AudioStreamPlayer.play() errors on a node outside the tree, so wait until
	# the host is live.
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = _host.get_node_or_null(_player_name)
		if not (_player is AudioStreamPlayer):
			_player = AudioStreamPlayer.new()
			_player.name = _player_name
			_player.volume_db = _volume_db
			_host.add_child(_player)
	if _player.stream == null:
		_player.stream = _load_stream()
	if _player.stream == null:
		return
	_player.play()


## Resolve a sound file against this script's own directory, so callers only pass
## a file name and the mod can live anywhere on disk.
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
