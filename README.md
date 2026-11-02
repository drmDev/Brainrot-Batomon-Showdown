# Brain Rot

Fun additions for **Batomon Showdown**. Currently ships achievement detection,
persistence, and unlock toasts; more brainrot features are planned.

## Features

### Achievements
- Tracks run and battle state every 500 ms and awards achievements as you play.
- Completion is persisted to `achievements.json` at the mod root.
- Unlocks are printed to the log and shown as a bottom-right toast.

### Planned
- Additional "fun" features beyond achievements. The achievement system will
  remain part of the mod.

## Settings

This mod has no configurable settings; toasts are always on.

## Development

See [`_agent.md`](_agent.md) for architecture and conventions

- Parse-check every script: `powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\gd_checks.ps1`
- Run the headless suite: `powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\run_tests.ps1`

Both scripts default to `C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe`;
override with `-Godot <path>` if Godot is installed elsewhere.

- Optional debug capture: set `BRAINROT_DUMP_DIR` to an absolute directory to
  write run/battle snapshots for fixture replay.
- Developer mode: set `DEV_MODE := true` in `dev/dev_config.gd` (or set
  `BRAINROT_DEV_MODE=1`) to show a small **Preview** button. It opens a dropdown
  of every registered achievement and reaction toast; Play replays the selected
  toast repeatedly without touching progress, saves, or game state.
