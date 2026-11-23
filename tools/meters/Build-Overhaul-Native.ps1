param(
    # A folder holding custom-training\src\dllmain.cpp to use instead of this repo's (e.g. a newer worktree's native\).
    [string]$CustomTrainingNative = '',
    # The development variant: the meters part also registers for SimOverhaulMeters and Custom Training's registers
    # nowhere, so the DLL can be tried beside the development mods (native/overhaul/src/dllmain.cpp).
    [switch]$Test,
    [string]$BuildDirectory = ''
)
# Builds Simulator Upgrade Native (main.dll: every part's native helper in one DLL) against pinned UE4SS v3.0.1
# (c0a8d4c), as Battle Meters Native is built. Machine paths come from tools\meters\native-config.local.json (not in
# git): cmake, python, ue4ssWork, telemetryExporter. The release puts Release\main.dll in
# SimulatorUpgradeNative\dlls\ (it registers for the Lua mod SimulatorUpgrade). Don't run this during another
# session's game booking at normal priority.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $root ($(if ($Test) { 'build\overhaul-native-test' } else { 'build\overhaul-native' })) }
$configPath = Join-Path $PSScriptRoot 'native-config.local.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing $configPath; see tools\meters\Build-Native.ps1." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$work = $config.ue4ssWork
$sourceRoot = "$work\official-ue4ss-v3.0.1\UE4SSCPPTemplate\RE-UE4SS"
$parts = @()
if ($CustomTrainingNative) {
    if (-not (Test-Path -LiteralPath (Join-Path $CustomTrainingNative 'custom-training\src\dllmain.cpp'))) { throw "No custom-training\src\dllmain.cpp under $CustomTrainingNative" }
    $parts += (Resolve-Path $CustomTrainingNative).Path.Replace('\', '/')
}
$parts += (Join-Path $root 'native').Replace('\', '/')
New-Item -ItemType Directory -Force $BuildDirectory | Out-Null
$interfaceRoot = Join-Path $BuildDirectory 'installed-interface'
& $config.python (Join-Path $config.telemetryExporter 'Prepare-InstalledUe4ssInterface.py') $sourceRoot $interfaceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the pinned installed-build interface.' }
& $config.cmake -S (Join-Path $root 'native\overhaul') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 `
    "-DNATIVE_PARTS=$($parts -join ';')" `
    "-DSIM_OVERHAUL_COMBINED_TEST=$(if ($Test) { 'ON' } else { 'OFF' })" `
    "-DINSTALLED_INTERFACE=$interfaceRoot" `
    "-DUE4SS_SOURCE=$sourceRoot" `
    "-DUEPSEUDO_SOURCE=$work\official-ue4ss-v3.0.1\UEPseudo-authenticated" `
    "-DIMGUI_SOURCE=$work\official-ue4ss-v3.0.1\header-deps\imgui" `
    "-DIMGUI_TEXT_EDIT_SOURCE=$work\official-ue4ss-v3.0.1\header-deps\ImGuiColorTextEdit" `
    "-DZYDIS_SOURCE=$sourceRoot/../../header-deps/zydis-v4.1.0" `
    "-DUE4SS_IMPORT_LIB=$work\BenchSlot2OfficialNoOp\UE4SS.lib"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE" }
& $config.cmake --build $BuildDirectory --config Release -- /m
if ($LASTEXITCODE -ne 0) { throw "CMake build failed with exit code $LASTEXITCODE" }
$dll = Join-Path $BuildDirectory 'Release\main.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "Build did not produce $dll" }
"parts: $($parts -join ', ')"
Get-FileHash -Algorithm SHA256 -LiteralPath $dll
