extends RefCounted
## ReactionEvaluator - detects "reactions" from game snapshots.
##
## Rules only: consumes the plain run snapshot produced by
## achievements/game_snapshot_reader.gd and returns newly triggered reaction
## dictionaries. It never touches live game objects, files, UI, or the achievement
## store, so a completed achievement can never suppress a reaction.
##
##   poll(run_snapshot) -> Array of {"id": String, "detail": String}
##   reset_run()        -> clear occurrence tracking for a new run
##
## Occurrence semantics:
## - A reaction triggers once per run, the first time a matching snapshot is seen.
## - Repeated matching polls do not retrigger.
## - Leaving the condition and returning during the same run does not retrigger.
## - Only reset_run() clears tracking (called at a verified run transition).
## - An empty snapshot (run unavailable) does NOT reset, so a menu round-trip cannot
##   re-arm a reaction.
##
## LIMITATION: occurrence tracking is session-only. Restarting the game or the mod
## can allow a reaction to trigger again within a continuing run. Persisting
## occurrences is deliberately out of scope for now.
##
## Reactions:
## - "six_seven"
##   Condition: remaining Lives == 6 AND committed cumulative Wins == 7.
##   A run starts with 10 lives, so this is 4 lives lost and 7 wins.
##   Fields: run.lives and run.current_wins (RunManager.data), read from the same
##   snapshot so both values come from one poll. Missing, null, or non-numeric
##   values never match.

const SIX_SEVEN_ID := "six_seven"
const SIX_SEVEN_LIVES := 6
const SIX_SEVEN_WINS := 7

## Reaction table: same rule shape, one row per reaction. Add rows here rather than
## new classes; the condition code stays in _matches().
const REACTIONS := [
	{"id": SIX_SEVEN_ID, "lives": SIX_SEVEN_LIVES, "wins": SIX_SEVEN_WINS},
]

# Occurrence count per reaction id for the current run. Presence means "already
# triggered this run"; the count is kept for diagnostics and tests.
var _occurrences: Dictionary = {}


## Poll a run snapshot. Returns newly triggered reaction dictionaries (empty most polls).
func poll(run_snapshot: Dictionary) -> Array:
	var triggered: Array = []
	if run_snapshot.is_empty():
		return triggered

	for reaction in REACTIONS:
		var id := str(reaction.get("id", ""))
		if id.is_empty() or _occurrences.has(id):
			continue
		if not _matches(reaction, run_snapshot):
			continue
		_occurrences[id] = int(_occurrences.get(id, 0)) + 1
		triggered.append({
			"id": id,
			"detail": "Lives %d, Wins %d" % [
				int(run_snapshot.get("lives")),
				int(run_snapshot.get("current_wins")),
			],
		})
	return triggered


## Clear occurrence tracking. Call at a verified run transition.
func reset_run() -> void:
	_occurrences.clear()


## How many times this reaction has triggered in the current run (0 or 1 today).
func occurrence_count(id: String) -> int:
	return int(_occurrences.get(id, 0))


## Does the snapshot satisfy this reaction's condition? Both fields must be present
## integers; anything else (absent, null, string, bool) does not match.
func _matches(reaction: Dictionary, run_snapshot: Dictionary) -> bool:
	var lives = run_snapshot.get("lives")
	var wins = run_snapshot.get("current_wins")
	if typeof(lives) != TYPE_INT or typeof(wins) != TYPE_INT:
		return false
	return int(lives) == int(reaction.get("lives")) and int(wins) == int(reaction.get("wins"))
