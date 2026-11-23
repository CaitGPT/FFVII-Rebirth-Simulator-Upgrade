[CmdletBinding(SupportsShouldProcess)]
param(
    # Build: apply a party test spec on top of the Colosseum table the game currently uses and pack
    # SimOverhaulPartyTest_9300_P. Install/Uninstall: copy it into, or out of, the game's ~mods. Status: what is installed.
    # Development only: the party workstream ships through custom-training's pak, never this one.
    [ValidateSet('Build', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Build',
    [string]$Spec = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'data\party\test-vanilla-copy.json'),
    # The Colosseum table to build on. Default: Junon Colosseum's installed build (vanilla Epic 1.005 + Training
    # Dummy + Junon rows), so the test pak hides no installed course.
    [string]$BaseColosseum = 'D:\FF7RebirthModding\Mods\JunonColosseumFoyer\20261113-epic-1.005-foyer\Staging\End\Content\DataObject\Resident\Colosseum.uasset',
    [string]$GameRoot = 'D:\Epic Games\FinalFantasyVIIRebirth',
    [string]$UnrealReZen = 'D:\FF7RebirthModding\Tools\UnrealReZen\UnrealReZen.exe',
    [string]$BuildRoot = 'D:\FF7RebirthModding\Mods\SimulatorOverhaul\party-build'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
# Loads after JunonColosseum_999_P (which also replaces Colosseum); NoPopups_JunonCompat_9999_P does not touch Colosseum.
$PackageName = 'SimOverhaulPartyTest_9300_P'
$Paks = Join-Path $GameRoot 'End\Content\Paks'
$ModsDir = Join-Path $Paks '~mods'
$Package = Join-Path $BuildRoot 'Package'
$BuilderBin = Join-Path $BuildRoot 'DataBuilderBin'
$Builder = Join-Path $BuilderBin 'DataBuilder.dll'
$HeaderSource = Join-Path $Paks 'pakchunk4optional-WindowsNoEditor.ucas'
$KnownHeaders = [ordered]@{ 'epic-1.005' = '8C-06-00-97-7A-88-97-78-D3-00' }

function Get-Triplet([string]$Directory) { '.pak', '.ucas', '.utoc' | ForEach-Object { Join-Path $Directory ($PackageName + $_) } }
function Read-Bytes([string]$Path, [int]$Count) {
    $bytes = New-Object byte[] $Count
    $stream = [IO.File]::OpenRead($Path)
    try { if ($stream.Read($bytes, 0, $Count) -ne $Count) { throw "Too short: $Path" } } finally { $stream.Dispose() }
    , $bytes
}
# Same check as No Popups' build: the 10 header bytes written over the .ucas must spoil only UnrealReZen's own
# container-header block, never the table's.
function Assert-TableBlockClear([string]$Toc) {
    $t = [IO.File]::ReadAllBytes($Toc)
    $entries = [BitConverter]::ToInt32($t, 24); $blocks = [BitConverter]::ToInt32($t, 28)
    $start = 144 + $entries * 22
    for ($i = 1; $i -lt $blocks; $i++) {
        $at = $start + $i * 12
        $offset = 0L; for ($j = 0; $j -lt 5; $j++) { $offset = $offset -bor ([long]$t[$at + $j] -shl (8 * $j)) }
        if ($offset -lt 10) { throw "Block $i starts at $offset, inside the 10 bytes the header step overwrites" }
    }
}

function Invoke-Build {
    $staging = Join-Path $BuildRoot 'Staging'; $base = Join-Path $BuildRoot 'Base'
    foreach ($dir in $staging, $Package, $base) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $baseTables = Join-Path $base 'End\Content\DataObject\Resident'
    New-Item -ItemType Directory -Path $baseTables -Force | Out-Null
    Copy-Item -LiteralPath $BaseColosseum -Destination (Join-Path $baseTables 'Colosseum.uasset')

    & dotnet build (Join-Path $ModRoot 'tools\DataBuilder\src') -c Release -o $BuilderBin --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder build failed ($LASTEXITCODE)" }
    & dotnet $Builder build $Spec $base $staging
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder failed ($LASTEXITCODE); nothing was packed" }

    Push-Location (Split-Path $UnrealReZen -Parent)
    try {
        & $UnrealReZen --content-path $staging --compression-format Zlib --engine-version GAME_UE4_26 `
            --game-dir $Paks --output-path (Join-Path $Package "$PackageName.utoc")
        if ($LASTEXITCODE -ne 0) { throw "UnrealReZen failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
    foreach ($path in Get-Triplet $Package) { if (-not (Test-Path -LiteralPath $path)) { throw "UnrealReZen did not write $path" } }

    Assert-TableBlockClear (Join-Path $Package "$PackageName.utoc")
    $header = Read-Bytes $HeaderSource 10
    $headerText = [BitConverter]::ToString($header)
    $headerBuild = ($KnownHeaders.GetEnumerator() | Where-Object { $_.Value -eq $headerText } | Select-Object -First 1).Key
    if (-not $headerBuild) { throw "$HeaderSource starts with $headerText, not a Rebirth header we have built against" }
    $ucas = Join-Path $Package "$PackageName.ucas"
    $stream = [IO.File]::Open($ucas, 'Open', 'Write', 'None')
    try { $stream.Write($header, 0, 10) } finally { $stream.Dispose() }

    [ordered]@{
        PackageName = $PackageName; BuiltAt = (Get-Date).ToString('o'); ContainerHeader = $headerBuild
        Spec = [ordered]@{ Path = $Spec; SHA256 = (Get-FileHash -LiteralPath $Spec).Hash }
        Base = [ordered]@{ Path = $BaseColosseum; SHA256 = (Get-FileHash -LiteralPath $BaseColosseum).Hash }
        Files = @(Get-Triplet $Package | ForEach-Object { [ordered]@{ Name = Split-Path $_ -Leaf; SHA256 = (Get-FileHash -LiteralPath $_).Hash } })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Package 'manifest.json') -Encoding utf8
    Write-Host "Built $PackageName in $Package"
}

switch ($Mode) {
    'Build' { Invoke-Build }
    'Install' {
        foreach ($path in Get-Triplet $Package) {
            if (-not (Test-Path -LiteralPath $path)) { throw "Build first: $path is missing" }
            if ($PSCmdlet.ShouldProcess($ModsDir, "Install $(Split-Path $path -Leaf)")) { Copy-Item -LiteralPath $path -Destination $ModsDir -Force }
        }
        Write-Host "Installed $PackageName"
    }
    'Uninstall' {
        foreach ($path in Get-Triplet $ModsDir) {
            if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove')) { Remove-Item -LiteralPath $path }
        }
        Write-Host "Uninstalled $PackageName"
    }
    'Status' {
        foreach ($path in Get-Triplet $ModsDir) {
            if (Test-Path -LiteralPath $path) { Write-Host "$path $((Get-FileHash -LiteralPath $path).Hash)" } else { Write-Host "$path (not installed)" }
        }
    }
}
