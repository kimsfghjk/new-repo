#Requires -Version 5.1
<#
.SYNOPSIS
    Pre-push / CI check: opens the project headlessly and fails on load or parse errors.

.DESCRIPTION
    Runs `Godot --headless --path <repo> --editor --quit`, strips ANSI codes from the
    output and fails the build when script/resource errors appear.

    The Godot AI plugin prints "MCP | plugin disabled in headless mode" and never
    starts its server here, so this can run while an editor (or an MCP client) is
    connected without fighting over ports 8000/9500.

    Engine resolution order:
      1. -GodotExe <path>
      2. $env:GODOT_BIN
      3. godot / godot4 on PATH
      4. Godot* folders one level under C:\ and D:\ containing *_console.exe

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1 -GodotExe "D:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
#>
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$ProjectPath = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = $repoRoot }
if (-not (Test-Path (Join-Path $ProjectPath 'project.godot'))) {
    throw "'$ProjectPath' is not a Godot project (project.godot not found)."
}

function Resolve-GodotExe {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "-GodotExe '$Explicit' does not exist." }
        return (Resolve-Path $Explicit).Path
    }
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return (Resolve-Path $env:GODOT_BIN).Path
    }
    foreach ($name in @('godot', 'godot4', 'godot.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($root in @('C:\', 'D:\', 'C:\Program Files')) {
        $dirs = Get-ChildItem -Path $root -Directory -Filter 'Godot*' -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            $exe = Get-ChildItem -Path $dir.FullName -Filter '*_console.exe' -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }
    throw "Godot executable not found. Pass -GodotExe <path> or set `$env:GODOT_BIN."
}

$exe = Resolve-GodotExe -Explicit $GodotExe
Write-Host "Godot : $exe"
Write-Host "Project: $ProjectPath"
Write-Host 'Running headless import + script load check...'

$output = & $exe --headless --path $ProjectPath --editor --quit 2>&1 | Out-String
$exitCode = $LASTEXITCODE

# Strip ANSI colour codes so the log is readable in CI.
$clean = [regex]::Replace($output, "\x1B\[[0-9;]*[a-zA-Z]", '')
$lines = $clean -split "`r?`n"

$errorPattern = 'SCRIPT ERROR|Parse Error|ERROR:|Failed to load|Cannot open file|Unable to load'
$problems = $lines | Where-Object { $_ -match $errorPattern -and $_ -notmatch 'MCP \| plugin disabled in headless mode' }

if ($exitCode -ne 0 -or $problems.Count -gt 0) {
    Write-Host ''
    Write-Host 'FAILED'
    if ($exitCode -ne 0) { Write-Host "Godot exited with code $exitCode" }
    $problems | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host ''
Write-Host 'PASS - project imports and all scripts parse cleanly.'
exit 0
