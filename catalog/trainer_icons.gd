extends RefCounted
## Trainer portrait lookup backed by the game's own trainer data.
##
## GameDatabase.get_trainer_by_id(id) returns the trainer resource, and the game's
## res://game/trainers/trainer_portrait.gd turns it into the small portrait the
## trainer-select screen shows (TrainerPortrait.crop_for(trainer, Kind.SMALL)).
## The portrait script is loaded lazily and optionally: when it is missing or its
## API differs, the lookup falls back to a plain Texture2D property on the trainer
## resource, and finally to null. A miss is never an error; callers just draw
## nothing in the portrait slot.
##
## Found portraits are cached by trainer id (misses are not, so a lookup made
## before GameDatabase is ready retries on the next call).
##
## Adapted from Creature Comforts (core/trainer_icons.gd). Brain Rot stays
## standalone, so this is a copy, not a runtime dependency.

const NodeUtils = preload("node_utils.gd")

const PORTRAIT_SCRIPT_PATH := "res://game/trainers/trainer_portrait.gd"
const KIND_NAME := "SMALL"
# Texture2D properties tried on the trainer resource when the portrait script
# cannot supply a crop.
const FALLBACK_PROPS := ["portrait", "portrait_small", "icon", "texture", "sprite"]

static var _cache: Dictionary = {}  # trainer id -> Texture2D


## Portrait for a trainer id (e.g. "chef"), or null when it cannot be resolved.
## `db` and `portrait_script` are test hooks; production callers omit them to use
## the GameDatabase autoload and the game's trainer_portrait.gd.
static func icon_for(trainer_id: String, db = null, portrait_script = null) -> Texture2D:
	var id := trainer_id.strip_edges()
	if id.is_empty():
		return null
	var cached = _cache.get(id)
	if cached is Texture2D:
		return cached
	var trainer = _find_trainer(id, db)
	if trainer == null:
		return null
	var icon := _crop(trainer, portrait_script)
	if icon == null:
		icon = _fallback_texture(trainer)
	if icon != null:
		_cache[id] = icon
	return icon


## Drop the cached portraits (used by tests).
static func reset() -> void:
	_cache = {}


static func _find_trainer(id: String, db_override):
	var db = db_override if db_override != null else NodeUtils.get_autoload("GameDatabase")
	if not (db is Object) or not db.has_method("get_trainer_by_id"):
		return null
	return db.call("get_trainer_by_id", id)


## The game's own small portrait crop, via its trainer_portrait.gd script.
static func _crop(trainer, script_override) -> Texture2D:
	var script = script_override if script_override != null else _load_portrait_script()
	if not (script is Script) or not _has_script_method(script, "crop_for"):
		return null
	var kinds = script.get("Kind")
	if not (kinds is Dictionary) or not kinds.has(KIND_NAME):
		return null
	var result = script.call("crop_for", trainer, kinds[KIND_NAME])
	return result if result is Texture2D else null


## True when `script` declares `method_name`. Object.has_method does not see the
## static functions of a script resource, so read the script's method list.
static func _has_script_method(script: Script, method_name: String) -> bool:
	for method in script.get_script_method_list():
		if str(method.get("name", "")) == method_name:
			return true
	return false


static func _load_portrait_script():
	if not ResourceLoader.exists(PORTRAIT_SCRIPT_PATH):
		return null
	return load(PORTRAIT_SCRIPT_PATH)


static func _fallback_texture(trainer) -> Texture2D:
	for prop in FALLBACK_PROPS:
		if not NodeUtils.has_property(trainer, prop):
			continue
		var value = trainer.get(prop)
		if value is Texture2D:
			return value
	return null
