## Dev-only switches for Brain Rot.
##
## These are NOT user-facing settings and are intentionally absent from mod.json.
## The shipped default is off; developers flip DEV_MODE locally, or set the
## environment variable, to show tools such as the toast preview.

extends RefCounted

const DEV_MODE := false
const DEV_MODE_ENV_VAR := "BRAINROT_DEV_MODE"


## Is developer mode enabled? The constant wins; otherwise the environment
## variable accepts 1/true/yes/on (case-insensitive).
static func is_enabled() -> bool:
	if DEV_MODE:
		return true
	var value := OS.get_environment(DEV_MODE_ENV_VAR).strip_edges().to_lower()
	return value == "1" or value == "true" or value == "yes" or value == "on"
