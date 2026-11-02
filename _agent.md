# AGENTS.md — Brain Rot

## Summary
Brain Rot (`brain_rot`) is a standalone GDScript mod for **Batomon Showdown**. Achievements — detect, persist, and display achievement unlocks — are the first feature; more "fun" features are planned, so keep new code modular rather than achievement-specific where practical.

The achievement system polls the live run and battle state every 500 ms, reads them into plain snapshot Dictionaries (`game_snapshot_reader.gd`), evaluates achievements from those snapshots, writes completion to `achievements.json` at the mod root, and shows a bottom-right toast. It is self-contained and does not depend on other mods.

Separation of concerns: only `game_snapshot_reader.gd` touches live game objects; the evaluator is rules only; `battle_completion_detector.gd` owns when battle evaluation happens; `debug/state_capture.gd` owns debug dumps; `mod_main.gd` owns initialization, polling, run-transition detection, and coordination.

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

## Logging
Logging mirrors Creature Comforts (same helpers, different path). `mod_main.gd` keeps one append handle open for the session and writes to:

```
user://brain_rot/inspect.log
```

On Windows that is `%APPDATA%\Godot\app_userdata\Batomon Showdown\brain_rot\inspect.log`.

- `_print_notice(message)` - console **and** file, no prefix. Used for user-visible events (`loaded`, `EARNED`, `REACTION`, `run reset`).
- `_log_event(message)` - file only, `[HH:MM:SS] ` prefix. Used for diagnostics (`RUN PROGRESS`, `BATTLE PHASE`, `BATTLE COMPLETE`, `BATTLE UNIT`, `REACTION BATTLE`).
- Battle diagnostics: `BATTLE PHASE` (once per battle: sim/data/battle_over/unit count/replay run present), `BATTLE COMPLETE` (snapshot usability and field counts), `BATTLE UNIT` (one line per player unit with dmg/heal/shield/burn/poison/shock), `REACTION BATTLE` (how many battle reactions fired).
- `_log_message(message)` - raw file line (startup banner).
- The file is created if missing and appended to; it is never truncated by the mod. Delete it before launching for a clean session.
- If the file cannot be opened, logging no-ops and the mod still runs.

Watch it live:

```powershell
$log = "$env:APPDATA\Godot\app_userdata\Batomon Showdown\brain_rot\inspect.log"
Get-Content $log -Wait -Tail 50
```

## Reactions
Reactions are snapshot-driven conditions that log to the console. They are independent of achievements: no store, no panel, no completion flags.

**Shop layout and income.** The shop shows `[Lives, Day, Wins]`, mapping to `run.lives`, `run.current_round` (Day), and `run.current_wins`. Shop income is derived, not current gold: `35 + 5 * (Day - 1) + sum(_active_passives[].gold_gain)`, matching Creature Comforts' `_compute_daily_income`. `game_snapshot_reader.gd` emits it as the snapshot's `income` field whenever Day is known.

- **six_seven** triggers on any of:
  - **Run layout:** Lives == 6 AND (Day == 7 OR Wins == 7).
  - **Income:** derived shop income == 67.
  - **Battle:** any player-side unit's **final** battle total is exactly 67 on damage, heal, shield, burn, poison, or shock. Evaluated only at `battle_over`, never mid-fight. Logs `Brain Rot: REACTION | six_seven | slot <n> <species> <metric> 67`.
  - Run details are built from whichever triggers matched (`Lives 6, Day 7`, `Lives 6, Wins 7`, `Income 67`, or comma-joined when several match).
- **six_nine** is the same shape for Day 9 / Wins 9 / income 69, plus battle total 69. Title: `6 9`.
- **four_twenty** (420) and **six_six_six** (666): income equals the value (run-scoped) OR any player-side unit's **final** battle total equals the value on damage, heal, shield, burn, poison, or shock. Battle timing, lowest-slot, and first-metric rules match six_seven. Logs `Income 420` / `Income 666` or the battle detail.
- **over_9000**: income is **strictly greater than 9000** (run-scoped) OR any player-side unit's **final** battle total is **strictly greater than 9000** on **burn, poison, or shock only**. 9000 itself does not fire; 9001 does. The log reports the **actual total**, not the threshold. It also plays `assets/sounds/over-9000.ogg`.
- **flawless_victory**: at `battle_over`, the **committed** post-battle run has **Wins == 10** and **Lives == 10**. Reads the battle snapshot's `outcome` (the promoted `RunManager.data` run, guarded by run identity + pending state), NOT the pre-battle replay copy. Fires once per run; `reset_battle()` does not re-arm it. Plays `assets/sounds/ff_fanfare.ogg`. Title: `Flawless Victory`.
- During battle the player's run is read from `battle_state._replay_p1_data` (verified in MyBattleStats/BatoEyes and BatomonHelperBridge), falling back to `RunManager.data`, which may already be the promoted/completed run.
- Run-scoped reactions trigger once per run, on the first matching snapshot. Repeated polls, leaving and returning, and a menu round-trip (run unavailable) do not retrigger. Only a verified run transition calls `reset_run()`.
- Battle reactions fire at most **once per battle per reaction id**, even when several units qualify: the lowest slot wins, and within that slot the first metric in `BATTLE_METRICS` order (damage, heal, shield, burn, poison, shock). `reset_battle()` runs when a new battle starts. They are checked once, on the completed battle's final totals, so mid-fight values never match.
- Run rows live in `REACTIONS` and may carry `lives` with `day`/`wins` (layout) and/or `income` plus optional `income_comparison`. Battle rows live in `BATTLE_REACTIONS`: `{"id", "value"}` for exact matches, plus optional `"comparison": "gt"` and `"metrics": [keys]`. Adding a value reaction is one row plus an id const. `tests/test_reaction_evaluator.gd` mirrors the exact-value rows in `BATTLE_CASES`, so every battle test runs the full matrix for each value; threshold reactions have their own block.
- **Limitation:** occurrence tracking is session-only. Restarting the game or the mod can allow a reaction again within a continuing run.
- **Unverified field mappings:** `lives` is the displayed remaining-lives counter and starts at 10, and when `lives`/`current_wins` are committed relative to each other, are inferred from Creature Comforts usage, not the game's own UI. With `BRAINROT_DUMP_DIR` set, `mod_main` logs `RUN PROGRESS | Day N, Lives L, Wins W` on every change to verify them.
- `reaction_player.gd` logs (console and `inspect.log`), submits a toast through the shared notification host, and forwards the reaction id to an optional sound sink.
- Reaction audio is table-driven in `audio/reaction_sounds.gd` (`REACTION_SOUNDS`). Adding a sound is one row plus the OGG in `assets/sounds/`; `mod_main` and the dev preview both call `play_for(id)`, so they cannot drift.
- The dev toast preview calls the same sound mapping, so previewing a sound reaction plays it too.

## UI Sizing and Theme Overrides
Godot's default control theme is sized for menus, not the mod's compact toast/HUD
scale. Native `Label`, `Button`, and `OptionButton` controls render with large
fonts, padding, and popup rows unless every control is overridden explicitly.
This bit the dev toast preview: without overrides, the dropdown popup and button
labels were several times larger than the surrounding toast UI.

Rules for compact HUD/tool UI:

- Set the font and size on every control, not just its parent:
  `add_theme_font_override("font", font)` and
  `add_theme_font_size_override("font_size", size)` (build the font with
  `hud/styles.gd`'s `make_font()`).
- `OptionButton`'s dropdown is a separate `PopupMenu`, so override it too:
  `var popup := option.get_popup()`, then set `font`, `font_size`, and optionally
  `v_separation` to `0`. Skipping this leaves dropdown rows at Godot's default
  large size even when the button face itself is small.
- Godot's default button stylebox content margins dominate a tiny font. Override
  `normal`, `hover`, `pressed`, `focus`, and `disabled` with
  `Styles.make_compact_button_style()` (navy/gold chrome, 1 px content margin)
  and set a matching `custom_minimum_size.y`.
- Size the surrounding panel explicitly and halve its padding/gaps in step with
  the text (`MarginContainer` margins, `VBoxContainer` separation). Otherwise
  default spacing keeps the panel oversized after the fonts shrink.
- Place viewport-relative controls with anchors rather than fixed offsets. The
  preview button sets `anchor_top = anchor_bottom = 0.20` so it stays 20% down
  the viewport at any resolution.
- Keep these controls presentation-only. `hud/toast_preview_panel.gd` forwards
  the selected catalog entry to `mod_main._preview_toast()` and never touches
  achievement progress, saves, or game state.

This is the Brain Rot adaptation of Creature Comforts' HUD sizing approach
(`hud/comfort_panel.gd` `_build_hud_box()` and `hud/watchlist_panel.gd`
`_apply_font()` plus its `OptionButton` popup overrides).

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity (`brain_rot`), version, and description. |
| `mod_main.gd` | Loader lifecycle, session log (`user://brain_rot/inspect.log`), 500 ms polling, run-transition detection, coordination of reader/evaluator/store/detector/capture, award persistence, and toast display. |
| `achievements/game_snapshot_reader.gd` | The only place that reads live game objects; produces plain snapshot Dictionaries (run and battle, including derived shop `income`) with absent keys for unknown values. |
| `achievements/achievement_evaluator.gd` | Rules only: `poll(run_snapshot)`, `poll_battle(battle_snapshot)`, `reset_run()`; returns structured achievements without persistence or UI side effects. |
| `achievements/achievement_store.gd` | JSON persistence for completion at the mod root (`achievements.json`); tolerates missing or corrupt files. |
| `hud/toast_view.gd` | Bottom-right toast view; the notification host owns placement and timing. |
| `hud/styles.gd` | Shared palette, font, panel chrome, compact-button chrome, and toast layout metrics. |
| `hud/toast_preview_panel.gd` | Dev-only preview button/panel: compact dropdown of registered toasts, Play, and Close. |
| `notifications/toast_catalog.gd` | Builds preview entries from the achievement/reaction registries and duplicate-allowed requests. |
| `audio/ui_sound.gd` | Lazy one-shot OGG player adapted from Creature Comforts, with optional per-sound volume. |
| `audio/reaction_sounds.gd` | Table-driven reaction audio (`REACTION_SOUNDS`); one row per reaction, lazy per-file players. |
| `achievements/battle_completion_detector.gd` | Owns when battle evaluation happens: `is_pending(state)` (non-consuming) and `consume()` after a usable snapshot exists. |
| `reactions/reaction_evaluator.gd` | Rules only: `poll(run_snapshot)` and `poll_battle(battle_snapshot)` return newly triggered reactions; `reset_run()` / `reset_battle()` clear occurrence tracking. No store, UI, or live objects. |
| `reactions/reaction_player.gd` | Plays a reaction: logs `Brain Rot: REACTION \| <id> \| <detail>` to console and `inspect.log`, submits a toast, and forwards the id to the sound sink. |
| `debug/state_capture.gd` | Optional `BRAINROT_DUMP_DIR` debug dump of changed snapshots (signature + counter). |
| `tests/` | Zero-dependency unit tests: `achievement_evaluator`, `achievement_store`, `battle_completion_detector`, `achievements_schema`, `fixture_replay`, `game_snapshot_reader`, `state_capture`, `reaction_evaluator`, `reaction_player`, `toast_catalog`, `toast_preview_panel`, `dev_config`, `mod_main_preview`, `reaction_sounds`, `ui_sound`. |
| `dev/dev_config.gd` | Developer-mode gate (`DEV_MODE` constant or `BRAINROT_DEV_MODE`); not a user-facing setting. |
| `dev/gd_checks.ps1` | Parse-checks every `.gd` file in the repo with `--check-only`, one Godot process per file; exits non-zero on any failure. |
| `dev/run_tests.ps1` | Runs `tests/run_tests.gd` headless (all suites in one Godot process); exits with the runner's exit code. |
| `dev/fixtures/` | Curated/captured run and battle snapshots replayed by `test_fixture_replay.gd`. |
| `dev/QUALITY.md` | Test strategy, branch matrix, and framework evaluation. |

### Locating the gitignored dev files
`.gitignore` has `dev/*`, so the `dev/` scripts and `dev/QUALITY.md` are **gitignored but
present on disk**. Tools that respect `.gitignore` (including some directory listings)
will not show them, which makes them look missing. They are not missing — read or run
them by path:

- Read them directly, e.g. `dev/QUALITY.md`, `dev/run_tests.ps1`.
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
- Persistence must not depend on the toast host existing.
- Call `reset_run()` at verified run transitions (inferred in `mod_main` from `run_id`, then run object instance, trainer, and day regression). `run_id` is the primary identity: the game promotes `RunManager.data` to a new RunData object when a battle starts, so instance comparison alone fires a false reset at every battle. An unavailable run does not clear tracking; the comparison on return detects a new run.
- Reactions must not read the achievement store or depend on achievement completion.
- Toasts are always on.
- Compact UI needs explicit font, stylebox, and popup overrides; see **UI Sizing and Theme Overrides**. Do not rely on Godot's default theme for HUD/tool controls.
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

# 2. Run the headless unit-test suite (all suites)
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\run_tests.ps1
```

- Use these scripts — do not hand-roll `godot --headless ...` commands. They are the
  canonical checks and behave identically for every contributor.
- Both accept `-Root <path>` (defaults to the mod root) and `-Godot <exe>`
  (defaults to the path above). Pass `-Godot` only if the binary moves.
- Do not report a change as complete unless both scripts exit `0`. Quote the suite and
  assertion counts from `run_tests.ps1` output, and say plainly that gameplay
  verification is still pending when it is.
- To re-run one test method, use the runner's filter instead of a separate script:
  `"C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script tests\run_tests.gd -- --test=<exact_name>`
- Expected noise: `run_tests.ps1` prints a `Parse JSON failed` error and a
  `Brain Rot: invalid achievements JSON` warning — that is the corrupt-file test
  exercising [`achievements/achievement_store.gd`](achievements/achievement_store.gd).
  Exit code `0` with `0 failures` is a pass.

## Game Source Code

- Do not attempt to locate, extract, or decompile Batomon Showdown's original source code. The game's Godot PCK is encrypted, and attempting to access it wastes time and tokens.
- Instead, investigate game behavior using existing mod code, runtime inspection, Godot's scene tree, object properties, signals, and targeted debug logging.
- Prefer existing discoveries and utilities in this repository before implementing new inspection logic.

