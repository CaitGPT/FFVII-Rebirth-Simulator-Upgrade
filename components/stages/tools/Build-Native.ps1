param(
    [Parameter(Mandatory)][string]$BuildDirectory,
    # Machine paths: a JSON file with CMake, Ue4ssSource, UEPseudoSource, ImguiSource, ImguiTextEditSource and
    # Ue4ssImportLib, the same keys Junon Colosseum's build uses (its build-config.local.json works as it is).
    [Parameter(Mandatory)][string]$ConfigPath,
    # Path to a FFVII-Rebirth-Junon-Colosseum checkout, to regenerate native/src/main.cpp from its helper first.
    [string]$JunonCheckout=''
)
# Builds the level helper (Release\main.dll) from native/. An install puts it at
# End\Binaries\Win64\ue4ss\Mods\SimulatorStages\dlls\main.dll. It is tied to UE4SS 3.0.1, like Junon Colosseum's.
# Don't run this during another session's game booking: the compile competes with the game for CPU.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($JunonCheckout){
    & python (Join-Path $PSScriptRoot 'make_helper_source.py') $JunonCheckout
    if($LASTEXITCODE -ne 0){throw 'Generating main.cpp failed'}
}
$config=@{}
(Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $config[$_.Name]=$_.Value }
function Setting([string]$key) {
    if($config[$key]){return [string]$config[$key]}
    throw "$key is missing from $ConfigPath"
}
$cmakeExe=Setting 'CMake'
& $cmakeExe -S (Join-Path $root 'native') -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 `
    "-DUE4SS_SOURCE=$(Setting 'Ue4ssSource')" `
    "-DUEPSEUDO_SOURCE=$(Setting 'UEPseudoSource')" `
    "-DIMGUI_SOURCE=$(Setting 'ImguiSource')" `
    "-DIMGUI_TEXT_EDIT_SOURCE=$(Setting 'ImguiTextEditSource')" `
    "-DUE4SS_IMPORT_LIB=$(Setting 'Ue4ssImportLib')"
if($LASTEXITCODE -ne 0){throw 'Configure failed'}
& $cmakeExe --build $BuildDirectory --config Release
if($LASTEXITCODE -ne 0){throw 'Compilation failed'}
Get-FileHash -LiteralPath (Join-Path $BuildDirectory 'Release\main.dll') -Algorithm SHA256
