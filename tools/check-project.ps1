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

.PARAMETER LogFile
    Reuse an existing Godot log instead of launching the editor (for CI
    debugging and for validating the classification policy).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1 -GodotExe "D:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
#>
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [string]$ProjectPath = '',
    [string]$LogFile = ''
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

$reusedLog = $false
if ($LogFile) {
    if (-not (Test-Path $LogFile)) { throw "-LogFile not found: $LogFile" }
    Write-Host "Reusing log (classification only, Godot is not launched): $LogFile"
    $output = Get-Content $LogFile -Raw
    $exitCode = 0
    $reusedLog = $true
}
else {
    $exe = Resolve-GodotExe -Explicit $GodotExe
    Write-Host "Godot : $exe"
    Write-Host "Project: $ProjectPath"
    Write-Host 'Running headless import + script load check...'

    $output = & $exe --headless --path $ProjectPath --editor --quit 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}

# Strip ANSI colour codes so the log is readable in CI.
$clean = [regex]::Replace($output, "\x1B\[[0-9;]*[a-zA-Z]", '')
$lines = $clean -split "`r?`n"

# Classification policy (mirrors .github/workflows/ci.yml):
#   HARD   -> parse errors, load failures, and script errors in OUR code: fail
#   VENDOR -> script errors whose stack frame is inside addons/ or third_party/: warn only
# Why: vendored addons can log editor-only errors on a machine without user editor
# settings (dialogue_manager reads "interface/editor/code_font_size", which is unset
# in a fresh headless run). The game is unaffected and we do not patch vendored code,
# so it must not fail the gate. Parse/load failures still always fail.
$hardPattern = 'Parse Error|ERROR:|Failed to load|Cannot open file|Unable to load'
# Only used when classifying a saved CI log: the runner echoes our own workflow
# script into the log, and those lines contain the patterns below.
$scriptEchoPattern = '::(error|warning)::|##\[(error|warning)\]|\$RUNNER_TEMP|^\s*(echo|if|grep|cat|awk|fi|then|sed)\s'
$hard = New-Object System.Collections.Generic.List[string]
$vendor = New-Object System.Collections.Generic.List[string]

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -match 'MCP \| plugin disabled in headless mode') { continue }
    if ($line -match $scriptEchoPattern) { continue }

    # SCRIPT ERROR must be classified by its stack frame BEFORE the generic
    # pattern below, because "SCRIPT ERROR:" also matches 'ERROR:'.
    if ($line -match 'SCRIPT ERROR') {
        # Look ahead a few lines for the "at: ..." frame. In the editor's own
        # output it is the next line; a GitHub job log interleaves annotations
        # and drops frames, so allow up to three and treat a missing frame in a
        # reused log as a warning (the lossy format cannot prove the origin).
        $frame = ''
        for ($j = $i + 1; $j -le [Math]::Min($i + 3, $lines.Count - 1); $j++) {
            if ($lines[$j] -match '^\s*at: ') { $frame = $lines[$j].Trim(); break }
        }
        $isParse = $line -match 'Parse Error'
        $entry = '{0}  [{1}]' -f $line.Trim(), $frame
        $vendored = (-not $isParse) -and ($frame -match '(addons|third_party)/')
        if (-not $vendored -and -not $isParse -and $frame -eq '' -and $reusedLog) {
            $entry = $entry + '  (no frame; reused log)'
            $vendored = $true
        }
        if ($vendored) { $vendor.Add($entry) } else { $hard.Add($entry) }
        continue
    }
    if ($line -match $hardPattern) {
        $hard.Add($line.Trim())
        continue
    }
}

if ($exitCode -ne 0 -or $hard.Count -gt 0) {
    Write-Host ''
    Write-Host 'FAILED'
    if ($exitCode -ne 0) { Write-Host "Godot exited with code $exitCode" }
    $hard | Select-Object -First 40 | ForEach-Object { Write-Host "  $_" }
    if ($vendor.Count -gt 0) { Write-Host ('  ({0} vendored warning(s) also present)' -f $vendor.Count) }
    exit 1
}

Write-Host ''
if ($vendor.Count -gt 0) {
    Write-Host ('WARN - {0} script error(s) inside vendored addons (ignored; see third_party/README.md):' -f $vendor.Count)
    $vendor | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
}
Write-Host 'PASS - project imports; no load or parse errors in project code.'
exit 0
