#Requires -Version 5.1
<#
.SYNOPSIS
    Regenerate the EasyRPG RTP assets under assets/ from the pinned upstream revision.

.DESCRIPTION
    RPG Maker 2000/2003 art stores transparency as a flat colour key rather than an
    alpha channel, so the upstream files cannot be used in Godot as-is. This wrapper
    runs tools/easyrtp_prepare.py, which keys those colours out, slices the character
    sheets into the 72x128 cells GBM2K expects, and writes one TileSet skeleton per
    chipset.

    The outputs are committed, so teammates never need to run this. Run it only when
    bumping the upstream pin or changing the conversion policy.

.PARAMETER Check
    Verify the committed assets match assets/easyrtp.manifest.json instead of
    regenerating. Exits non-zero on drift.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\prepare-easyrtp.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\prepare-easyrtp.ps1 -Check

.NOTES
    Requires Python 3 with Pillow:  python -m pip install pillow
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'easyrtp_prepare.py'

if (-not (Test-Path $script)) {
    throw "easyrtp_prepare.py not found next to this script."
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    throw "python was not found on PATH. Install Python 3, then: python -m pip install pillow"
}

& $python.Source -c "import PIL" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Pillow is not installed. Run: python -m pip install pillow"
}

# The generator writes UTF-8; keep Python from falling back to the console codepage.
$env:PYTHONUTF8 = '1'

$arguments = @($script)
if ($Check) { $arguments += '--check' }

& $python.Source @arguments
exit $LASTEXITCODE