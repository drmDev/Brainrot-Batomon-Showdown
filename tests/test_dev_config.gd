extends "test_runner.gd"
## Unit tests for dev/dev_config.gd (developer-mode gate).

const DevConfig = preload("../dev/dev_config.gd")


func test_env_override_enables_dev_mode() -> void:
	var previous := OS.get_environment(DevConfig.DEV_MODE_ENV_VAR)
	for value in ["1", "true", "YES", "on"]:
		OS.set_environment(DevConfig.DEV_MODE_ENV_VAR, value)
		assert_true(DevConfig.is_enabled(), "expected dev mode for " + value)
	OS.set_environment(DevConfig.DEV_MODE_ENV_VAR, previous)


func test_unset_or_off_env_falls_back_to_constant() -> void:
	var previous := OS.get_environment(DevConfig.DEV_MODE_ENV_VAR)
	for value in ["", "0", "false", "off"]:
		OS.set_environment(DevConfig.DEV_MODE_ENV_VAR, value)
		assert_eq(DevConfig.is_enabled(), DevConfig.DEV_MODE, "unexpected dev mode for " + value)
	OS.set_environment(DevConfig.DEV_MODE_ENV_VAR, previous)
