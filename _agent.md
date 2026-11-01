# AGENTS.md — Brain Rot

## Summary
Brain Rot (`brain_rot`) is a standalone GDScript mod for **Batomon Showdown**. Achievements — detect, persist, and display achievement unlocks — are the first feature; more "fun" features are planned, so keep new code modular rather than achievement-specific where practical.

The achievement system polls the live run and battle state every 500 ms, reads them into plain snapshot Dictionaries (`game_snapshot_reader.gd`), evaluates achievements from those snapshots, writes completion to `achievements.json` at the mod root, and shows a bottom-right toast when the Achievement Notifications setting is enabled. It is self-contained and does not depend on other mods.

Separation of concerns: only `game_snapshot_reader.gd` touches live game objects; the evaluator is rules only; `battle_completion_detector.gd` owns when battle evaluation happens; `debug/state_capture.gd` owns debug dumps; `mod_main.gd` owns initialization, settings, polling, run-transition detection, and coordination.

## Previous Mod
Brain Rot is an offshoot of **Creature Comforts** but is a **separate, standalone mod**. Creature Comforts contains a lot of solid, working code (game-state access, node paths, signals, HUD panels, persistence, test tooling) that should be reused to ease implementation.

- Reference location: `C:\Program Files (x86)\Steam\steamapps\common\Batomon Showdown\Mods\CreatureComforts` — read its `agent.md` first.
- **Reuse, don't depend:** when existing Creature Comforts code does what is needed, copy and adapt it into this repo (keep Brain Rot's own naming/ids). Never reference, load, or require Creature Comforts files or autoloads at runtime; Brain Rot must work with Creature Comforts absent.
- **Reference is read-only:** do not modify anything under the Creature Comforts directory.
- **Prefer proven code:** before writing new inspection or game-API logic, check Creature Comforts for a working equivalent. Its verified identifiers (node paths, properties, signals) may be trusted; do not extrapolate beyond what it demonstrates.
- **Copy only what's needed:** bring over the minimum required for the current feature, not whole files or unrelated systems.
- **Note provenance:** when adapting a non-trivial piece of code, add a brief comment or mention in the summary stating which Creature Comforts file it came from.
- Where this file and Creature Comforts' `agent.md` conflict, this file wins for Brain Rot.

## Preserve Existing Functionality
- Prefer surgical changes over large refactors.
- Do not modify unrelated systems unless necessary.
- Never remove existing functionality without explicitly asking.

## Investigation
- Before modifying code, inspect the relevant existing implementation.
- Do not invent game APIs, node paths, or signal names.
- Do not modify the game's original files.

## Communication Style
- Be concise and direct.
- Assume I am an experienced software developer.
- When changes are complete, summarize what changed, what to test, and any remaining concerns.

## Achievements
- **So I started blasting** - Gentleman owns a level-2 Rhizuka on Day 5 or earlier (`run.current_round`), checked from team + bench.
- **Oh Yeah!** - Twins double-evolution: Beetbud (level 2) -> two level-3 Beetdowns.
- **Herd U Liek Mudkipz** - Twins double-evolution: Frillet (level 2) -> two level-3 Dewlotls.
- **Big Dog, Best Dog** - a single Cinnabark unit generates more than 1,000,000 shield in a single battle, read from `simulation.data.battle_units` (`team_id == 0`, `slot_index`, `shield_granted`) with species resolved through the player run's team slot. Per-unit semantics: shield is not summed across records in the same slot.

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity (`brain_rot`), version, description, and the `achievement_notifications` setting. |
| `mod_main.gd` | Loader lifecycle, settings, 500 ms polling, run-transition detection, coordination of reader/evaluator/store/panel/detector/capture, award persistence, and toast display. |
| `achievements/game_snapshot_reader.gd` | The only place that reads live game objects; produces plain snapshot Dictionaries (run and battle) with absent keys for unknown values. |
| `achievements/achievement_evaluator.gd` | Rules only: `poll(run_snapshot)`, `poll_battle(battle_snapshot)`, `reset_run()`; returns structured achievements without persistence or UI side effects. |
| `achievements/achievement_store.gd` | JSON persistence for completion at the mod root (`achievements.json`); tolerates missing or corrupt files. |
| `achievements/achievement_panel.gd` | Bottom-right achievement toast; auto-hides after ~4 seconds. |
| `achievements/battle_completion_detector.gd` | Owns when battle evaluation happens: `is_pending(state)` (non-consuming) and `consume()` after a usable snapshot exists. |
| `debug/state_capture.gd` | Optional `BRAINROT_DUMP_DIR` debug dump of changed snapshots (signature + counter). |
| `hud/comfort_panel.gd` | Shared dark-navy/gold panel base (palette, font, resize plumbing) used by mod HUD panels, including the toast. |
| `tests/` | Zero-dependency unit tests: `achievement_evaluator`, `achievement_store`, `battle_completion_detector`, `achievements_schema`, `fixture_replay`, `game_snapshot_reader`, `state_capture`. |
| `dev/gd_checks.ps1` | Parse-checks every `.gd` file in the repo with `--check-only`, one Godot process per file; exits non-zero on any failure. |
| `dev/run_tests.ps1` | Runs `tests/run_tests.gd` headless (all suites); exits with the runner's exit code. |
| `dev/run_tests_isolated.ps1` | Runs each test method in its own Godot process so a crash fails only that test. |
| `dev/mutate_tests.ps1` | Mutation harness: injects defects into the evaluator and verifies the suite catches them. |
| `dev/fixtures/` | Curated/captured run and battle snapshots replayed by `test_fixture_replay.gd`. |
| `dev/QUALITY.md` | Test strategy, branch matrix, mutation score, and framework evaluation. |

### Locating the gitignored dev files
`.gitignore` has `dev/*`, so the `dev/` scripts and `dev/QUALITY.md` are **gitignored but
present on disk**. Tools that respect `.gitignore` (including some directory listings)
will not show them, which makes them look missing. They are not missing — read or run
them by path:

- Read them directly, e.g. `dev/QUALITY.md`, `dev/mutate_tests.ps1`.
- List them with a shell that ignores `.gitignore`:
  `cmd /c dir /a "dev"` or `powershell -NoProfile -Command "Get-ChildItem dev -Force"`.
- Run them from the mod root as documented in **Verification** below.
- Do not "restore" or recreate them; if a path truly does not exist, ask before adding it.
- `dev/fixtures/` is un-ignored (`!dev/fixtures/`) because `tests/test_fixture_replay.gd`
  depends on it; keep it tracked. `dev/dev_config.gd` is also un-ignored.
- `_agent.md` and `plans/` are gitignored too, so they are local-only as well.

## Working conventions
- **Versioning:** on every edit, bump the version by `0.0001` in BOTH places: `mod.json` (`version`) and `mod_main.gd` (`const VERSION`). (Note: the on-disk format is four segments, e.g. `0.0.0.4`; bump the last segment.)
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep the evaluator independent of live game objects, file writing, and UI drawing. All live-object reads belong in `game_snapshot_reader.gd`.
- Snapshots use absent keys for unknown values; defaults belong to the rules, not the reader.
- Battle evaluation timing belongs to `battle_completion_detector.gd`; the evaluator's `poll_battle` is a pure rule check.
- Persistence must not depend on the panel existing or notifications being enabled.
- Call `reset_run()` at verified run transitions (inferred in `mod_main` from run identity, trainer, and day regression).
- The toast is gated by the Achievement Notifications setting.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Tests must stay deterministic: inject `TestHelpers.TestClock` instead of relying on wall-clock time.
- When adding an achievement, add it to `test_achievement_ids_unique_and_well_formed` and the branch matrix in `dev/QUALITY.md`.
- Keep `tests/fixtures/` and `dev/fixtures/` in sync with the fields the evaluator reads.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.

## Verification (required before reporting a change complete)

The check scripts live in `dev/` and already point at the Godot console binary
(`C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe`). Run them from the mod root
(`.../Batomon Showdown/Mods/BrainRot`):

```powershell
# 1. Parse-check every .gd file (mod_main.gd, achievements/, hud/, tests/, ...)
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\gd_checks.ps1

# 2. Run the headless unit-test suite (all 7 suites)
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\run_tests.ps1
```

- Use these scripts — do not hand-roll `godot --headless ...` commands. They are the
  canonical checks and behave identically for every contributor.
- Both accept `-Root <path>` (defaults to the current directory) and `-Godot <exe>`
  (defaults to the path above). Pass `-Godot` only if the binary moves.
- Do not report a change as complete unless both scripts exit `0`. Quote the suite and
  assertion counts from `run_tests.ps1` output, and say plainly that gameplay
  verification is still pending when it is.
- If evaluator rules changed, also run `dev\run_tests_isolated.ps1` and
  `dev\mutate_tests.ps1`; add tests for any surviving mutation.
- Expected noise: `run_tests.ps1` prints a `Parse JSON failed` error and a
  `Brain Rot: invalid achievements JSON` warning — that is the corrupt-file test
  exercising [`achievements/achievement_store.gd`](achievements/achievement_store.gd).
  Exit code `0` with `0 failures` is a pass.

## Game Source Code

- Do not attempt to locate, extract, or decompile Batomon Showdown's original source code. The game's Godot PCK is encrypted, and attempting to access it wastes time and tokens.
- Instead, investigate game behavior using existing mod code, runtime inspection, Godot's scene tree, object properties, signals, and targeted debug logging.
- Prefer existing discoveries and utilities in this repository before implementing new inspection logic.

