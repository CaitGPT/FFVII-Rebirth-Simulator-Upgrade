[CmdletBinding(SupportsShouldProcess)]
param(
    # Build: apply the specs and pack SimOverhaulCustomTraining_9200_P.
    # Install/Uninstall: copy the pak (and the UE4SS mod folder, when built) into, or out of, the game.
    # Status: show what is installed.
    [ValidateSet('Build', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Build',
    # Spec files, relative to the repo root. The default is the course itself; the probe is data\custom-training\probe.json.
    [string[]]$Spec = @('data\custom-training.json', 'data\custom-training\generated.json', 'data\party.json'),
    # Machine paths, JSON (default tools\custom-training\build-config.local.json; see build-config.example.json).
    [string]$ConfigPath = $null,
    # The pak's name. The release ships SimulatorUpgrade_9200_P (and SimulatorUpgrade_JunonCompat_9200_P).
    [string]$PackageName = 'SimOverhaulCustomTraining_9200_P',
    # The folder holding the five tables to build on (End\Content\DataObject\Resident layout not needed: the
    # .uasset files themselves). Default: the vanilla export. For players who also have Junon Colosseum, its own
    # built tables (they carry its courses, and Training Dummy's rows it was built on), so its courses stay.
    [string]$BaseTables = $null
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'build-config.local.json' }
$Config = [ordered]@{
    GameRoot    = $null  # FF7 Rebirth install folder
    VanillaRoot = $null  # export root containing End\Content\DataObject\Resident (the Epic 1.005 export)
    UnrealReZen = $null  # UnrealReZen.exe
    BuildRoot   = (Join-Path $ModRoot 'build\custom-training')
}
if (Test-Path -LiteralPath $ConfigPath) {
    $local = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    foreach ($p in $local.PSObject.Properties) { $Config[$p.Name] = $p.Value }
}
if (-not $Config.GameRoot) { throw "Set GameRoot in $ConfigPath (see build-config.example.json)." }

# Loads after Junon Colosseum (999) and Training Dummy, which replace the same tables (docs/COORDINATION.md).
if ($PackageName -notmatch '^[A-Za-z0-9_]+_P$') { throw "PackageName must end in _P: $PackageName" }
$LuaModName = 'SimOverhaulCustomTraining'

$CourseRow = 'COL99_SimOverhaul_CT_Custom_vr'
$Tables = @('Colosseum', 'EnemyTerritory', 'EnemyTerritoryLevel', 'ColosseumPositionData', 'EnemyParameter')
$SpecFiles = @($Spec | ForEach-Object { Join-Path $ModRoot $_ } | Where-Object { Test-Path -LiteralPath $_ })
if (-not $SpecFiles) { throw "None of the spec files exist: $($Spec -join ', ')" }
$SpecOut = Join-Path $Config.BuildRoot 'spec.json'
$BuilderBin = Join-Path $Config.BuildRoot 'DataBuilderBin'
$Builder = Join-Path $BuilderBin 'DataBuilder.dll'
$Paks = Join-Path $Config.GameRoot 'End\Content\Paks'
$ModsDir = Join-Path $Paks '~mods'
$Ue4ssMods = Join-Path $Config.GameRoot 'End\Binaries\Win64\ue4ss\Mods'
$Package = Join-Path $Config.BuildRoot 'Package'
if ($PackageName -ne 'SimOverhaulCustomTraining_9200_P') { $Package = Join-Path $Config.BuildRoot "Package-$PackageName" }
$LuaSource = Join-Path $ModRoot "ue4ss\$LuaModName"
# Rebirth's own containers start with these 10 bytes. They differ per game build (No Popups' list).
$HeaderSource = Join-Path $Paks 'pakchunk4optional-WindowsNoEditor.ucas'
$KnownHeaders = [ordered]@{
    'steam-2026-07' = '8C-06-00-97-A6-88-97-A4-D3-00'
    'epic-1.005'    = '8C-06-00-97-7A-88-97-78-D3-00'
}

function Get-Triplet([string]$Directory) {
    '.pak', '.ucas', '.utoc' | ForEach-Object { Join-Path $Directory ($PackageName + $_) }
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Read-Bytes([string]$Path, [int]$Count) {
    $bytes = New-Object byte[] $Count
    $stream = [IO.File]::OpenRead($Path)
    try { if ($stream.Read($bytes, 0, $Count) -ne $Count) { throw "Too short: $Path" } } finally { $stream.Dispose() }
    , $bytes
}

# UnrealReZen's .utoc lists its 44-byte container header as block 0; the header step below overwrites the first 10
# bytes of the .ucas, so every table block must start after them (No Popups, 2026-11-12).
function Assert-TableBlockClear([string]$Toc) {
    $t = [IO.File]::ReadAllBytes($Toc)
    $entries = [BitConverter]::ToInt32($t, 24); $blocks = [BitConverter]::ToInt32($t, 28)
    $start = 144 + $entries * 22
    for ($i = 1; $i -lt $blocks; $i++) {
        $at = $start + $i * 12
        $offset = 0L; for ($j = 0; $j -lt 5; $j++) { $offset = $offset -bor ([long]$t[$at + $j] -shl (8 * $j)) }
        if ($offset -lt 10) { throw "Block $i starts at $offset, inside the 10 bytes the header step overwrites" }
    }
    $first = 0L; for ($j = 0; $j -lt 5; $j++) { $first = $first -bor ([long]$t[$start + $j] -shl (8 * $j)) }
    $usize = $t[$start + 8] -bor ($t[$start + 9] -shl 8) -bor ($t[$start + 10] -shl 16)
    if ($first -ne 0 -or $usize -gt 64) { throw "Block 0 is not UnrealReZen's small container header (offset $first, $usize bytes)" }
}

function Invoke-Build {
    foreach ($key in 'VanillaRoot', 'UnrealReZen') {
        if (-not $Config[$key]) { throw "Set $key in $ConfigPath (see build-config.example.json)." }
    }
    $staging = Join-Path $Config.BuildRoot 'Staging'
    $base = Join-Path $Config.BuildRoot 'Base'
    foreach ($dir in $staging, $Package, $base) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $baseDir = Join-Path $base 'End\Content\DataObject\Resident'
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
    $from = if ($BaseTables) { $BaseTables } else { Join-Path $Config.VanillaRoot 'End\Content\DataObject\Resident' }
    foreach ($table in $Tables) {
        Copy-Item -LiteralPath (Join-Path $from "$table.uasset") -Destination $baseDir
    }
    Write-Host "Tables from $from"

    # One spec from all spec files (whole-line // comments allowed); a row changed by two files is refused.
    # A spec file may also carry "courseRow": {"set": {...}}: values for the Custom Training course row, which this
    # workstream owns (data/party.json from the party workstream uses it; docs/COORDINATION.md).
    $byAsset = [ordered]@{}
    $courseRowSets = @()
    foreach ($file in $SpecFiles) {
        $json = ((Get-Content -LiteralPath $file) | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        $parsed = $json | ConvertFrom-Json
        foreach ($table in @($parsed.tables | Where-Object { $_ })) {
            if (-not $byAsset.Contains($table.asset)) { $byAsset[$table.asset] = [System.Collections.ArrayList]@() }
            foreach ($row in @($table.rows)) { [void]$byAsset[$table.asset].Add($row) }
        }
        if ($parsed.PSObject.Properties['courseRow'] -and $parsed.courseRow.set) { $courseRowSets += , @($file, $parsed.courseRow.set) }
    }
    foreach ($pair in $courseRowSets) {
        $row = @($byAsset['DataObject/Resident/Colosseum.uasset'] | Where-Object { $_.name -eq $CourseRow })
        if ($row.Count -ne 1) { throw "$($pair[0]) sets values on $CourseRow, but no spec defines that row" }
        foreach ($p in $pair[1].PSObject.Properties) {
            $row[0].set | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
            Write-Host "Course row: $($p.Name) from $(Split-Path $pair[0] -Leaf)"
        }
    }
    $merged = @()
    foreach ($asset in $byAsset.Keys) {
        $names = @($byAsset[$asset] | ForEach-Object { $_.name })
        if (@($names | Select-Object -Unique).Count -ne $names.Count) { throw "Two spec files change the same row of $asset" }
        $merged += [ordered]@{ asset = $asset; rows = @($byAsset[$asset]) }
    }
    [ordered]@{ tables = $merged } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SpecOut -Encoding utf8

    & dotnet build (Join-Path $ModRoot 'tools\DataBuilder\src') -c Release -o $BuilderBin --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder build failed ($LASTEXITCODE)" }
    & dotnet $Builder build $SpecOut $base $staging
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder failed ($LASTEXITCODE); nothing was packed" }

    # Pack only the tables the specs changed; show which rows differ from vanilla.
    $changed = @($merged | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.asset) })
    foreach ($table in $Tables) {
        $relative = "End\Content\DataObject\Resident\$table.uasset"
        if ($changed -notcontains $table) { Remove-Item -LiteralPath (Join-Path $staging $relative) -ErrorAction SilentlyContinue; continue }
        @(& dotnet $Builder compare (Join-Path $base $relative) (Join-Path $staging $relative)) | Write-Host
    }

    Push-Location (Split-Path $Config.UnrealReZen -Parent)
    try {
        & $Config.UnrealReZen --content-path $staging --compression-format Zlib --engine-version GAME_UE4_26 `
            --game-dir $Paks --output-path (Join-Path $Package "$PackageName.utoc")
        if ($LASTEXITCODE -ne 0) { throw "UnrealReZen failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    Assert-TableBlockClear (Join-Path $Package "$PackageName.utoc")
    $header = Read-Bytes $HeaderSource 10
    $headerText = [BitConverter]::ToString($header)
    $headerBuild = ($KnownHeaders.GetEnumerator() | Where-Object { $_.Value -eq $headerText } | Select-Object -First 1).Key
    if (-not $headerBuild) { throw "$HeaderSource starts with $headerText, which is not a Rebirth header we have built against" }
    Write-Host "Container header: $headerBuild"
    $ucas = Join-Path $Package "$PackageName.ucas"
    $stream = [IO.File]::Open($ucas, 'Open', 'Write', 'None')
    try { $stream.Write($header, 0, 10) } finally { $stream.Dispose() }
    if ([BitConverter]::ToString((Read-Bytes $ucas 10)) -ne $headerText) { throw "Header step did not apply to $ucas" }

    $manifest = [ordered]@{
        PackageName = $PackageName
        BuiltAt = (Get-Date).ToString('o')
        BaseTables = $from
        Specs = @($SpecFiles | ForEach-Object { [ordered]@{ Path = $_.Substring($ModRoot.Length + 1); SHA256 = (Get-Sha $_) } })
        Assets = @(Get-ChildItem -LiteralPath $staging -Recurse -File | ForEach-Object {
            [ordered]@{ Path = $_.FullName.Substring($staging.Length + 1); SHA256 = (Get-Sha $_.FullName) } })
        Files = @(Get-Triplet $Package | ForEach-Object {
            [ordered]@{ Name = Split-Path $_ -Leaf; Length = (Get-Item -LiteralPath $_).Length; SHA256 = (Get-Sha $_) } })
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Package 'manifest.json') -Encoding utf8
    Write-Host "Built $PackageName in $Package"
}

function Assert-GameClosed {
    if (Get-Process -Name 'ff7rebirth_' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
}

function Invoke-Install {
    Assert-GameClosed
    $manifest = Get-Content -LiteralPath (Join-Path $Package 'manifest.json') -Raw | ConvertFrom-Json
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    foreach ($file in $manifest.Files) {
        $source = Join-Path $Package $file.Name
        if ((Get-Sha $source) -ne $file.SHA256) { throw "Built $($file.Name) does not match its manifest" }
        if ($PSCmdlet.ShouldProcess($ModsDir, "Copy $($file.Name)")) {
            Copy-Item -LiteralPath $source -Destination $ModsDir -Force
            if ((Get-Sha (Join-Path $ModsDir $file.Name)) -ne $file.SHA256) { throw "Installed $($file.Name) does not match the build" }
        }
    }
    Write-Host "Installed $PackageName"
    # The UE4SS mod: scripts are replaced, the player's settings.txt and enabled.txt are kept.
    if (Test-Path -LiteralPath (Join-Path $LuaSource 'Scripts')) {
        $target = Join-Path $Ue4ssMods $LuaModName
        New-Item -ItemType Directory -Path (Join-Path $target 'Scripts') -Force | Out-Null
        Get-ChildItem -LiteralPath (Join-Path $target 'Scripts') -Filter *.lua | Remove-Item
        Copy-Item -Path (Join-Path $LuaSource 'Scripts\*.lua') -Destination (Join-Path $target 'Scripts')
        foreach ($keep in 'settings.txt', 'enabled.txt') {
            $from = Join-Path $LuaSource $keep
            if ((Test-Path -LiteralPath $from) -and -not (Test-Path -LiteralPath (Join-Path $target $keep))) { Copy-Item -LiteralPath $from -Destination $target }
        }
        Write-Host "Installed UE4SS mod $LuaModName"
        # The difficulty helper (tools\custom-training\Build-Native.ps1) goes in the same folder, as Simulator Stages
        # ships its helper: UE4SS loads dlls\main.dll as a C++ mod of the same name.
        $dll = Join-Path $ModRoot 'build\custom-training-native\Release\main.dll'
        if (Test-Path -LiteralPath $dll) {
            New-Item -ItemType Directory -Path (Join-Path $target 'dlls') -Force | Out-Null
            Copy-Item -LiteralPath $dll -Destination (Join-Path $target 'dlls\main.dll') -Force
            Write-Host "Installed the difficulty helper $(Get-Sha $dll)"
        }
        if (Test-Path -LiteralPath (Join-Path $LuaSource 'dev.txt')) { Copy-Item -LiteralPath (Join-Path $LuaSource 'dev.txt') -Destination $target -Force }
    }
}

function Invoke-Uninstall {
    Assert-GameClosed
    foreach ($path in Get-Triplet $ModsDir) {
        if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove')) { Remove-Item -LiteralPath $path }
    }
    $enabled = Join-Path $Ue4ssMods "$LuaModName\enabled.txt"
    if ((Test-Path -LiteralPath $enabled) -and $PSCmdlet.ShouldProcess($enabled, 'Remove')) { Remove-Item -LiteralPath $enabled }
    Write-Host "Removed $PackageName (and disabled $LuaModName if it was installed)"
}

function Show-Status {
    foreach ($path in Get-Triplet $ModsDir) {
        if (Test-Path -LiteralPath $path) { "$(Split-Path $path -Leaf) $(Get-Sha $path)" } else { "missing: $path" }
    }
    $mod = Join-Path $Ue4ssMods $LuaModName
    if (Test-Path -LiteralPath $mod) { "UE4SS mod: $mod (enabled: $(Test-Path -LiteralPath (Join-Path $mod 'enabled.txt')))" }
}

switch ($Mode) {
    'Build' { Invoke-Build }
    'Install' { Invoke-Install }
    'Uninstall' { Invoke-Uninstall }
    'Status' { Show-Status }
}
