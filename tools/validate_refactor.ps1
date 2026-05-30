param(
    [string]$GodotExe = "d:\Godot\Godot_v4.5.2-stable_win64.exe",
    [switch]$RunImport
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$LogDir = Join-Path $RepoRoot ".codex-godot"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    $LogPath = Join-Path $LogDir "$Name.log"
    if (Test-Path $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force
    }

    $FullArgs = @("--path", $RepoRoot) + $Arguments + @("--log-file", $LogPath)
    $Process = Start-Process -FilePath $GodotExe -ArgumentList $FullArgs -Wait -PassThru -WindowStyle Hidden
    if ($Process.ExitCode -ne 0) {
        if (Test-Path $LogPath) {
            Get-Content $LogPath -Tail 200
        }
        throw "$Name failed with exit code $($Process.ExitCode)"
    }

    if (Test-Path $LogPath) {
        $ProblemLines = Select-String -Path $LogPath -Pattern "ERROR:|SCRIPT ERROR:|Parse Error|Failed to create an autoload" |
            Where-Object {
                $_.Line -notmatch "resources still in use at exit"
            }
        if ($ProblemLines) {
            $ProblemLines | Select-Object -First 80
            throw "$Name wrote errors to $LogPath"
        }
    }

    Write-Host "[ok] $Name"
}

Push-Location $RepoRoot
try {
    if (-not (Test-Path $GodotExe)) {
        throw "Godot executable not found: $GodotExe"
    }

    git diff --check
    Write-Host "[ok] git diff --check"

    Invoke-GodotCheck "check-gamepad-manager" @("--headless", "--check-only", "--script", "res://scripts/GamepadManager.gd")
    Invoke-GodotCheck "check-event-bus" @("--headless", "--check-only", "--script", "res://scripts/EventBus.gd")
    Invoke-GodotCheck "check-rhythm-clock" @("--headless", "--check-only", "--script", "res://scripts/RhythmClock.gd")
    Invoke-GodotCheck "check-attack-heat-model" @("--headless", "--check-only", "--script", "res://scripts/AttackHeatModel.gd")
    Invoke-GodotCheck "check-attack-hit-queue" @("--headless", "--check-only", "--script", "res://scripts/AttackHitQueue.gd")
    Invoke-GodotCheck "check-attack-music-fade-rules" @("--headless", "--check-only", "--script", "res://scripts/AttackMusicFadeRules.gd")
    Invoke-GodotCheck "check-attack-phase-timing" @("--headless", "--check-only", "--script", "res://scripts/AttackPhaseTiming.gd")
    Invoke-GodotCheck "check-battle-subsystem-coordinator" @("--headless", "--check-only", "--script", "res://scripts/BattleSubsystemCoordinator.gd")
    Invoke-GodotCheck "check-attack-beat-grid" @("--headless", "--check-only", "--script", "res://scripts/AttackBeatGrid.gd")
    Invoke-GodotCheck "check-boss-charge-bullet-timing" @("--headless", "--check-only", "--script", "res://scripts/BossChargeBulletTiming.gd")
    Invoke-GodotCheck "check-character-attack-hitbox-rules" @("--headless", "--check-only", "--script", "res://scripts/CharacterAttackHitboxRules.gd")
    Invoke-GodotCheck "check-player-afterimage-factory" @("--headless", "--check-only", "--script", "res://scripts/PlayerAfterimageFactory.gd")
    Invoke-GodotCheck "check-debug-shape-drawer" @("--headless", "--check-only", "--script", "res://scripts/DebugShapeDrawer.gd")
    Invoke-GodotCheck "check-sprite-animation-duration" @("--headless", "--check-only", "--script", "res://scripts/SpriteAnimationDuration.gd")
    Invoke-GodotCheck "check-heat-beat-flash-style" @("--headless", "--check-only", "--script", "res://scripts/HeatBeatFlashStyle.gd")
    Invoke-GodotCheck "check-attack-beat-track-layout" @("--headless", "--check-only", "--script", "res://scripts/AttackBeatTrackLayout.gd")
    Invoke-GodotCheck "check-defense-judgment-rules" @("--headless", "--check-only", "--script", "res://scripts/DefenseJudgmentRules.gd")
    Invoke-GodotCheck "check-defense-note-search" @("--headless", "--check-only", "--script", "res://scripts/DefenseNoteSearch.gd")
    Invoke-GodotCheck "check-defense-input-resolution" @("--headless", "--check-only", "--script", "res://scripts/DefenseInputResolution.gd")
    Invoke-GodotCheck "check-music-clock-event-queue" @("--headless", "--check-only", "--script", "res://scripts/MusicClockEventQueue.gd")
    Invoke-GodotCheck "check-hit-note-side-assignments" @("--headless", "--check-only", "--script", "res://scripts/HitNoteSideAssignments.gd")
    Invoke-GodotCheck "check-track-cue-request-registry" @("--headless", "--check-only", "--script", "res://scripts/TrackCueRequestRegistry.gd")
    Invoke-GodotCheck "check-prejudge-key-hint-style" @("--headless", "--check-only", "--script", "res://scripts/PrejudgeKeyHintStyle.gd")
    Invoke-GodotCheck "check-tracked-note-runtime" @("--headless", "--check-only", "--script", "res://scripts/TrackedNoteRuntime.gd")
    Invoke-GodotCheck "check-boss-part-health-model" @("--headless", "--check-only", "--script", "res://scripts/BossPartHealthModel.gd")
    Invoke-GodotCheck "check-boss-missile-side-selector" @("--headless", "--check-only", "--script", "res://scripts/BossMissileSideSelector.gd")
    Invoke-GodotCheck "check-boss-missile-launcher-recoil-state" @("--headless", "--check-only", "--script", "res://scripts/BossMissileLauncherRecoilState.gd")
    Invoke-GodotCheck "check-boss-missile-warning-light-style" @("--headless", "--check-only", "--script", "res://scripts/BossMissileWarningLightStyle.gd")
    Invoke-GodotCheck "check-boss-pre-charge-target-picker" @("--headless", "--check-only", "--script", "res://scripts/BossPreChargeTargetPicker.gd")
    Invoke-GodotCheck "check-dialogue-pause-state" @("--headless", "--check-only", "--script", "res://scripts/DialoguePauseState.gd")
    Invoke-GodotCheck "check-dialogue-ui" @("--headless", "--check-only", "--script", "res://scenes/dialogue_ui.tscn.gd")
    Invoke-GodotCheck "check-offset-calibration" @("--headless", "--check-only", "--script", "res://scripts/OffsetCalibration.gd")
    Invoke-GodotCheck "project-headless" @("--headless", "--quit-after", "10")
    Invoke-GodotCheck "main-scene-smoke" @("--headless", "--scene", "res://scenes/Main.tscn", "--quit-after", "30")
    Invoke-GodotCheck "tutorial-scene-smoke" @("--headless", "--scene", "res://scenes/tutorial.tscn", "--quit-after", "30")
    Invoke-GodotCheck "offset-calibration-scene-smoke" @("--headless", "--scene", "res://scenes/OffsetCalibration.tscn", "--quit-after", "10")

    if ($RunImport) {
        Invoke-GodotCheck "editor-import" @("--import")
    } else {
        Write-Host "[skip] editor-import (pass -RunImport outside sandbox when needed)"
    }
}
finally {
    Pop-Location
}
