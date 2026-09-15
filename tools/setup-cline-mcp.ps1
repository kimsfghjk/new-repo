#Requires -Version 5.1
<#
.SYNOPSIS
    Registers the Godot AI MCP server for Cline CLI, pinned to this repo's plugin version.

.DESCRIPTION
    Cline CLI reads MCP servers from
        %USERPROFILE%\.cline\data\settings\cline_mcp_settings.json
    (verified against cline 3.0.61; the plugin's own "Configure" button writes the
    VS Code extension path instead, which Cline CLI never reads).

    This script merges one "godot-ai" entry into that file:
      * pins --from godot-ai==<version from addons/godot_ai/plugin.cfg>
      * injects PYTHONUTF8=1 (Korean Windows console/pipe encoding crash guard)
      * preserves every other server entry and writes a .bak backup

.PARAMETER HttpPort
    Backend HTTP port. Must match the Godot AI dock's port setting. Default 8000.

.PARAMETER WsPort
    Godot editor WebSocket port. Default 9500.

.PARAMETER DisableTelemetry
    Adds --disable-telemetry to the bridge command.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\setup-cline-mcp.ps1
#>
[CmdletBinding()]
param(
    [int]$HttpPort = 8000,
    [int]$WsPort = 9500,
    [switch]$DisableTelemetry
)

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# 1. Locate the plugin version that this repository pins.
# -----------------------------------------------------------------------------
$repoRoot = Split-Path -Parent $PSScriptRoot
$pluginCfg = Join-Path $repoRoot 'addons\godot_ai\plugin.cfg'
if (-not (Test-Path $pluginCfg)) {
    throw "addons/godot_ai/plugin.cfg not found under '$repoRoot'. Run this script from the game repository (tools\ lives next to addons\)."
}

$match = [regex]::Match((Get-Content $pluginCfg -Raw), 'version\s*=\s*"([^"]+)"')
if (-not $match.Success) {
    throw "Could not read the version line from $pluginCfg"
}
$pluginVersion = $match.Groups[1].Value
Write-Host "Godot AI plugin version in this repo: $pluginVersion"

# -----------------------------------------------------------------------------
# 2. Prerequisite checks.
# -----------------------------------------------------------------------------
if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
    throw "uvx was not found on PATH. Install uv first: https://docs.astral.sh/uv/getting-started/installation/"
}
if (-not (Get-Command cline -ErrorAction SilentlyContinue)) {
    Write-Warning "cline was not found on PATH. The config will still be written, but Cline will not read it until you install it: npm i -g cline"
}

# -----------------------------------------------------------------------------
# 3. Build the stdio bridge command.
# -----------------------------------------------------------------------------
$attachArgs = @(
    '--isolated', '--no-config', '--no-env-file', '--no-sources', '--no-build',
    '--index-strategy', 'first-index', '--keyring-provider', 'disabled',
    '--index', 'https://pypi.org/simple',
    '--default-index', 'https://pypi.org/simple',
    '--find-links', 'https://pypi.org/simple/godot-ai/',
    '--link-mode', 'copy',
    '--from', "godot-ai==$pluginVersion",
    'godot-ai', 'attach',
    '--port', "$HttpPort",
    '--ws-port', "$WsPort"
)
if ($DisableTelemetry) { $attachArgs += '--disable-telemetry' }

$entry = [pscustomobject][ordered]@{
    type        = 'stdio'
    command     = 'uvx'
    args        = $attachArgs
    env         = [pscustomobject][ordered]@{ PYTHONUTF8 = '1' }
    disabled    = $false
    autoApprove = @()
}

# -----------------------------------------------------------------------------
# 4. Merge into Cline CLI's MCP settings (everything else is preserved).
# -----------------------------------------------------------------------------
$settingsPath = Join-Path $env:USERPROFILE '.cline\data\settings\cline_mcp_settings.json'
$settingsDir = Split-Path -Parent $settingsPath
if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
    Write-Host "Created $settingsDir"
}

if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    Write-Host "Backup written: $settingsPath.bak"

    $raw = Get-Content $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $config = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
    }
    else {
        try {
            $config = $raw | ConvertFrom-Json
        }
        catch {
            throw "Existing $settingsPath is not valid JSON. Fix or delete it and re-run (backup: $settingsPath.bak)."
        }
        if ($null -eq $config.PSObject.Properties['mcpServers']) {
            $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
        }
    }
}
else {
    $config = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
}

# Replace an existing godot-ai entry (reconfigure is idempotent, never duplicated).
if ($null -ne $config.mcpServers.PSObject.Properties['godot-ai']) {
    $config.mcpServers.PSObject.Properties.Remove('godot-ai')
}
$config.mcpServers | Add-Member -NotePropertyName 'godot-ai' -NotePropertyValue $entry

$json = $config | ConvertTo-Json -Depth 12
# Write UTF-8 without BOM: a BOM breaks JSON.parse() in Node-based clients.
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Registered 'godot-ai' in $settingsPath"

# -----------------------------------------------------------------------------
# 5. Report.
# -----------------------------------------------------------------------------
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Open the project in Godot 4.7.2 mono and enable the Godot AI plugin (dock shows "connected").'
Write-Host '  2. Restart Cline so it picks up the new MCP server.'
Write-Host '  3. Verify: cline config mcp --json   -> should list godot-ai (stdio, disabled=false)'
Write-Host '  4. Try: "Show me the current scene hierarchy."'
