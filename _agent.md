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

## Investigation
- Before modifying code, inspect the relevant existing implementation.
- Do not invent game APIs, node paths, or signal names.
- Do not modify the game's original files.

## Communication Style
- Be concise and direct.
- Assume I am an experienced software developer.
- When changes are complete, summarize what changed, what to test, and any remaining concerns.
- Do not exhaustively update this document with each and every achievement and reaction in the mod. Keep this scoped to understanding this repo itself.

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
| `notifications/toast_catalog.gd` | Builds preview entries from the achievement/reaction registries and duplicate-allowed requests; reaction titles and descriptions come from `reaction_definitions.gd`. |
| `audio/ui_sound.gd` | Lazy one-shot OGG player adapted from Creature Comforts, with optional per-sound volume. |
| `audio/reaction_sounds.gd` | Reaction audio derived from each definition's `sound` block; lazy per-file players. |
| `achievements/battle_completion_detector.gd` | Owns when battle evaluation happens: `is_pending(state)` (non-consuming) and `consume()` after a usable snapshot exists. |
| `reactions/reaction_definitions.gd` | The single source of truth for reactions: `DEFINITIONS` (id, title, optional message/sound, triggers), the run/outcome field registry, battle metric map, and comparison ops. Adding a reaction is one block here. |
| `reactions/reaction_evaluator.gd` | Rules only: evaluates `DEFINITIONS` from snapshots. `poll(run_snapshot)` and `poll_battle(battle_snapshot)` return newly triggered reactions; `reset_run()` / `reset_battle()` clear occurrence tracking. No store, UI, or live objects. |
| `reactions/reaction_player.gd` | Plays a reaction: logs `Brain Rot: REACTION \| <id> \| <detail>` to console and `inspect.log`, submits a toast (title from `reaction_definitions.gd`), and forwards the id to the sound sink. |
| `debug/state_capture.gd` | Optional `BRAINROT_DUMP_DIR` debug dump of changed snapshots (signature + counter). |
| `tests/` | Zero-dependency unit tests: `achievement_evaluator`, `achievement_store`, `battle_completion_detector`, `achievements_schema`, `fixture_replay`, `game_snapshot_reader`, `state_capture`, `reaction_definitions`, `reaction_evaluator`, `reaction_player`, `toast_catalog`, `toast_preview_panel`, `dev_config`, `mod_main_preview`, `reaction_sounds`, `ui_sound`. |
| `dev/dev_config.gd` | Developer-mode gate (`DEV_MODE` constant or `BRAINROT_DEV_MODE`); not a user-facing setting. |
| `dev/gd_checks.ps1` | Parse-checks every `.gd` file in the repo with `--check-only`, one Godot process per file; exits non-zero on any failure. |
| `dev/run_tests.ps1` | Runs `tests/run_tests.gd` headless (all suites in one Godot process); exits with the runner's exit code. |
| `dev/fixtures/` | Curated/captured run and battle snapshots replayed by `test_fixture_replay.gd`. |

### Locating the gitignored dev files
`.gitignore` has `dev/*`, so the `dev/` scripts are **gitignored but present on disk**. Tools that respect `.gitignore` (including some directory listings) will not show them, which makes them look missing. They are not missing — read or run them by path:

- Read them directly, e.g. `dev/run_tests.ps1`.
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
- Reaction definitions live in `reactions/reaction_definitions.gd`. Adding a reaction is one block there; the evaluator, toast titles, sounds, and preview descriptions all read from it. Do not add per-reaction tables elsewhere. `tests/test_reaction_definitions.gd` validates the schema and generates a match/boundary-miss case per trigger.
- Reaction conditions support int fields (`lives`, `day`, `wins`, `income`), the string field `trainer` (eq/ne only), `any` blocks, and `owns` (a team or bench unit matching a species and level comparison). `owns` is state-based, so the generated matrix covers it.
- Run-scoped reactions are evaluated only while the shop state is active (`mod_main` gates `poll()` on `shop_state.gd`; the evaluator stays phase-agnostic). The game promotes the completed run into `RunManager.data` before the visual battle ends (see BatomonHelperBridge `read_battle_outcome`), so polling mid-battle would fire the lives/wins paths of 6 7 and 6 9 before the player sees the next day. Battle- and outcome-scoped reactions still fire at `battle_over`.
- Toasts are always on.
- Compact UI needs explicit font, stylebox, and popup overrides; see **UI Sizing and Theme Overrides**. Do not rely on Godot's default theme for HUD/tool controls.
- Retain the 500 ms polling interval unless measurements justify changing it.
- Tests must stay deterministic; the evaluators no longer use wall-clock time.
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

