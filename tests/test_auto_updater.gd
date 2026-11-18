extends "test_runner.gd"
## Unit tests for core/auto_updater.gd (GitHub self-updater).
##
## Only the pure/static parts and the filesystem swap are exercised here: the network paths are
## covered by the release walkthrough in plans/auto_update.md.

const AutoUpdater = preload("../core/auto_updater.gd")

const TMP_DIR := "user://brain_rot_test"

var _updater = null


func _updater_node():
	if _updater == null:
		_updater = AutoUpdater.new()
	return _updater


func _manifest() -> Dictionary:
	return {
		"mod": "brain_rot",
		"version": "0.0.0.44",
		"url": AutoUpdater.DOWNLOAD_PREFIX + "v0.0.0.44/BrainRot-0.0.0.44.zip",
		"sha256": "a".repeat(64),
		"size": 10,
		"notes": "one line",
	}


func test_cmp_version() -> void:
	assert_eq(AutoUpdater.cmp_version("2.212", "2.211"), 1)
	assert_eq(AutoUpdater.cmp_version("2.211", "2.212"), -1)
	assert_eq(AutoUpdater.cmp_version("2.211", "2.211"), 0)
	assert_eq(AutoUpdater.cmp_version("2.9", "2.10"), -1, "numeric, not lexicographic")
	assert_eq(AutoUpdater.cmp_version("3.0", "2.999"), 1)
	assert_eq(AutoUpdater.cmp_version("2.212", "2.212.0"), 0, "missing parts are zero")
	assert_eq(AutoUpdater.cmp_version("2.212-dev", "2.212"), -1, "pre-release sorts below release")
	assert_eq(AutoUpdater.cmp_version("2.212-beta", "2.212-alpha"), 1, "tags compare as text")
	assert_eq(AutoUpdater.cmp_version("2.212-beta", "2.212"), -1)


func test_version_ok() -> void:
	assert_true(AutoUpdater.version_ok("2.211"))
	assert_true(AutoUpdater.version_ok("1.2.3.4"))
	assert_true(AutoUpdater.version_ok("2.212-beta.1"))
	assert_false(AutoUpdater.version_ok(""))
	assert_false(AutoUpdater.version_ok("v2.211"))
	assert_false(AutoUpdater.version_ok("2."))


func test_zip_root_is_the_mod_folder() -> void:
	# The release zip is extracted into Mods/, so its top level is BrainRot/ - never
	# Mods/BrainRot/ (that would nest the mod one folder too deep).
	assert_eq(AutoUpdater.ZIP_ROOT, "BrainRot/")


func test_path_ok_allows_mod_layout() -> void:
	for ok in [
		"mod_main.gd", "mod.json", "README.md",
		"audio/ui_sound.gd", "battle/high_scores.gd", "catalog/brain_rot_catalog.gd",
		"core/auto_updater.gd", "debug/state_capture.gd", "hud/toast_view.gd",
		"notifications/notification_host.gd", "reactions/reaction_player.gd",
		"snapshots/game_snapshot_reader.gd", "dev/dev_config.gd",
		"assets/icons/rainbowBrain.png", "assets/sounds/ff_fanfare.ogg",
	]:
		assert_true(AutoUpdater.path_ok(ok), "should allow %s" % ok)


func test_path_ok_rejects_everything_else() -> void:
	for bad in [
		"",
		"../evil.gd",
		"core/../../evil.gd",
		"core/./auto_updater.gd",
		"/abs/path.gd",
		"core\\auto_updater.gd",
		"tests/test_auto_updater.gd",
		"dev/run_tests.ps1",
		"dev/gd_checks.ps1",
		"assets/icons/rainbowBrain.ogg",
		"assets/sounds/ff_fanfare.png",
		"assets/other/file.png",
		"assets/icons/nested/file.png",
		"audio/nested/file.gd",
		"mod_main.exe",
		"_agent.md",
		"plans/auto_update.md",
		"audio/a b.gd",
	]:
		assert_false(AutoUpdater.path_ok(bad), "should reject %s" % bad)


func test_name_ok() -> void:
	assert_true(AutoUpdater.name_ok("mod_main.gd"))
	assert_true(AutoUpdater.name_ok("README.md"))
	assert_false(AutoUpdater.name_ok("mod_main.gd.new"))
	assert_false(AutoUpdater.name_ok("icon.png"))
	assert_false(AutoUpdater.name_ok("a b.gd"))
	assert_false(AutoUpdater.name_ok("_agent.md"))


func test_is_text() -> void:
	assert_true(AutoUpdater.is_text("plain ascii\r\n\tindent".to_utf8_buffer()))
	assert_true(AutoUpdater.is_text(PackedByteArray()))
	assert_false(AutoUpdater.is_text(PackedByteArray([0x00])), "binary NUL")
	assert_false(AutoUpdater.is_text("\u2014".to_utf8_buffer()), "UTF-8 em dash bytes")
	assert_false(AutoUpdater.is_text(PackedByteArray([0x7F])), "DEL")


func test_content_error_signatures() -> void:
	var png := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
	var ogg := PackedByteArray([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02])
	assert_eq(AutoUpdater.content_error("assets/icons/a.png", png), "")
	assert_eq(AutoUpdater.content_error("assets/sounds/a.ogg", ogg), "")
	assert_ne(AutoUpdater.content_error("assets/icons/a.png", ogg), "", "ogg content named .png")
	assert_ne(AutoUpdater.content_error("assets/sounds/a.ogg", png), "", "png content named .ogg")
	assert_ne(AutoUpdater.content_error("assets/icons/a.png", PackedByteArray()), "")
	assert_eq(AutoUpdater.content_error("core/a.gd", "extends Node\n".to_utf8_buffer()), "")
	assert_ne(AutoUpdater.content_error("core/a.gd", PackedByteArray([0xC3, 0xA9])), "")


func test_sha256_hex() -> void:
	assert_eq(AutoUpdater.sha256_hex("abc".to_utf8_buffer()),
		"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	assert_eq(AutoUpdater.sha256_hex(PackedByteArray()),
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")


func test_manifest_error_accepts_good_manifest() -> void:
	assert_eq(AutoUpdater.manifest_error(_manifest()), "")


func test_manifest_error_rejects_bad_manifests() -> void:
	assert_ne(AutoUpdater.manifest_error(null), "")
	assert_ne(AutoUpdater.manifest_error("text"), "")

	var other_mod := _manifest()
	other_mod["mod"] = "batoeyes"
	assert_ne(AutoUpdater.manifest_error(other_mod), "")

	var missing_url := _manifest()
	missing_url.erase("url")
	assert_ne(AutoUpdater.manifest_error(missing_url), "")

	var bad_version := _manifest()
	bad_version["version"] = "0.0.0.x"
	assert_ne(AutoUpdater.manifest_error(bad_version), "")

	var short_sha := _manifest()
	short_sha["sha256"] = "abc"
	assert_ne(AutoUpdater.manifest_error(short_sha), "")

	var non_hex := _manifest()
	non_hex["sha256"] = "z".repeat(64)
	assert_ne(AutoUpdater.manifest_error(non_hex), "")

	var foreign_url := _manifest()
	foreign_url["url"] = "https://github.com/someone/Else/releases/download/v1/x.zip"
	assert_ne(AutoUpdater.manifest_error(foreign_url), "")

	var bad_size := _manifest()
	bad_size["size"] = "big"
	assert_ne(AutoUpdater.manifest_error(bad_size), "")


func test_apply_writes_swaps_and_prunes() -> void:
	var dir := ProjectSettings.globalize_path(TMP_DIR)
	AutoUpdater.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("hud"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("audio"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("tests"))
	_write(dir.path_join("mod.json"), '{"id": "brain_rot"}')
	_write(dir.path_join("mod_main.gd"), "const VERSION := \"0.0.0.44\"\n")
	_write(dir.path_join("hud/keep.gd"), "old\n")
	_write(dir.path_join("hud/stale.gd"), "stale\n")
	_write(dir.path_join("tests/test_old.gd"), "test\n")

	var u = _updater_node()
	u.mod_dir = dir
	var files := {
		"mod.json": '{"id": "brain_rot", "version": "0.0.0.44"}'.to_utf8_buffer(),
		"mod_main.gd": "const VERSION := \"0.0.0.44\"\n".to_utf8_buffer(),
		"hud/keep.gd": "new\n".to_utf8_buffer(),
		"audio/added.gd": "added\n".to_utf8_buffer(),
	}
	var err: String = u.apply(files)
	_release_node()

	assert_eq(err, "")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("hud/keep.gd")), "new\n")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("audio/added.gd")), "added\n")
	assert_false(FileAccess.file_exists(dir.path_join("hud/stale.gd")), "stale script pruned")
	assert_true(FileAccess.file_exists(dir.path_join("tests/test_old.gd")), "tests never pruned")
	assert_false(FileAccess.file_exists(dir.path_join("hud/keep.gd.new")), "no temp files left")
	assert_false(FileAccess.file_exists(dir.path_join("mod_main.gd.new")), "no temp files left")
	var backup := ProjectSettings.globalize_path(AutoUpdater.WORK_DIR).path_join("previous")
	assert_eq(FileAccess.get_file_as_string(backup.path_join("hud/keep.gd")), "old\n")

	AutoUpdater.remove_tree(dir)


func test_apply_refuses_a_folder_without_our_manifest() -> void:
	var dir := ProjectSettings.globalize_path(TMP_DIR)
	AutoUpdater.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("mod.json"), '{"id": "something_else"}')
	var u = _updater_node()
	u.mod_dir = dir
	var err: String = u.apply({"mod_main.gd": "x".to_utf8_buffer()})
	_release_node()
	assert_ne(err, "")
	assert_false(FileAccess.file_exists(dir.path_join("mod_main.gd")), "nothing written")
	AutoUpdater.remove_tree(dir)


func test_is_dev_install_ignores_a_missing_folder() -> void:
	assert_false(AutoUpdater.is_dev_install(""))
	assert_false(AutoUpdater.is_dev_install(ProjectSettings.globalize_path("user://no_such_mod")))


func test_current_files_skips_tests_and_docs() -> void:
	# Read-only look at this repository: only the shipped, update-managed files are listed.
	var dir := ProjectSettings.globalize_path("res://")
	var files: Array = AutoUpdater.current_files(dir)
	assert_true(files.has("mod_main.gd"))
	assert_true(files.has("mod.json"))
	assert_true(files.has("core/auto_updater.gd"))
	assert_true(files.has("dev/dev_config.gd"))
	assert_false(files.has("dev/run_tests.ps1"))
	assert_false(files.has("_agent.md"))
	assert_false(files.has("plans/auto_update.md"))
	for f in files:
		assert_false(str(f).begins_with("tests/"), "tests are not managed: %s" % f)


func _release_node() -> void:
	if _updater != null:
		_updater.free()
		_updater = null


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
