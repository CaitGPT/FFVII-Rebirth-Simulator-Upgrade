[CmdletBinding(SupportsShouldProcess)]
param(
    # Install: the SimOverhaulMeters development mod (scripts, the native helper if built, enabled.txt, dev.txt).
    # Uninstall: remove it. Status: what is installed.
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Status',
    [string]$GameRoot = 'D:\Epic Games\FinalFantasyVIIRebirth',
    # Leave the native helper out (to see the fallback rules).
    [switch]$WithoutNative,
    # Install the combined SimulatorUpgradeNative test build (tools\meters\Build-Overhaul-Native.ps1 -Test) as this
    # mod's DLL instead of the meters' own helper, to try it beside Battle Meters' own native.
    [switch]$Combined
)
# Only while this workstream holds the game lock (docs/COORDINATION.md). The player's settings.txt is kept.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$target = Join-Path $GameRoot 'End\Binaries\Win64\ue4ss\Mods\SimOverhaulMeters'
$dll = Join-Path $root $(if ($Combined) { 'build\overhaul-native-test\Release\main.dll' } else { 'build\meters-native\Release\main.dll' })

switch ($Mode) {
    'Install' {
        if (-not $PSCmdlet.ShouldProcess($target, 'Install SimOverhaulMeters')) { return }
        $settings = Join-Path $target 'settings.txt'
        $kept = if (Test-Path -LiteralPath $settings) { Get-Content -LiteralPath $settings -Raw } else { $null }
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        New-Item -ItemType Directory -Force (Join-Path $target 'Scripts') | Out-Null
        Copy-Item -Path (Join-Path $root 'ue4ss\SimOverhaulMeters\Scripts\*.lua') -Destination (Join-Path $target 'Scripts')
        if (-not $WithoutNative) {
            if (-not (Test-Path -LiteralPath $dll)) { throw "Build the native helper first (tools\meters\Build-Native.ps1): $dll" }
            New-Item -ItemType Directory -Force (Join-Path $target 'dlls') | Out-Null
            Copy-Item -LiteralPath $dll -Destination (Join-Path $target 'dlls\main.dll')
        }
        Set-Content -LiteralPath (Join-Path $target 'enabled.txt') -Value '' -Encoding ascii
        Set-Content -LiteralPath (Join-Path $target 'dev.txt') -Value '' -Encoding ascii
        if ($kept) { Set-Content -LiteralPath $settings -Value $kept -NoNewline -Encoding ascii }
        else { Copy-Item -LiteralPath (Join-Path $root 'ue4ss\SimOverhaulMeters\settings.txt') -Destination $settings }
        Write-Host "Installed SimOverhaulMeters to $target$(if ($WithoutNative) { ' (no native helper)' } elseif ($Combined) { ' (combined native, test build)' })"
    }
    'Uninstall' {
        if ((Test-Path -LiteralPath $target) -and $PSCmdlet.ShouldProcess($target, 'Remove')) { Remove-Item -LiteralPath $target -Recurse -Force }
        Write-Host 'Uninstalled SimOverhaulMeters'
    }
    'Status' {
        if (-not (Test-Path -LiteralPath $target)) { Write-Host 'SimOverhaulMeters: not installed'; return }
        Get-ChildItem -LiteralPath $target -Recurse -File | ForEach-Object { "{0}  {1}" -f $_.FullName.Substring($target.Length + 1), (Get-FileHash -LiteralPath $_.FullName).Hash.Substring(0, 12) }
    }
}
