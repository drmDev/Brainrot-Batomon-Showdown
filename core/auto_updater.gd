extends Node
## Brain Rot self-updater. Once per game start (and every 6 h while the game runs) it reads
## the release manifest (update.json) from the mod's GitHub releases. When a newer Brain Rot
## is out it downloads the release zip and checks it before anything on disk changes:
##   * SHA-256 and size = the manifest's, the address starts with the mod's own release URL
##   * only BrainRot/<file> or <folder>/<file> entries from the folders below, plain
##     ASCII text for scripts/data, PNG / OGG signatures for images/sounds, nothing else
##   * the version inside (mod.json + mod_main.gd) = the manifest's
##   * every script of the update compiles on THIS game build (loaded from a staging folder)
## Then it replaces the files of its own folder (old ones backed up, put back if a swap fails) and
## removes scripts the new version no longer has. The running game keeps the old scripts; the new
## version starts with the next game start. Nothing outside Mods/BrainRot and
## user://brain_rot_update is written.
##
## Auto-update is always on (Brain Rot has no settings). It never runs on a developer install
## (a folder with .git or dev/run_tests.ps1): it would overwrite the working copy. Engine APIs
## only (no game classes), so it keeps working when a game patch breaks the overlay - which is
## exactly when a fixed version has to arrive.
##
## Manifest (a release asset, built by dev/package_release.ps1):
##   {"mod": "brain_rot", "version": "0.0.0.44", "url": "<zip address>",
##    "sha256": "<hex>", "size": 123456, "notes": "one line"}
## user://brain_rot/update.cfg [update] keys (shared by every version - keep them stable):
##   installed_version, announced, notes

signal finished(state: String)  # current | available | installed | no_release | offline | error

const MOD_ID := "brain_rot"
const REPO_URL := "https://github.com/drmDev/Brainrot-Batomon-Showdown"
const MANIFEST_URL := REPO_URL + "/releases/latest/download/update.json"
const DOWNLOAD_PREFIX := REPO_URL + "/releases/download/"
const WORK_DIR := "user://brain_rot_update"
const CFG_PATH := "user://brain_rot/update.cfg"
## The release zip's top-level folder: it is extracted into Mods/, so the entries are
## BrainRot/<file> (same layout as dev/package_release.ps1).
const ZIP_ROOT := "BrainRot/"

## Folders of the mod that may be written (and pruned) by an update.
const TOP_DIRS := ["audio", "battle", "catalog", "core", "debug", "hud", "notifications", "reactions", "snapshots", "dev", "assets"]
const TEXT_EXT := ["gd", "json", "md"]

const FIRST_CHECK_SEC := 4.0
const RECHECK_SEC := 6.0 * 3600.0
const MAX_MANIFEST := 64 * 1024
const MAX_ZIP := 16 * 1024 * 1024
const MAX_UNZIPPED := 32 * 1024 * 1024

const NAME_PATTERN := "^[A-Za-z0-9_\\-]+\\.[A-Za-z0-9]+$"
const SEGMENT_PATTERN := "^[A-Za-z0-9_\\-][A-Za-z0-9_.\\-]*$"
const VERSION_PATTERN := "^\\d+(\\.\\d+){0,3}(-[A-Za-z0-9.]+)?$"

const OFFLINE_RESULTS := [
	HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE,
	HTTPRequest.RESULT_CONNECTION_ERROR, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
	HTTPRequest.RESULT_NO_RESPONSE, HTTPRequest.RESULT_TIMEOUT,
]

var version := ""
var mod_dir := ""                     # folder of the running mod_main.gd (absolute or res://)
var cfg: ConfigFile
var auto_update := true
var manifest_url := MANIFEST_URL
var allow_prefix := DOWNLOAD_PREFIX
var enabled := true                   # dev / test builds: only with a test channel (setup)
var state := "idle"                   # idle | checking | downloading | one of the finished() states
var detail := ""                      # reason of the last error / version found or installed
var remote: Dictionary = {}           # last valid manifest
var installed := ""                   # version installed this session (waits for the restart)

var _next_check_ms := -1
var _layer: CanvasLayer
var _toast = null
var _shown := {}                      # notices already shown this session


## Called by mod_main once. auto is the Auto-update setting; mod_dir is the folder of the running
## mod_main.gd (res:// in the editor, an absolute OS path in the Mod Loader).
func setup(p_version: String, p_mod_dir: String, auto: bool) -> void:
	version = p_version
	mod_dir = p_mod_dir
	auto_update = auto
	DirAccess.make_dir_recursive_absolute(CFG_PATH.get_base_dir())
	cfg = ConfigFile.new()
	cfg.load(CFG_PATH)  # a missing / unreadable file just leaves the defaults
	if OS.has_feature("editor"):
		# dev / test builds never call the real channel unless a run asks for it
		enabled = false
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--brain-rot-update="):
				manifest_url = a.trim_prefix("--brain-rot-update=")
				enabled = true
			elif a.begins_with("--brain-rot-update-allow="):
				allow_prefix = a.trim_prefix("--brain-rot-update-allow=")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.name = "BrainRotUpdateNotice"
	add_child(_layer)


## Called once the mod booted: the "updated" notice after a successful swap, then the check schedule.
func start() -> void:
	var dir := os_dir()
	if is_dev_install(dir):
		enabled = false
		state = "dev_install"
		print("Brain Rot update: dev install (%s) - auto-update off" % dir)
		return
	if str(cfg.get_value("update", "installed_version", "")) == version \
			and not bool(cfg.get_value("update", "announced", true)):
		cfg.set_value("update", "announced", true)
		cfg.save(CFG_PATH)
		var notes := str(cfg.get_value("update", "notes", ""))
		notice("Brain Rot updated to %s" % version,
			notes if notes != "" else "The new version is running.")
	if enabled:
		_next_check_ms = Time.get_ticks_msec() + int(FIRST_CHECK_SEC * 1000.0)


## The Auto-update setting changed. Turning it on while a version is waiting installs it now.
func set_auto(on: bool) -> void:
	auto_update = on
	if on and state == "available":
		check_now()


func _process(_delta: float) -> void:
	# real time: the game slows / stops Engine.time_scale
	if _next_check_ms >= 0 and Time.get_ticks_msec() >= _next_check_ms:
		_next_check_ms = Time.get_ticks_msec() + int(RECHECK_SEC * 1000.0)
		check_now()


func check_now() -> void:
	if not enabled:
		return
	if state == "checking" or state == "downloading" or installed != "":
		return
	state = "checking"
	detail = ""
	var r: Dictionary = await _fetch(manifest_url, MAX_MANIFEST, 20.0)
	if r.result != HTTPRequest.RESULT_SUCCESS:
		_finish("offline" if r.offline else "error", r.why)
		return
	if r.code == 404:
		_finish("no_release", "no release published yet")
		return
	if r.code != 200:
		_finish("error", "manifest HTTP %d" % r.code)
		return
	var m = parse_json(r.body.get_string_from_utf8())
	var bad := manifest_error(m)
	if bad != "":
		_finish("error", bad)
		return
	remote = m
	if cmp_version(str(m.version), version) <= 0:
		_finish("current", str(m.version))
		return
	if not auto_update:
		_notice_once("available " + str(m.version), "Brain Rot %s is out" % m.version,
			"Download it from GitHub.")
		_finish("available", str(m.version))
		return
	await _install(m)


func _install(m: Dictionary) -> void:
	var v := str(m.version)
	var err := await _download_and_apply(m)
	_clear_work(false)
	if err != "":
		_notice_once("failed " + v, "Brain Rot update failed",
			"Could not install %s (%s). Download it from GitHub instead." % [v, err], true)
		_finish("error", err)
		return
	installed = v
	cfg.set_value("update", "installed_version", v)
	cfg.set_value("update", "announced", false)
	cfg.set_value("update", "notes", str(m.get("notes", "")).left(200))
	cfg.save(CFG_PATH)
	notice("Brain Rot %s downloaded" % v, "Restart the game to use the new version.")
	_finish("installed", v)


func _download_and_apply(m: Dictionary) -> String:
	var v := str(m.version)
	var url := str(m.url)
	if not url.begins_with(allow_prefix):
		return "download address not allowed: " + url
	state = "downloading"
	var r: Dictionary = await _fetch(url, MAX_ZIP, 90.0)
	if r.result != HTTPRequest.RESULT_SUCCESS:
		return "download failed: " + r.why
	if r.code != 200:
		return "download HTTP %d" % r.code
	var body: PackedByteArray = r.body
	if m.has("size") and int(m.size) != body.size():
		return "size mismatch (%d bytes, manifest %d)" % [body.size(), int(m.size)]
	if sha256_hex(body) != str(m.sha256).to_lower():
		return "checksum mismatch"
	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	var zip_path := WORK_DIR.path_join("BrainRot-%s.zip" % v)
	if not write_bytes(zip_path, body):
		return "cannot write " + zip_path
	var z: Dictionary = read_zip(zip_path, v)
	if z.has("error"):
		return z.error
	var c: String = compile_check(z.files)
	if c != "":
		return c
	return apply(z.files)


## {"result", "code", "body", "why", "offline"} of one GET (redirects followed, size-capped).
func _fetch(url: String, limit: int, timeout_s: float) -> Dictionary:
	var out := {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0,
		"body": PackedByteArray(), "why": "", "offline": true}
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = timeout_s
	http.body_size_limit = limit
	add_child(http)
	var err := http.request(url, PackedStringArray(["User-Agent: BrainRot/" + version]))
	if err == OK:
		var r: Array = await http.request_completed
		out.result = r[0]
		out.code = r[1]
		out.body = r[3]
	else:
		out.why = "request not started (%s)" % error_string(err)
	http.queue_free()
	if out.why == "":
		out.why = _result_text(int(out.result))
	out.offline = int(out.result) in OFFLINE_RESULTS
	return out


static func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS: return ""
		HTTPRequest.RESULT_CANT_CONNECT: return "cannot connect"
		HTTPRequest.RESULT_CANT_RESOLVE: return "no internet (name lookup failed)"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "secure connection failed"
		HTTPRequest.RESULT_NO_RESPONSE: return "no response"
		HTTPRequest.RESULT_TIMEOUT: return "timed out"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "file too large"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "too many redirects"
	return "network error %d" % result


## "" when the manifest is usable, else the reason (pure: unit-tested).
static func manifest_error(m) -> String:
	if not (m is Dictionary):
		return "manifest is not readable"
	if str(m.get("mod", "")) != MOD_ID:
		return "manifest is not for Brain Rot"
	for k in ["version", "url", "sha256"]:
		if not (m.get(k) is String) or str(m[k]) == "":
			return "manifest misses " + k
	if not version_ok(str(m.version)):
		return "manifest version is malformed"
	var sha := str(m.sha256).to_lower()
	if sha.length() != 64 or not sha.is_valid_hex_number():
		return "manifest sha256 is malformed"
	if not (m.url is String) or not str(m.url).begins_with(DOWNLOAD_PREFIX):
		return "manifest url is not a Brain Rot release"
	if m.has("size") and not (m.size is float or m.size is int):
		return "manifest size is malformed"
	return ""


## The update zip's files ({"files": {relative path: bytes}}) or {"error": why}. Only
## BrainRot/ entries at an allowed path, ASCII text or a PNG / OGG, the expected
## version inside.
func read_zip(path: String, want: String) -> Dictionary:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return {"error": "update zip unreadable"}
	var files := {}
	var seen := {}
	var total := 0
	var err := ""
	for entry in z.get_files():
		var n := str(entry).replace("\\", "/")
		if n.ends_with("/"):
			if not ZIP_ROOT.begins_with(n):
				err = "unexpected folder in the zip: " + n
				break
			continue
		if not n.begins_with(ZIP_ROOT):
			err = "file not allowed in the zip: " + n
			break
		var fname := n.trim_prefix(ZIP_ROOT)
		if not path_ok(fname):
			err = "file not allowed in the zip: " + n
			break
		if seen.has(fname.to_lower()):
			err = "duplicate file in the zip: " + n
			break
		seen[fname.to_lower()] = true
		var data := z.read_file(entry)
		total += data.size()
		if total > MAX_UNZIPPED:
			err = "zip contents too large"
			break
		var bad := content_error(fname, data)
		if bad != "":
			err = bad
			break
		files[fname] = data
	z.close()
	if err != "":
		return {"error": err}
	if not files.has("mod_main.gd") or not files.has("mod.json"):
		return {"error": "zip misses mod_main.gd / mod.json"}
	var meta = parse_json(files["mod.json"].get_string_from_ascii())
	if not (meta is Dictionary) or str(meta.get("id", "")) != MOD_ID or str(meta.get("version", "")) != want:
		return {"error": "zip mod.json is not Brain Rot " + want}
	if files["mod_main.gd"].get_string_from_ascii().find('const VERSION := "%s"' % want) < 0:
		return {"error": "zip mod_main.gd is not version " + want}
	return {"files": files}


## Every script of the update loads on this game build (from a fresh staging folder, so nothing is
## served from an earlier attempt's cache and relative preloads resolve); "" = fine.
func compile_check(files: Dictionary) -> String:
	_clear_work(true)
	var stage := WORK_DIR.path_join("stage_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(stage)
	for fname in files:
		var p := stage.path_join(fname)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		if not write_bytes(p, files[fname]):
			return "cannot write " + stage
	for fname in files:
		if str(fname).get_extension().to_lower() == "gd":
			var s = ResourceLoader.load(stage.path_join(fname), "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			if not (s is Script) or not s.can_instantiate():
				return "%s of the update does not load on this game version" % fname
	return ""


## Swaps the new files into the mod's own folder; "" = done.
func apply(files: Dictionary) -> String:
	var dir := os_dir()
	if dir == "" or not FileAccess.file_exists(dir.path_join("mod_main.gd")):
		return "Brain Rot folder not found"
	var own = parse_json(FileAccess.get_file_as_string(dir.path_join("mod.json")))
	if not (own is Dictionary) or str(own.get("id", "")) != MOD_ID:
		return "Brain Rot folder check failed"
	var names: Array = files.keys()
	names.erase("mod_main.gd")
	names.sort()
	names.append("mod_main.gd")  # the entry script goes last
	# the current files, kept to put back if a swap fails half-way (and as a manual fallback)
	var backup := WORK_DIR.path_join("previous")
	remove_tree(backup)
	var old := {}
	for f in current_files(dir):
		old[f] = FileAccess.get_file_as_bytes(dir.path_join(f))
		var bp := backup.path_join(f)
		DirAccess.make_dir_recursive_absolute(bp.get_base_dir())
		write_bytes(bp, old[f])
	for n in names:
		var target := dir.path_join(n)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var tmp := target + ".new"
		if not write_bytes(tmp, files[n]) or FileAccess.get_file_as_bytes(tmp) != files[n]:
			_drop_new(dir, names)
			return "no write access to " + dir
	for i in names.size():
		if not _swap(dir.path_join(names[i] + ".new"), dir.path_join(names[i])):
			for k in i + 1:
				if old.has(names[k]):
					write_bytes(dir.path_join(names[k]), old[names[k]])
				else:
					DirAccess.remove_absolute(dir.path_join(names[k]))
			_drop_new(dir, names)
			return "could not replace " + str(names[i])
	# scripts of older versions the new one no longer has
	for f in current_files(dir):
		if f.get_extension().to_lower() == "gd" and not files.has(f):
			DirAccess.remove_absolute(dir.path_join(f))
	return ""


## Rename, replacing the target (POSIX renames over; some Windows APIs refuse).
static func _swap(tmp: String, target: String) -> bool:
	if DirAccess.rename_absolute(tmp, target) == OK:
		return true
	DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(tmp, target) == OK


## Every file of the mod folder an update may touch, as relative paths with forward slashes.
static func current_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if path_ok(str(f)):
			out.append(str(f))
	for top in TOP_DIRS:
		_collect(dir, str(top), out)
	out.sort()
	return out


static func _collect(dir: String, rel_dir: String, out: Array) -> void:
	var abs := dir.path_join(rel_dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f in DirAccess.get_files_at(abs):
		var rel := rel_dir + "/" + str(f)
		if path_ok(rel):
			out.append(rel)
	for d in DirAccess.get_directories_at(abs):
		_collect(dir, rel_dir + "/" + str(d), out)


## The mod folder as an OS path (Mod Loader installs already are; res:// = next to the game exe).
func os_dir() -> String:
	if mod_dir.begins_with("res://"):
		if OS.has_feature("editor"):
			return ProjectSettings.globalize_path(mod_dir)
		return OS.get_executable_path().get_base_dir().path_join(mod_dir.trim_prefix("res://"))
	if mod_dir.begins_with("user://"):
		return ProjectSettings.globalize_path(mod_dir)
	return mod_dir


## The running copy is the author's working tree (git checkout or test scripts): never touch it.
static func is_dev_install(dir: String) -> bool:
	if dir == "":
		return false
	if DirAccess.dir_exists_absolute(dir.path_join(".git")) or FileAccess.file_exists(dir.path_join(".git")):
		return true
	return FileAccess.file_exists(dir.path_join("dev").path_join("run_tests.ps1"))


## An allowed path inside the mod folder: a top-level .gd/.json/.md, a .gd in audio/ battle/
## catalog/ core/ debug/ hud/ notifications/ reactions/ snapshots/, dev/dev_config.gd, or
## assets/icons/*.png / assets/sounds/*.ogg.
static func path_ok(rel: String) -> bool:
	if not (rel is String) or rel == "" or rel.contains("\\"):
		return false
	var parts := rel.split("/")
	for p in parts:
		if not segment_ok(str(p)):
			return false
	if parts.size() == 1:
		return name_ok(parts[0])
	var top := str(parts[0])
	var ext := str(parts[-1]).get_extension().to_lower()
	if not (top in TOP_DIRS):
		return false
	if top == "dev":
		return parts.size() == 2 and ext == "gd"
	if top == "assets":
		if parts.size() != 3:
			return false
		var sub := str(parts[1])
		return (sub == "icons" and ext == "png") or (sub == "sounds" and ext == "ogg")
	return parts.size() == 2 and ext == "gd"


static func segment_ok(seg: String) -> bool:
	if seg == "" or seg == "." or seg == "..":
		return false
	return RegEx.create_from_string(SEGMENT_PATTERN).search(seg) != null


static func name_ok(fname: String) -> bool:
	if fname == "_agent.md":
		return false
	if RegEx.create_from_string(NAME_PATTERN).search(fname) == null:
		return false
	return fname.get_extension().to_lower() in TEXT_EXT


## "" when the bytes match the entry's extension (ASCII text, or a PNG / OGG signature).
static func content_error(rel: String, data: PackedByteArray) -> String:
	var ext := rel.get_extension().to_lower()
	if ext == "png":
		if data.size() < 8 or data[0] != 0x89 or data[1] != 0x50 or data[2] != 0x4E or data[3] != 0x47:
			return "not a PNG file: " + rel
		return ""
	if ext == "ogg":
		if data.size() < 4 or data[0] != 0x4F or data[1] != 0x67 or data[2] != 0x67 or data[3] != 0x53:
			return "not an OGG file: " + rel
		return ""
	if not is_text(data):
		return "non-text bytes in " + rel
	return ""


static func version_ok(v: String) -> bool:
	return RegEx.create_from_string(VERSION_PATTERN).search(v) != null


## -1 / 0 / 1. Numeric parts compare as numbers; "2.212-dev" sorts below "2.212".
static func cmp_version(a: String, b: String) -> int:
	var pa := _version_parts(a)
	var pb := _version_parts(b)
	var na: Array = pa[0]
	var nb: Array = pb[0]
	for i in maxi(na.size(), nb.size()):
		var x: int = na[i] if i < na.size() else 0
		var y: int = nb[i] if i < nb.size() else 0
		if x != y:
			return -1 if x < y else 1
	var ta: String = pa[1]
	var tb: String = pb[1]
	if ta == tb:
		return 0
	if ta == "":
		return 1
	if tb == "":
		return -1
	return -1 if ta < tb else 1


static func _version_parts(v: String) -> Array:
	var tag := ""
	var dash := v.find("-")
	if dash >= 0:
		tag = v.substr(dash + 1)
		v = v.left(dash)
	var nums: Array = []
	for p in v.strip_edges().split("."):
		nums.append(int(p) if p.is_valid_int() else 0)
	return [nums, tag]


## JSON text -> value, or null (quietly: a bad manifest must not print engine errors into the log).
static func parse_json(text: String):
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


static func sha256_hex(data: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	if not data.is_empty():
		h.update(data)
	return h.finish().hex_encode()


## Printable ASCII plus tab / CR / LF (the mod's scripts are plain text by rule).
static func is_text(data: PackedByteArray) -> bool:
	for b in data:
		if b > 126 or (b < 32 and b != 9 and b != 10 and b != 13):
			return false
	return true


static func write_bytes(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	var ok := f.get_error() == OK
	f.close()
	return ok


static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _drop_new(dir: String, names: Array) -> void:
	for n in names:
		var p := dir.path_join(str(n) + ".new")
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Removes downloaded zips and staging folders (keeps "previous", the last replaced version).
func _clear_work(stages_only: bool) -> void:
	if not DirAccess.dir_exists_absolute(WORK_DIR):
		return
	for d in DirAccess.get_directories_at(WORK_DIR):
		if d.begins_with("stage_"):
			remove_tree(WORK_DIR.path_join(d))
	if not stages_only:
		for f in DirAccess.get_files_at(WORK_DIR):
			if f.get_extension() == "zip":
				DirAccess.remove_absolute(WORK_DIR.path_join(f))


func _finish(s: String, why: String) -> void:
	state = s
	detail = why
	print("Brain Rot update: %s%s" % [s, (" - " + why) if why != "" else ""])
	finished.emit(s)


func _notice_once(key: String, title: String, body: String, urgent := false) -> void:
	if _shown.has(key):
		return
	_shown[key] = true
	notice(title, body, urgent)


## A small, compact notice at the top of the screen (red header = urgent); it fades after a few
## seconds, a click dismisses it.
func notice(title: String, body: String, urgent := false) -> void:
	print("Brain Rot: %s - %s" % [title, body])
	if _layer == null:
		return
	if _toast != null and is_instance_valid(_toast):
		_toast.queue_free()
	var t := Toast.new()
	t.name = "Toast"
	_layer.add_child(t)
	t.setup(title, body, urgent)
	_toast = t


## A plain, self-contained notice: no game or mod UI classes, so it survives a broken overlay.
## Deliberately small (about half the footprint it had at first) so it reads as a corner notice
## instead of covering the HUD; long bodies wrap inside MAX_W rather than widening the box.
class Toast extends Control:
	const FS := 11
	const TITLE_FS := 13
	const HEAD := 15.0
	const PAD := 4.0
	const MIN_W := 150.0
	const MAX_W := 240.0
	const LIFE_MS := 12000
	const FADE_MS := 600

	var title := ""
	var body := ""
	var urgent := false
	var born := 0
	var _font: Font
	var _hfont: Font

	func setup(p_title: String, p_body: String, p_urgent: bool) -> void:
		urgent = p_urgent
		title = p_title
		body = p_body
		born = Time.get_ticks_msec()
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		_font = ThemeDB.fallback_font
		_hfont = ThemeDB.fallback_font
		var one: float = _font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var head: float = _hfont.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FS).x
		var w: float = clampf(maxf(one, head) + PAD * 2 + 4, MIN_W, MAX_W)
		var text_h: float = _font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, w - PAD * 2 - 4, FS).y
		size = Vector2(w, HEAD + PAD + text_h + PAD + 2)
		var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
		position = Vector2(roundf((vp.x - w) * 0.5), 6)

	func _process(_delta: float) -> void:
		var age := Time.get_ticks_msec() - born
		if age > LIFE_MS:
			modulate.a = 1.0 - clampf(float(age - LIFE_MS) / FADE_MS, 0.0, 1.0)
			if age > LIFE_MS + FADE_MS:
				queue_free()

	func _gui_input(event) -> void:
		if event is InputEventMouseButton and event.pressed:
			accept_event()
			queue_free()

	func _draw() -> void:
		var w := size.x
		var tw := w - PAD * 2 - 4
		var tp := Vector2(PAD + 2, HEAD + PAD + FS - 2)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.12, 0.14, 0.94))
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, HEAD)),
			Color(0.85, 0.3, 0.25) if urgent else Color(0.85, 0.65, 0.2))
		draw_string(_hfont, Vector2(0, HEAD - 4), title, HORIZONTAL_ALIGNMENT_CENTER, w, TITLE_FS, Color.WHITE)
		draw_multiline_string(_font, tp, body, HORIZONTAL_ALIGNMENT_LEFT, tw, FS, -1, Color(0.95, 0.95, 0.95))
