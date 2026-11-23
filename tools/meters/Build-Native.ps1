param(
    [string]$BuildDirectory = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\meters-native')
)
# Builds the meters native helper (main.dll, a copy of Battle Meters Native) against pinned UE4SS v3.0.1 (c0a8d4c) sources, as Battle Meters Native is
# built. Machine paths come from tools\meters\native-config.local.json (not in git), the same keys as Battle
# Meters' tools\build-config.local.json: cmake, python, ue4ssWork, telemetryExporter.
# The output, Release\main.dll, goes in ue4ss\SimOverhaulMetersNative\dlls\.
# Don't run this during another session's game booking: the compile competes with the game for CPU.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$configPath = Join-Path $PSScriptRoot 'native-config.local.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing $configPath; see the comments at the top of this script." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$work = $config.ue4ssWork
$sourceRoot = "$work\official-ue4ss-v3.0.1\UE4SSCPPTemplate\RE-UE4SS"
New-Item -ItemType Directory -Force $BuildDirectory | Out-Null
$interfaceRoot = Join-Path $BuildDirectory 'installed-interface'
& $config.python (Join-Path $config.telemetryExporter 'Prepare-InstalledUe4ssInterface.py') $sourceRoot $interfaceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the pinned installed-build interface.' }
& $config.cmake -S (Join-Path $root 'native\meters') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 `
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
Get-FileHash -Algorithm SHA256 -LiteralPath $dll
