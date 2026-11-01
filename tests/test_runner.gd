extends RefCounted
## TestRunner - minimal zero-dependency test harness for Batomon Achievements.
##
## Test files extend this script and define `test_*` methods. run_all() discovers
## and executes them, recording assertion failures. GDScript has no try/catch, so a
## runtime error aborts the run; Godot still exits non-zero, which fails CI.
##
## Usage (from a test file):
##   extends "test_runner.gd"
##   func test_something() -> void:
##       assert_eq(1 + 1, 2)

var _current_test: String = ""
var _failures: Array = []  # Array of {"test": String, "message": String}
var _assertions: int = 0


## Run every `test_*` method on this instance. When `filter` is non-empty, only the
## method whose name matches it exactly runs (used for per-test isolation). Returns
## the number of failures.
func run_all(filter: String = "") -> int:
	var methods: Array = []
	for method in get_method_list():
		var method_name := str(method.get("name", ""))
		if method_name.begins_with("test_") and not methods.has(method_name):
			if filter.is_empty() or method_name == filter:
				methods.append(method_name)
	methods.sort()
	for method_name in methods:
		_current_test = method_name
		call(method_name)
	return _failures.size()


func failure_count() -> int:
	return _failures.size()


func assertion_count() -> int:
	return _assertions


func failures() -> Array:
	return _failures


# --- Assertions ---

func assert_true(value: bool, message: String = "") -> void:
	_assertions += 1
	if not value:
		_fail("expected true" + _suffix(message))


func assert_false(value: bool, message: String = "") -> void:
	_assertions += 1
	if value:
		_fail("expected false" + _suffix(message))


func assert_eq(actual, expected, message: String = "") -> void:
	_assertions += 1
	if actual != expected:
		_fail("expected %s, got %s%s" % [str(expected), str(actual), _suffix(message)])


func assert_ne(actual, unexpected, message: String = "") -> void:
	_assertions += 1
	if actual == unexpected:
		_fail("did not expect %s%s" % [str(unexpected), _suffix(message)])


func assert_empty(value, message: String = "") -> void:
	_assertions += 1
	if not value.is_empty():
		_fail("expected empty, got %s%s" % [str(value), _suffix(message)])


func assert_not_empty(value, message: String = "") -> void:
	_assertions += 1
	if value.is_empty():
		_fail("expected non-empty" + _suffix(message))


func assert_has(container, key, message: String = "") -> void:
	_assertions += 1
	if not container.has(key):
		_fail("expected to contain %s%s" % [str(key), _suffix(message)])


func assert_gt(actual, threshold, message: String = "") -> void:
	_assertions += 1
	if not (actual > threshold):
		_fail("expected > %s, got %s%s" % [str(threshold), str(actual), _suffix(message)])


func _fail(message: String) -> void:
	_failures.append({"test": _current_test, "message": message})


func _suffix(message: String) -> String:
	return "" if message.is_empty() else " (" + message + ")"
