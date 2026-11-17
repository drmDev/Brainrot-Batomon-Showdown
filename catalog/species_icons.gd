extends RefCounted
## Species icon lookup backed by the game's GameDatabase.
##
## The game exposes every species through `GameDatabase.get_all_species()`, and
## each species carries a `name_key` plus a `texture` Texture2D (the same sprite
## the watchlist and the game's own UI use). This is the minimum extracted from
## Creature Comforts' watchlist catalog loader; no catalog, filters or formatting
## are needed.
##
## The index is built lazily and an empty result is not cached, so a lookup made
## before GameDatabase is ready retries on the next call.
##
## Adapted from Creature Comforts (core/species_icons.gd), which was itself ported
## from BatoStats++. Brain Rot stays standalone, so this is a copy, not a runtime
## dependency.

const NodeUtils = preload("node_utils.gd")

static var _index: Dictionary = {}  # lowercased species key -> Texture2D


## Icon for a species key (e.g. "monster.name.leafleap"), or null when the key is
## unknown, GameDatabase is unavailable, or the species has no Texture2D. `db` is
## a test hook; production callers omit it to use the GameDatabase autoload.
static func icon_for(species_key: String, db = null) -> Texture2D:
	var key := species_key.strip_edges().to_lower()
	if key.is_empty():
		return null
	if _index.is_empty():
		_build_index(db)
	var icon = _index.get(key)
	return icon if icon is Texture2D else null


## Drop the cached index (used by tests).
static func reset() -> void:
	_index = {}


static func _build_index(db_override) -> void:
	var db = db_override if db_override != null else NodeUtils.get_autoload("GameDatabase")
	if not (db is Object) or not db.has_method("get_all_species"):
		return
	var species_list = db.call("get_all_species")
	if not (species_list is Array):
		return
	var index := {}
	for species in species_list:
		if species == null or not NodeUtils.has_property(species, "texture"):
			continue
		var texture = species.get("texture")
		if not (texture is Texture2D):
			continue
		for prop in ["name_key", "id"]:
			if not NodeUtils.has_property(species, prop):
				continue
			var raw = species.get(prop)
			var key := str(raw).strip_edges().to_lower() if raw != null else ""
			if not key.is_empty():
				index[key] = texture
	# Do not cache an empty index: GameDatabase may not be ready yet.
	if not index.is_empty():
		_index = index