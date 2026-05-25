# Refactor Iteration Prep

This project is ready for multi-pass refactoring on branch `codex/refactor-prep`.

## Baseline Fix

Remote `origin/main` currently contains duplicate `GamepadManager` autoload entries in `project.godot`:

- `GamepadManager="*res://scenes/autoload/GamepadManager.tscn"`
- `GamepadManager="*res://scripts/GamepadManager.gd"`

Keep only the wrapper scene entry. The duplicate script entry causes editor startup to report a `GamepadManager.gd` autoload compile failure.

## Validation Rules

Use the GUI Godot executable, not the console executable:

```powershell
d:\Godot\Godot_v4.5.2-stable_win64.exe
```

The console executables on this machine have repeatedly crashed with `signal 11`, including both 4.5.2 and 4.6.2.

Run the local validation script after each meaningful iteration:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_refactor.ps1
```

Run the editor import check only outside the Codex sandbox, because Godot writes preview/cache files under `%LOCALAPPDATA%\Godot`:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\validate_refactor.ps1 -RunImport
```

Inside the sandbox, `--import` can produce false errors such as `Cannot create file ... AppData/Local/Godot/resthumb-*.png`.

## Refactor Guardrails

- Preserve `MusicPlayer.get_song_time()` as the authoritative rhythm clock.
- Keep beat-visible gameplay on absolute music time plus `_process()` polling, not `Timer` drift.
- Treat autoload wrapper scenes under `scenes/autoload/` as the safe autoload pattern.
- Keep controller prompts routed through `GamepadManager` and `GameConstants.get_action_key_label()`.
- Split giant scripts incrementally, with a runnable checkpoint after each extraction.
- Avoid broad scene rewrites unless a script extraction requires it.

## First Safe Iterations

1. Keep the autoload duplicate fix and verify startup. Done in `8e3bd81`.
2. Remove or isolate obvious debug-only code and scene flags. Done in `7de8e22`.
3. Extract rhythm-clock helpers without changing timing behavior. Done across `ca5247b`, `6f0deb9`, and `d075f0d`.
4. Split attack-phase input from defense judgment. Done across `953e015`, `e545970`, `b279c5f`, and `a5e94ae`.
5. Extract Boss subsystems one at a time. In progress: part health, missile side selection, and pre-charge target picking are extracted.
6. Extract Player hitbox/death-flow subsystems. In progress: attack hitbox rules are extracted.
7. Split TrackManager visual spawning, miss detection, and boss cue routing. Still pending.

## Current Checkpoint

The branch now has reusable helper scripts for:

- Shared rhythm clock reads and music-clock event queues.
- Attack heat, attack beat grid, defense judgment rules, and defense note search.
- Boss part health, missile side selection, and pre-charge target picking.
- Boss missile warning light style and missile launcher recoil state.
- Character attack hitbox timing, preset, and default geometry rules.
- Track HIT note missile side assignments and cue request de-duplication.

Next high-value iterations:

1. Continue reducing `Boss.gd` by extracting charge bullet timing helpers and player dash afterimage helpers.
2. Split `TrackManager.gd` into note spawning, miss resolution, and boss cue routing.
3. Move `Character.gd` death-flow and debug-hitbox drawing into smaller collaborators.
4. Remove remaining old or ambiguous naming after confirming scene usage.
