# AGENTS.md — Batomon Achievements

## Summary
Batomon Achievements (`batomon_achievements`) is a standalone GDScript mod for **Batomon Showdown** that detects, persists, and displays achievement unlocks. It polls the live run and battle state every 500 ms, evaluates achievements, writes completion to `achievements.json` at the mod root, and shows a bottom-right toast when the Achievement Notifications setting is enabled. It is self-contained and does not depend on Creature Comforts.

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

## Scope Discipline
Implement only what was requested. Do not add speculative features, extra configuration, new dependencies, or unrelated refactors.

## Achievements
- **So I started blasting** — Gentleman owns a level-2 Rhizuka on Day 5 or earlier (`run.current_round`), checked from team + bench.
- **Oh Yeah!** — Twins double-evolution: Beetbud (level 2) → two level-3 Beetdowns.
- **Herd U Liek Mudkipz** — Twins double-evolution: Frillet (level 2) → two level-3 Dewlotls.
- **Big Dog, Best Dog** — a Cinnabark unit generates more than 1,000,000 shield in a single battle, read from `simulation.data.battle_units` (`team_id == 0`, `slot_index`, `shield_granted`) with species resolved through the player run's team slot.

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity, version, description, and the `achievement_notifications` setting. |
| `mod_main.gd` | Loader lifecycle, settings, 500 ms polling, run/battle achievement evaluation, award persistence, and toast display. |
| `achievements/achievement_evaluator.gd` | Poll-based achievement detection (`poll(run)` and `poll_battle(state, run)`); returns structured achievements without persistence or UI side effects. |
| `achievements/achievement_store.gd` | JSON persistence for completion at the mod root (`achievements.json`); tolerates missing or corrupt files. |
| `achievements/achievement_panel.gd` | Bottom-right achievement toast; auto-hides after ~4 seconds. |
| `achievements/battle_completion_detector.gd` | Reports each battle's completion exactly once via `simulation.data.battle_over`. |
| `hud/comfort_panel.gd` | Shared dark-navy/gold panel base (palette, font, resize plumbing) used by the toast. |
| `tests/` | Zero-dependency unit tests: `achievement_evaluator`, `achievement_store`, `battle_completion_detector`, `achievements_schema`, `fixture_replay`. |
| `dev/gd_checks.ps1` | Runs Godot checks across mod scripts. |
| `dev/run_tests.ps1` | Runs the headless unit-test suite (all suites). |
| `dev/run_tests_isolated.ps1` | Runs each test method in its own Godot process so a crash fails only that test. |
| `dev/mutate_tests.ps1` | Mutation harness: injects defects into the evaluator and verifies the suite catches them. |
| `dev/fixtures/` | Curated/captured run and battle snapshots replayed by `test_fixture_replay.gd`. |
| `dev/QUALITY.md` | Test strategy, branch matrix, mutation score, and framework evaluation. |

## Working conventions
- **Versioning:** on every edit, bump the version by `0.0001` in BOTH places: `mod.json` (`version`) and `mod_main.gd` (`const VERSION`).
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep the evaluator independent of live game objects, file writing, and UI drawing.
- The toast is gated by the Achievement Notifications setting.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Run GDScript checks on every changed helper as well as the main script.
- Run `dev/run_tests.ps1` after changing the achievement evaluator.
- After changing evaluator rules, run `dev/mutate_tests.ps1` and add tests for any surviving mutation.
- Tests must stay deterministic: inject `TestHelpers.TestClock` instead of relying on wall-clock time.
- When adding an achievement, add it to `test_achievement_ids_unique_and_well_formed` and the branch matrix in `dev/QUALITY.md`.
- Keep `tests/test_fixtures`/`dev/fixtures` in sync with the fields the evaluator reads.
- The user performs gameplay tests; report actual checks separately from pending runtime validation.


## Game Source Code

- Do not attempt to locate, extract, or decompile Batomon Showdown's original source code. The game's Godot PCK is encrypted, and attempting to access it wastes time and tokens.
- Instead, investigate game behavior using existing mod code, runtime inspection, Godot's scene tree, object properties, signals, and targeted debug logging.
- Prefer existing discoveries and utilities in this repository before implementing new inspection logic.

