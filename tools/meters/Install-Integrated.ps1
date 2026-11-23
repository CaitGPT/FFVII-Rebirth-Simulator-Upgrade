[CmdletBinding(SupportsShouldProcess)]
param(
    # Install: back up what is installed of the integrated mod, then put build\integrated in its place.
    # Restore: put a backup back (-Backup <folder>).
    [ValidateSet('Install', 'Restore')]
    [string]$Mode = 'Install',
    [string]$Build = '',              # default: build\integrated in this worktree
    [string]$Backup = '',
    [string]$Source = '',            # what the build was made from, for INSTALLED.txt
    [string]$GameRoot = 'D:\Epic Games\FinalFantasyVIIRebirth'
)
# The game baseline (docs/COORDINATION.md): the integrated mod, no standalone SimOverhaul* parts. Game closed, and only
# while holding the game lock. Backups go to D:\FF7RebirthModding\Mods\SimulatorOverhaul\install-backups\<time>.
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 has no $PSScriptRoot while it binds parameter defaults.
if (-not $Build) { $Build = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\integrated' }
$mods = Join-Path $GameRoot 'End\Binaries\Win64\ue4ss\Mods'
$paks = Join-Path $GameRoot 'End\Content\Paks\~mods'
$root = 'D:\FF7RebirthModding\Mods\SimulatorOverhaul'
$items = @(
    @{ From = Join-Path $Build 'SimulatorUpgrade'; To = Join-Path $mods 'SimulatorUpgrade' },
    @{ From = Join-Path $Build 'SimulatorUpgradeNative'; To = Join-Path $mods 'SimulatorUpgradeNative' }
)
$pakNames = 'SimulatorUpgrade_9200_P.pak', 'SimulatorUpgrade_9200_P.ucas', 'SimulatorUpgrade_9200_P.utoc'
# The mod's name before 2026-11-21 (docs/COORDINATION.md, "The name"): an install under it is backed up and removed, so
# the old and the renamed mod never run side by side, and its mods.txt lines are renamed.
$oldMods = @((Join-Path $mods 'SimulatorOverhaul'), (Join-Path $mods 'SimulatorOverhaulNative'))
$oldPakNames = 'SimulatorOverhaul_9200_P.pak', 'SimulatorOverhaul_9200_P.ucas', 'SimulatorOverhaul_9200_P.utoc'
$modsTxt = Join-Path $mods 'mods.txt'
if (Get-Process -Name 'ff7rebirth_' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }

if ($Mode -eq 'Install') {
    foreach ($i in $items) { if (-not (Test-Path -LiteralPath $i.From)) { throw "Missing $($i.From): build first" } }
    foreach ($p in $pakNames) { if (-not (Test-Path -LiteralPath (Join-Path $Build "~mods\$p"))) { throw "Missing ~mods\$p in the build" } }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $Backup = Join-Path $root "install-backups\$stamp"
    New-Item -ItemType Directory -Force (Join-Path $Backup 'Mods'), (Join-Path $Backup 'Paks') | Out-Null
    foreach ($m in @($items.To) + $oldMods) {
        if (Test-Path -LiteralPath $m) { Copy-Item -LiteralPath $m -Destination (Join-Path $Backup 'Mods') -Recurse }
    }
    foreach ($p in $pakNames + $oldPakNames) {
        $installed = Join-Path $paks $p
        if (Test-Path -LiteralPath $installed) { Copy-Item -LiteralPath $installed -Destination (Join-Path $Backup 'Paks') }
    }
    Copy-Item -LiteralPath $modsTxt -Destination $Backup
    $note = Join-Path $root 'INSTALLED.txt'
    if (Test-Path -LiteralPath $note) { Copy-Item -LiteralPath $note -Destination $Backup }
    foreach ($i in $items) {
        if (Test-Path -LiteralPath $i.To) { Remove-Item -LiteralPath $i.To -Recurse -Force }
        Copy-Item -LiteralPath $i.From -Destination $i.To -Recurse
    }
    foreach ($p in $pakNames) { Copy-Item -LiteralPath (Join-Path $Build "~mods\$p") -Destination $paks -Force }
    $removedOld = @()
    foreach ($m in $oldMods) { if (Test-Path -LiteralPath $m) { Remove-Item -LiteralPath $m -Recurse -Force; $removedOld += (Split-Path $m -Leaf) } }
    foreach ($p in $oldPakNames) {
        $installed = Join-Path $paks $p
        if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Force; $removedOld += $p }
    }
    # mods.txt: SimulatorOverhaul(Native) lines become SimulatorUpgrade(Native), in place, so the order stays.
    $lines = Get-Content -LiteralPath $modsTxt
    $renamed = $lines | ForEach-Object { $_ -replace '^(\s*)SimulatorOverhaul(Native)?(\s*:)', '${1}SimulatorUpgrade${2}${3}' }
    if (($renamed -join "`n") -ne ($lines -join "`n")) { $renamed | Set-Content -LiteralPath $modsTxt -Encoding ascii }
    if ($removedOld) { "Removed the old-named install (backed up): $($removedOld -join ', ')" }
    # Standalone parts must not run beside it.
    $standalone = @(Get-ChildItem -LiteralPath $mods -Directory | Where-Object { $_.Name -like 'SimOverhaul*' })
    $standalonePak = @(Get-ChildItem -LiteralPath $paks -Filter 'SimOverhaul*_P.*')
    "Installed $Build; backup in $Backup"
    "Standalone parts still present: $(@($standalone.Name) + @($standalonePak.Name) -join ', ')"
    $dll = (Get-FileHash -LiteralPath (Join-Path $mods 'SimulatorUpgradeNative\dlls\main.dll')).Hash
    @"
Installed $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) by meters (game turn): the integrated build, $Source
  tools/integrate/build_mod.py --dev (stages, ct, equipment, meters, ui)
    --stages-dll D:\FF7RebirthModding\Mods\SimulatorStages\native-build-130\Release\main.dll
    --native-dll <meters worktree>\build\overhaul-native\Release\main.dll (the combined SimulatorUpgradeNative: Custom
      Training's helper and the meters' hit events; SHA256 $($dll.Substring(0, 16))...)
    --pak-dir D:\FF7RebirthModding\Mods\SimulatorOverhaul\custom-training-build\Package-SimulatorUpgrade_9200_P
Game now has: ue4ss\Mods\SimulatorUpgrade, ue4ss\Mods\SimulatorUpgradeNative, ~mods\SimulatorUpgrade_9200_P.*
  (the mod's name since 2026-11-21; no SimulatorOverhaul folders or paks are left in the game)
Replaced (backed up in $Backup): what the INSTALLED.txt in that folder describes.
Standalone parts are still set aside where custom-training put them:
  D:\FF7RebirthModding\Mods\SimulatorOverhaul\custom-training-build\standalone-aside (Simulator Stages' standalone mod is
  there too: the integrated build's Stages part runs).
Restore the previous integrated build: game closed, then
  powershell -File <meters worktree>\tools\meters\Install-Integrated.ps1 -Mode Restore -Backup "$Backup"
mods.txt lists SimulatorUpgradeNative and SimulatorUpgrade after JunonColosseum (they also have enabled.txt; UE4SS
  starts each once, in mods.txt's order). Simulator Stages' standalone mod was enabled when it was set aside.
<meters worktree> is $(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).
Untouched: JunonColosseum_999_P, NoPopups_JunonCompat_9999_P, TrainingDummy_P and their UE4SS mods, BattleMeters and
  BattleMetersNative.
"@ | Set-Content -LiteralPath (Join-Path $root 'INSTALLED.txt') -Encoding utf8
}
else {
    if (-not $Backup -or -not (Test-Path -LiteralPath $Backup)) { throw 'Give -Backup <folder> from install-backups.' }
    # Either name may be in the backup (before or after the rename): remove both, put back what the backup has, and its
    # mods.txt, which lists the names it went with.
    foreach ($m in @($items.To) + $oldMods) {
        if (Test-Path -LiteralPath $m) { Remove-Item -LiteralPath $m -Recurse -Force }
        $saved = Join-Path $Backup ('Mods\' + (Split-Path $m -Leaf))
        if (Test-Path -LiteralPath $saved) { Copy-Item -LiteralPath $saved -Destination $m -Recurse }
    }
    foreach ($p in $pakNames + $oldPakNames) {
        $installed = Join-Path $paks $p
        if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Force }
        $saved = Join-Path $Backup "Paks\$p"
        if (Test-Path -LiteralPath $saved) { Copy-Item -LiteralPath $saved -Destination $paks -Force }
    }
    $savedList = Join-Path $Backup 'mods.txt'
    if (Test-Path -LiteralPath $savedList) { Copy-Item -LiteralPath $savedList -Destination $modsTxt -Force }
    "Restored from $Backup, mods.txt too (INSTALLED.txt not rewritten: the backup has the one that went with it)"
}
