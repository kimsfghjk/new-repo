#Requires -Version 5.1
<#
.SYNOPSIS
    Stage everything, commit, and push to GitHub in one step.

.DESCRIPTION
    `git commit` only writes to YOUR local repository - GitHub sees nothing until
    you push. This helper chains the whole flow:

        git add -A  ->  git commit -m <Message>  ->  git push

    It never invents a commit message, and it reports "nothing to commit" instead
    of failing when the working tree already matches the last commit.

.PARAMETER Message
    Commit message (required). Use a prefix such as feat:/fix:/docs:/chore:.

.PARAMETER NoPush
    Commit locally only, without pushing (local checkpoint).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\publish.ps1 "feat: add title screen"

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\publish.ps1 "wip: checkpoint" -NoPush

.NOTES
    Pushing is what makes GitHub show the commit and start the CI workflow.
    Your credentials are cached by Git Credential Manager, so no login prompt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Message,

    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot 'project.godot'))) {
    throw "project.godot not found under '$repoRoot'. Run this from the game repository."
}

function Invoke-Git {
    param([string[]]$Arguments)
    # git writes progress to stderr; capture both streams so PowerShell does not
    # turn it into a terminating error.
    $out = & git -C $repoRoot @Arguments 2>&1
    return @{ Output = @($out); Code = $LASTEXITCODE }
}

& git -C $repoRoot add -A
$staged = @(& git -C $repoRoot diff --cached --name-only)

if ($staged.Count -eq 0) {
    Write-Host 'Nothing to commit - the working tree already matches the last commit.'
    $pending = @(& git -C $repoRoot log --oneline 'origin/main..HEAD' 2>$null)
    if ($pending.Count -gt 0) {
        Write-Host ('{0} commit(s) are local only - run "git push" (or rerun with -NoPush removed).' -f $pending.Count)
    }
    else {
        Write-Host 'Everything is already on GitHub.'
    }
    exit 0
}

Write-Host ('Staging {0} file(s)' -f $staged.Count)

$commit = Invoke-Git -Arguments @('commit', '-m', $Message)
$commit.Output | ForEach-Object { Write-Host $_ }
if ($commit.Code -ne 0) { exit $commit.Code }

if ($NoPush) {
    Write-Host 'Committed locally only (-NoPush). Run "git push" when you want it on GitHub.'
    exit 0
}

Write-Host 'Pushing to origin...'
$push = Invoke-Git -Arguments @('push')
$push.Output | ForEach-Object { Write-Host $_ }
if ($push.Code -ne 0) {
    Write-Host 'Push failed. If this branch has no upstream yet, run: git push -u origin main'
    exit $push.Code
}

Write-Host ''
Write-Host ('HEAD  : {0}' -f (& git -C $repoRoot rev-parse --short HEAD))
Write-Host ('GitHub: {0}' -f (& git -C $repoRoot rev-parse --short origin/main 2>$null))
Write-Host 'Done. GitHub shows the commit right away and the CI workflow starts on its own.'
exit 0
