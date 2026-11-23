<#
.SYNOPSIS
  Installs the equipment workstream's development UE4SS mod (SimOverhaulEquipment) into the game.
.DESCRIPTION
  -Mode Install copies ue4ss\SimOverhaulEquipment into the game's ue4ss\Mods folder with enabled.txt (so mods.txt
  is left alone) and, with -Dev, dev.txt (the eval console, the request file and equipment-log.txt). settings.txt in the
  game folder is kept. -Mode Uninstall removes the folder; -Mode Status shows what is installed.
  No pak: this part changes no tables. The mod loads at the next game start.

  The game baseline is the integrated mod (Mods\SimulatorUpgrade; Mods\SimulatorOverhaul for builds made before the
  rename), which already carries this part. While it is installed, Install refuses (both copies would run): rebuild
  and install the integrated mod instead (tools\integrate\build_mod.py --dev, tools\meters\Install-Integrated.ps1).
  Status then shows the equipment files and log inside the integrated folder.

  Guards (docs\COORDINATION.md, "Taking turns"):
  * The game lock. Install and Uninstall, dry runs (-WhatIf) included, refuse on a real game folder (one with
    End\Binaries\Win64\ff7rebirth_.exe) unless GAME-LOCK.json names -Holder (default "equipment") and was refreshed
    in the last 30 minutes. Status only reads and needs no lock. A folder without the game (a test copy) needs none.
  * The target path. The only folder written or removed is <GameRoot>\End\Binaries\Win64\ue4ss\Mods\SimOverhaulEquipment.
  * -WhatIf lists what would change and writes nothing.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Install", "Uninstall", "Status")] [string] $Mode = "Status",
    [string] $GameRoot = "D:\Epic Games\FinalFantasyVIIRebirth",
    [switch] $Dev,
    [string] $Holder = "equipment",
    [string] $LockFile = "D:\FF7RebirthModding\Mods\SimulatorOverhaul\GAME-LOCK.json"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $repo "ue4ss\SimOverhaulEquipment"
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$mods = Join-Path $GameRoot "End\Binaries\Win64\ue4ss\Mods"
$target = Join-Path $mods "SimOverhaulEquipment"
# The integrated mod, under its new name first.
$integrated = $null
foreach ($name in "SimulatorUpgrade", "SimulatorOverhaul") {
    $folder = Join-Path $mods $name
    if (Test-Path (Join-Path $folder "Scripts\equipment")) { $integrated = $folder; break }
}

# The game lock, before anything that writes (or would write) into a real game folder.
function Assert-GameLock {
    if (-not (Test-Path (Join-Path $GameRoot "End\Binaries\Win64\ff7rebirth_.exe"))) { return }
    if (-not (Test-Path $LockFile)) { throw "No game lock ($LockFile): take it first (docs\COORDINATION.md)." }
    $lock = Get-Content -Raw $LockFile | ConvertFrom-Json
    if ($lock.holder -ne $Holder) { throw "The game lock is held by '$($lock.holder)', not '$Holder'." }
    $refreshed = [DateTime]::Parse($lock.refreshed, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    if (((Get-Date).ToUniversalTime() - $refreshed).TotalMinutes -gt 30) {
        throw "The game lock was last refreshed at $($lock.refreshed) (over 30 minutes ago): refresh it first."
    }
}

# Only this part's own standalone folder is ever written or removed.
function Assert-Target {
    $full = [System.IO.Path]::GetFullPath($target)
    $expected = [System.IO.Path]::GetFullPath((Join-Path $GameRoot "End\Binaries\Win64\ue4ss\Mods\SimOverhaulEquipment"))
    if ($full -ne $expected -or (Split-Path -Leaf $full) -ne "SimOverhaulEquipment") { throw "Refusing to write to $full" }
}

switch ($Mode) {
    "Status" {
        if ($integrated) {
            Write-Output "integrated: $integrated"
            Get-ChildItem (Join-Path $integrated "Scripts\equipment"), (Join-Path $integrated "Scripts\equipment_main.lua") |
                Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
            $log = Join-Path $integrated "equipment-log.txt"
            if (Test-Path $log) { Get-Content -Tail 5 $log }
        }
        if (Test-Path $target) {
            Write-Output "standalone installed: $target"
            Get-ChildItem -Recurse $target | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
        } elseif (-not $integrated) { Write-Output "not installed" }
    }
    "Uninstall" {
        Assert-GameLock
        Assert-Target
        if (Test-Path $target) {
            if ($PSCmdlet.ShouldProcess($target, "Remove the standalone equipment mod")) {
                Remove-Item -Recurse -Force $target
                Write-Output "removed $target"
            }
        } else { Write-Output "not installed" }
    }
    "Install" {
        Assert-GameLock
        Assert-Target
        if ($integrated) {
            throw ("$integrated is installed and already carries this part; a standalone copy beside it would run too. " +
                "Rebuild the integrated mod (tools\integrate\build_mod.py --dev) and install that instead.")
        }
        if (-not $PSCmdlet.ShouldProcess($target, "Install the standalone equipment mod (dev=$Dev)")) { return }
        $keep = $null
        $settings = Join-Path $target "settings.txt"
        if (Test-Path $settings) { $keep = Get-Content -Raw $settings }
        if (Test-Path (Join-Path $target "Scripts")) { Remove-Item -Recurse -Force (Join-Path $target "Scripts") }
        New-Item -ItemType Directory -Force $target | Out-Null
        Copy-Item -Recurse (Join-Path $source "Scripts") $target
        Set-Content -Encoding ascii (Join-Path $target "enabled.txt") ""
        if ($Dev) { Set-Content -Encoding ascii (Join-Path $target "dev.txt") "" }
        elseif (Test-Path (Join-Path $target "dev.txt")) { Remove-Item (Join-Path $target "dev.txt") }
        if ($null -ne $keep) { Set-Content -NoNewline -Encoding ascii $settings $keep }
        elseif (Test-Path (Join-Path $source "settings.txt")) { Copy-Item (Join-Path $source "settings.txt") $target }
        Write-Output "installed $target (dev=$Dev)"
    }
}
