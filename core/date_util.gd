extends RefCounted
## Shared date formatting for the mod's persisted stores.
##
## Both the high-score store and the achievement store record the local date a
## value was first set, so the format lives here instead of being duplicated.

## Current local date as MM/DD/YY (e.g. "11/18/26").
static func current_date_string() -> String:
	var date := Time.get_date_dict_from_system()
	return "%02d/%02d/%02d" % [int(date["month"]), int(date["day"]), int(date["year"]) % 100]
