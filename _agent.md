# AGENTS.md — Brain Rot

## Summary
Brain Rot (`brain_rot`) is a standalone GDScript mod for **Batomon Showdown**. Reactions — detect and display fun unlock toasts — are the first feature; more "fun" features are planned, so keep new code modular rather than reaction-specific where practical.

The reaction system polls the live run and battle state every 500 ms, reads them into plain snapshot Dictionaries (`game_snapshot_reader.gd`), evaluates reactions from those snapshots, and shows a bottom-right toast. It is self-contained and does not depend on other mods.

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
- Do not exhaustively update this document with each and every reaction in the mod. Keep this scoped to understanding this repo itself.

## Logging
Logging mirrors Creature Comforts (same helpers, different path). `mod_main.gd` keeps one append handle open for the session and writes to:

```
user://brain_rot/inspect.log
```

On Windows that is `%APPDATA%\Godot\app_userdata\Batomon Showdown\brain_rot\inspect.log`.

- `_print_notice(message)` - console **and** file, no prefix. Used for user-visible events (`loaded`, `REACTION`, `run reset`).
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

## Persistence
High scores live in `user://brain_rot/high_scores.json` (Windows:
`%APPDATA%\Godot\app_userdata\Batomon Showdown\brain_rot\high_scores.json`).
The store is `{"version": 1, "metrics": {"damage": {"value": int, "unit": String}, ...}}`
and records the best single-unit value per battle metric for the player's team,
plus the unit that set it. It is global across runs, updated once per completed
battle, and written only when a metric improves. The Brain Rot Memories shop
panel reads the same store.

## Shop HUD
The rainbow brain button in the shop opens the Brain Rot Memories panel. It is
positioned to the left of Creature Comforts' Replay Battle button position
(RIGHT_RATIO 0.80, TOP_RATIO 0.05). Close it with the X box, by clicking outside
the popup, or with Escape.

## UI Sizing and Theme Overrides
Godot's default control theme is sized for menus, not the mod's compact toast/HUD
scale. Native `Label`, `Button`, and `OptionButton` controls render with large
fonts, padding, and popup rows unless every control is overridden explicitly.
This bit the dev toast preview: without overrides, the dropdown popup and button
labels were several times larger than the surrounding toast UI.

The toast itself is a left-aligned rounded badge (the request's `icon` text) with
the three text lines (header, title, description) to its right. The badge is drawn
with `hud/styles.gd`'s `make_badge_style()` and sized by `BADGE_SIZE`; the badge
text is centered and clipped, using `BADGE_FONT_SIZE` for short icons and
`BADGE_FONT_SIZE_SMALL` for three-or-more characters.

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
  progress, saves, or game state.

This is the Brain Rot adaptation of Creature Comforts' HUD sizing approach
(`hud/comfort_panel.gd` `_build_hud_box()` and `hud/watchlist_panel.gd`
`_apply_font()` plus its `OptionButton` popup overrides).

## Files
| File | Responsibility |
|---|---|
| `mod.json` | Mod identity (`brain_rot`), version, and description. |
| `mod_main.gd` | Loader lifecycle, session log (`user://brain_rot/inspect.log`), 500 ms polling, run-transition detection, coordination of reader/evaluator/detector/capture, toast display, and self-updater setup. |
| `core/auto_updater.gd` | GitHub self-updater (adapted from Creature Comforts): checks `update.json`, validates/downloads/compiles the release zip, and swaps files. Always on; disables itself on dev installs. |
| `snapshots/game_snapshot_reader.gd` | The only place that reads live game objects; produces plain snapshot Dictionaries (run and battle, including derived shop `income`) with absent keys for unknown values. |
| `hud/toast_view.gd` | Bottom-right toast view; the notification host owns placement and timing. Renders a left-aligned rounded badge (the request's icon text) beside the three text lines (header, title, description). |
| `hud/styles.gd` | Shared palette, font, panel chrome, compact-button chrome, badge chrome, and toast layout metrics. |
| `hud/toast_preview_panel.gd` | Dev-only preview button/panel: Reaction and Case dropdowns plus inputs for the selected template's placeholders; Play renders the same match as gameplay. |
| `hud/panel_icons.gd` | Shared loader/drawer for loose mod icons (close box). |
| `hud/shop_modal_panel.gd` | Shared shop icon-button modal scaffolding (button, frame, close box, click-outside/Escape close). |
| `hud/table_modal_panel.gd` | Shared row-table layout for shop modals. |
| `hud/memories_panel.gd` | The shop's Brain Rot Memories high-score modal (rainbow brain button). |
| `audio/ui_sound.gd` | Lazy one-shot OGG player adapted from Creature Comforts, with optional per-sound volume. |
| `audio/reaction_sounds.gd` | Reaction audio derived from each catalog entry's `sound` block; lazy per-file players. |
| `battle/battle_completion_detector.gd` | Owns when battle evaluation happens: `is_pending(state)` (non-consuming) and `consume()` after a usable snapshot exists. |
| `battle/high_scores.gd` | Persistent per-metric best single-unit battle values (`user://brain_rot/high_scores.json`); pure parse/serialize/record helpers plus display formatting. |
| `catalog/brain_rot_catalog.gd` | The single source of truth for reaction detection metadata: `ENTRIES` (kind, id, title, optional icon/species/scopes/sound), run-scoped `run_match()`, and battle rules. No user text. |
| `catalog/reaction_text.gd` | The single source of user-facing reaction wording: `TEMPLATES` (id -> case -> template), placeholder filling, species-name and number formatting. Detection never produces text. |
| `reactions/reaction_evaluator.gd` | Rules only: calls the catalog's reaction checks from snapshots and owns occurrence tracking plus the battle lowest-slot / metric-order tie-break. `poll(run_snapshot)` and `poll_battle(battle_snapshot)` return newly triggered reactions; `reset_run()` / `reset_battle()` clear tracking. Battle rules may filter by species (Big Dog is Cinnabark-only). No store, UI, or live objects. |
| `reactions/reaction_player.gd` | Plays a reaction match: renders text via `catalog/reaction_text.gd`, logs `REACTION`/`PREVIEW \| <id> \| <case> \| <text>`, submits a toast, and forwards the id to the sound sink. |
| `debug/state_capture.gd` | Optional `BRAINROT_DUMP_DIR` debug dump of changed snapshots (signature + counter). |
| `tests/` | Zero-dependency unit tests: `auto_updater`, `battle_completion_detector`, `fixture_replay`, `game_snapshot_reader`, `state_capture`, `high_scores`, `memories_panel`, `catalog`, `reaction_evaluator`, `reaction_player`, `reaction_text`, `toast_preview_panel`, `dev_config`, `mod_main_preview`, `reaction_sounds`, `ui_sound`. |
| `dev/dev_config.gd` | Developer-mode gate (`DEV_MODE` constant or `BRAINROT_DEV_MODE`); not a user-facing setting. |
| `dev/gd_checks.ps1` | Parse-checks every `.gd` file in the repo with `--check-only`, one Godot process per file; exits non-zero on any failure. |
| `dev/run_tests.ps1` | Runs `tests/run_tests.gd` headless (all suites in one Godot process); exits with the runner's exit code. |
| `dev/asciicheck.ps1` | Verifies every shipped text file is plain ASCII (no Godot); exits non-zero on any non-ASCII byte. |
| `dev/package_release.ps1` | Builds `dist/BrainRot-<version>.zip` and `dist/update.json` for the GitHub auto-update channel. |
| `dev/validate_release.ps1` | Verifies a Brain Rot release locally and/or on GitHub (zip, manifest, checksums, published assets). |
| `dev/fixtures/` | Curated/captured run and battle snapshots replayed by `test_fixture_replay.gd`. |

### Locating the gitignored dev files
`.gitignore` has `dev/*`, so the `dev/` scripts are **gitignored but present on disk**. Tools that respect `.gitignore` (including some directory listings) will not show them, which makes them look missing. They are not missing — read or run them by path:

- Read them directly, e.g. `dev/run_tests.ps1`, `dev/asciicheck.ps1`,
  `dev/package_release.ps1`, or `dev/validate_release.ps1`.
- List them with a shell that ignores `.gitignore`:
  `cmd /c dir /a "dev"` or `powershell -NoProfile -Command "Get-ChildItem dev -Force"`.
- Run them from the mod root as documented in **Verification** below.
- Do not "restore" or recreate them; if a path truly does not exist, ask before adding it.
- `dev/fixtures/` is un-ignored (`!dev/fixtures/`) because `tests/test_fixture_replay.gd`
  depends on it; keep it tracked. `dev/dev_config.gd` is also un-ignored.
- `_agent.md` and `plans/` are gitignored too, so they are local-only as well.

## Working conventions
- Verify game identifiers/properties from source or runtime evidence; never invent APIs.
- Keep the evaluator independent of live game objects, file writing, and UI drawing. All live-object reads belong in `game_snapshot_reader.gd`.
- Snapshots use absent keys for unknown values; defaults belong to the rules, not the reader.
- Battle evaluation timing belongs to `battle_completion_detector.gd`; the reaction evaluator's `poll_battle` is a pure rule check.
- Call `reset_run()` at verified run transitions (inferred in `mod_main` from `run_id`, then run object instance, trainer, and day regression). `run_id` is the primary identity: the game promotes `RunManager.data` to a new RunData object when a battle starts, so instance comparison alone fires a false reset at every battle. An unavailable run does not clear tracking; the comparison on return detects a new run.
- Reactions must not read any persisted completion state; they fire from the current snapshot only.
- Detection and wording are separate: `catalog/brain_rot_catalog.gd` owns detection metadata and returns matches (`{id, case, params}`); `catalog/reaction_text.gd` owns every line a player reads. Adding an entry is one metadata row plus one check function plus one `TEMPLATES[id]` table. Do not write user text in detection code.
- Reaction checks are plain typed GDScript (`run_match` for run scope, `battle_rule` for battle scope). There is no condition DSL; add a `match` arm and a helper for a new reaction.
- Run-scoped reactions are evaluated only while the shop state is active (`mod_main` gates `poll()` on `shop_state.gd`; the evaluator stays phase-agnostic). The game promotes the completed run into `RunManager.data` before the visual battle ends (see BatomonHelperBridge `read_battle_outcome`), so polling mid-battle would fire the lives/wins paths of 6 7 and 6 9 before the player sees the next day. Battle-scoped reactions still fire at `battle_over`.
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
# 1. Parse-check every .gd file (mod_main.gd, snapshots/, hud/, tests/, ...)
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\gd_checks.ps1

# 2. Run the headless unit-test suite (all suites)
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\run_tests.ps1

# 3. Verify shipped text files are plain ASCII
powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\asciicheck.ps1
```

- Use these scripts — do not hand-roll `godot --headless ...` commands. They are the
  canonical checks and behave identically for every contributor.
- `gd_checks.ps1` and `run_tests.ps1` accept `-Root <path>` (defaults to the mod root)
  and `-Godot <exe>` (defaults to the path above). Pass `-Godot` only if the binary
  moves. `asciicheck.ps1` accepts `-Paths` and `-Quiet`.
- Do not report a change as complete unless all three scripts exit `0`. Quote the suite
  and assertion counts from `run_tests.ps1` output, and say plainly that gameplay
  verification is still pending when it is.
- To build and verify a release, use `.\dev\package_release.ps1` and
  `.\dev\validate_release.ps1` (see their headers). `package_release.ps1` writes
  `dist/` (gitignored) and must be run after the version is bumped in both `mod.json`
  and `mod_main.gd`.
- To re-run one test method, use the runner's filter instead of a separate script:
  `"C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script tests\run_tests.gd -- --test=<exact_name>`

## Game Source Code

- Do not attempt to locate, extract, or decompile Batomon Showdown's original source code. The game's Godot PCK is encrypted, and attempting to access it wastes time and tokens.
- Instead, investigate game behavior using existing mod code, runtime inspection, Godot's scene tree, object properties, signals, and targeted debug logging.
- Prefer existing discoveries and utilities in this repository before implementing new inspection logic.
