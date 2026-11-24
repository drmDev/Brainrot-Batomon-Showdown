extends RefCounted
## AchievementStore - persistent record of which Reactions the player has earned.
##
## The store is a versioned JSON dictionary:
##   {
##     "version": 1,
##     "reactions": {
##       "over_9000": {"first_date": "11/18/26", "first_run": "<run_id>", "runs": 3, "last_run": "<run_id>"},
##       ...
##     }
##   }
##
## Achievements are global across runs (like high scores), so they live in their
## own file rather than in the per-run occurrences store. `first_date` and
## `first_run` are set once on the first earn; `runs` counts the runs in which
## the reaction fired, incrementing at most once per run key (`last_run` tracks
## the most recent run so a reaction firing twice in one run counts once).
##
## record() mutates the store in place and reports whether anything changed, so
## callers can write only on change. Mirrors battle/high_scores.gd for the JSON
## load/save pattern.

const DateUtil = preload("date_util.gd")

const PATH := "user://brain_rot/achievements.json"
const VERSION := 1


static func empty_store() -> Dictionary:
	return {"version": VERSION, "reactions": {}}


## Current local date as MM/DD/YY (e.g. "11/18/26").
static func current_date_string() -> String:
	return DateUtil.current_date_string()


## Parse a store from JSON text. Missing, corrupt, or wrongly typed data yields an
## empty store; malformed reaction entries are dropped.
static func parse(text: String) -> Dictionary:
	var store := empty_store()
	if text.strip_edges().is_empty():
		return store
	var json := JSON.new()
	if json.parse(text) != OK:
		return store
	var parsed = json.data
	if not parsed is Dictionary:
		return store
	var raw_reactions = parsed.get("reactions")
	if not raw_reactions is Dictionary:
		return store
	var reactions := {}
	for id in raw_reactions:
		var entry := _normalize_entry(raw_reactions[id])
		if not entry.is_empty():
			reactions[str(id)] = entry
	store["reactions"] = reactions
	return store


static func serialize(store: Dictionary) -> String:
	return JSON.stringify(store, "\t")


static func load_store(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty_store()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Brain Rot: cannot read achievements at %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return empty_store()
	var text := file.get_as_text()
	file.close()
	return parse(text)


static func save_store(store: Dictionary, path: String = PATH) -> bool:
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_warning("Brain Rot: cannot create achievements directory %s: %s" % [abs_dir, error_string(dir_err)])
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Brain Rot: cannot write achievements to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(serialize(store))
	file.close()
	return true


## Record that `id` fired in `run_key` on `date`. Sets first_date/first_run on the
## first earn and increments `runs` at most once per run key. Mutates `store` in
## place; returns true when the store changed.
static func record(store: Dictionary, id: String, run_key: String, date: String) -> bool:
	if id.is_empty() or run_key.is_empty():
		return false
	var reactions = store.get("reactions")
	if not reactions is Dictionary:
		reactions = {}
		store["reactions"] = reactions
	var entry = reactions.get(id)
	if entry is Dictionary:
		if str(entry.get("last_run", "")) == run_key:
			return false
		entry["runs"] = int(entry.get("runs", 0)) + 1
		entry["last_run"] = run_key
		return true
	reactions[id] = {"first_date": date, "first_run": run_key, "runs": 1, "last_run": run_key}
	return true


## How many reactions the player has earned.
static func earned_count(store: Dictionary) -> int:
	var reactions = store.get("reactions")
	return reactions.size() if reactions is Dictionary else 0


static func _normalize_entry(raw) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var first_date := str(raw.get("first_date", ""))
	var first_run := str(raw.get("first_run", ""))
	var runs := int(raw.get("runs", 0))
	var last_run := str(raw.get("last_run", ""))
	if first_date.is_empty() and first_run.is_empty() and runs <= 0:
		return {}
	return {"first_date": first_date, "first_run": first_run, "runs": runs, "last_run": last_run}