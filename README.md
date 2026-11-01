# Brain Rot

Fun additions for **Batomon Showdown**. Currently ships achievement detection,
persistence, and unlock toasts; more brainrot features are planned.

## Features

### Achievements
- Tracks run and battle state every 500 ms and awards achievements as you play.
- Completion is persisted to `achievements.json` at the mod root.
- Unlocks are printed to the log; enable **Achievement Notifications** in the
  ModLoader settings to also show a bottom-right toast.

### Planned
- Additional "fun" features beyond achievements. The achievement system will
  remain part of the mod.

## Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `achievement_notifications` | bool | `false` | Show toast notifications when an achievement is unlocked |

Settings are read through `ModLoader.get_config("brain_rot", ...)` and update live
when changed.

## Development

See [`_agent.md`](_agent.md) for architecture and conventions, and
[`dev/QUALITY.md`](dev/QUALITY.md) for the test strategy.

- Parse-check every script: `powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\gd_checks.ps1`
- Run the headless suite: `powershell -NoProfile -ExecutionPolicy Bypass -File .\dev\run_tests.ps1`

Both scripts default to `C:\Code\Godot\Godot_v4.7.2-stable_win64_console.exe`;
override with `-Godot <path>` if Godot is installed elsewhere.

- Optional debug capture: set `BRAINROT_DUMP_DIR` to an absolute directory to
  write run/battle snapshots for fixture replay.
