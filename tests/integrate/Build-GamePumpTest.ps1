param(
    # vcvars64.bat of a Visual Studio 2022 C++ toolset; found with vswhere when not given.
    [string]$VcVars = ''
)
# Builds and runs tests/integrate/game_pump_test.cpp: the native game pump's logic with a fake Lua (no UE4SS needed).
# Small enough to run while the game is up; it runs at idle priority anyway.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $VcVars) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vs) { $VcVars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat' }
    }
}
if (-not $VcVars -or -not (Test-Path -LiteralPath $VcVars)) { throw 'No vcvars64.bat found; pass -VcVars.' }
$out = Join-Path $root 'build\game-pump-test'
New-Item -ItemType Directory -Force $out | Out-Null
$source = Join-Path $PSScriptRoot 'game_pump_test.cpp'
$exe = Join-Path $out 'game_pump_test.exe'
$cmd = "call `"$VcVars`" >nul && cl /nologo /std:c++latest /EHsc /W4 /O2 /DNOMINMAX `"$source`" /Fo`"$out\\`" /Fe`"$exe`""
$build = Start-Process -FilePath cmd.exe -ArgumentList '/c', $cmd -NoNewWindow -PassThru
$null = $build.Handle   # keeps the exit code readable after WaitForExit
try { $build.PriorityClass = 'Idle' } catch {}
$build.WaitForExit()
if ($build.ExitCode -ne 0) { throw "Build failed with exit code $($build.ExitCode)" }
& $exe
exit $LASTEXITCODE
