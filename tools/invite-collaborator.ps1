#Requires -Version 5.1
<#
.SYNOPSIS
    Invites GitHub users to this repository as collaborators.

.DESCRIPTION
    Resolves the repository from the 'origin' remote and obtains a token from
    $env:GITHUB_TOKEN / $env:GH_TOKEN, falling back to the token Git Credential
    Manager already holds for github.com (the one `git push` uses).

    The token is kept in memory only - it is never written to disk and never
    printed. Invitees receive a GitHub email invitation and must accept it.

.PARAMETER Username
    One or more GitHub usernames to invite (comma separated).

.PARAMETER Permission
    pull | triage | push | maintain | admin    (default: push)

.PARAMETER Repo
    Optional 'owner/name' override. Defaults to the 'origin' remote of the
    repository this script lives in, so it works from any working directory.

.PARAMETER DryRun
    Print the API calls without performing them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\invite-collaborator.ps1 -Username alice,bob

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tools\invite-collaborator.ps1 -Username lead -Permission maintain

.NOTES
    Requires admin rights on the repository. The account must have a token with
    'repo' scope (classic) or 'Administration: write' (fine-grained).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Username,

    [ValidateSet('pull', 'triage', 'push', 'maintain', 'admin')]
    [string]$Permission = 'push',

    [string]$Repo = '',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# PowerShell's -File argument binding keeps "a,b" as one literal string, so accept
# both comma separated and repeated values, and drop blanks.
$Username = @($Username |
    ForEach-Object { $_ -split ',' } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' })
if ($Username.Count -eq 0) {
    throw "No usernames supplied. Example: -Username alice,bob"
}

function Get-RepoSlug {
    param([string]$Override)

    if ($Override) {
        if ($Override -notmatch '^[^/]+/[^/]+$') { throw "-Repo must look like 'owner/name' (got '$Override')." }
        return $Override
    }

    # Resolve against the repository this script lives in, not the caller's cwd.
    $root = Split-Path -Parent $PSScriptRoot
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $url = & git -C $root remote get-url origin
    $ErrorActionPreference = $previous

    if (-not $url) { throw "No 'origin' remote found in $root. Pass -Repo owner/name instead." }
    $m = [regex]::Match($url, 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(\.git)?$')
    if (-not $m.Success) { throw "'origin' is not a GitHub remote: $url" }
    return "$($m.Groups['owner'].Value)/$($m.Groups['repo'].Value)"
}

function Get-GitHubToken {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN.Trim() }
    if ($env:GH_TOKEN) { return $env:GH_TOKEN.Trim() }

    # Fall back to Git Credential Manager - the same credential `git push` uses.
    # `git credential fill` needs protocol/host on stdin, and PowerShell 5.1 does
    # not reliably forward pipeline or StandardInput to a native command from a
    # -File script, so the request goes through a temp file + cmd redirection.
    # Only the request (no secret) is written to disk; the token stays in memory.
    $requestFile = Join-Path ([System.IO.Path]::GetTempPath()) "git-cred-req-$PID.txt"
    $previousGcm = $env:GCM_INTERACTIVE
    try {
        Set-Content -Path $requestFile -Value @('protocol=https', 'host=github.com', '') -Encoding ASCII
        $env:GCM_INTERACTIVE = 'never'
        $output = cmd /c ('git credential fill < "{0}" 2>&1' -f $requestFile)
    }
    finally {
        $env:GCM_INTERACTIVE = $previousGcm
        Remove-Item $requestFile -Force -ErrorAction SilentlyContinue
    }

    $line = @($output) | Where-Object { $_ -like 'password=*' } | Select-Object -First 1
    if (-not $line) {
        $seen = (@($output) |
            Where-Object { $_ -match '^(protocol|host|username)=' } |
            ForEach-Object { ($_ -split '=')[0] }) -join ', '
        throw "No GitHub token available (credential fill returned: [$seen]). Set `$env:GITHUB_TOKEN (repo scope), or run 'git push' once so Git Credential Manager can store one."
    }
    return ($line -replace '^password=', '').Trim()
}

$slug = Get-RepoSlug -Override $Repo
Write-Host "Repository : $slug"
Write-Host "Permission : $Permission"
Write-Host "Invitees   : $($Username -join ', ')"
Write-Host ''

if ($DryRun) {
    foreach ($user in $Username) {
        # Concatenated on purpose: "$user`?permission" reads as one variable name.
        $uri = "https://api.github.com/repos/$slug/collaborators/" + $user + "?permission=$Permission"
        Write-Host "[dry-run] PUT $uri"
    }
    exit 0
}

$token = Get-GitHubToken
$headers = @{
    'User-Agent'    = 'godot-collab-invite'
    'Accept'        = 'application/vnd.github+json'
    'Authorization' = "Bearer $token"
}

$failed = $false
foreach ($user in $Username) {
    $uri = "https://api.github.com/repos/$slug/collaborators/" + $user + "?permission=$Permission"
    try {
        $resp = Invoke-WebRequest -Uri $uri -Method Put -Headers $headers -UseBasicParsing
        if ($resp.StatusCode -eq 201) {
            Write-Host "invited  : $user ($Permission) - they must accept the email invitation"
        }
        elseif ($resp.StatusCode -eq 204) {
            Write-Host "updated  : $user was already a collaborator; permission is now $Permission"
        }
        else {
            Write-Host "response : $user -> HTTP $($resp.StatusCode)"
        }
    }
    catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        switch ($status) {
            401 { Write-Host "FAILED   : $user -> 401 token invalid or expired" }
            403 { Write-Host "FAILED   : $user -> 403 token lacks admin rights on $slug" }
            404 { Write-Host "FAILED   : $user -> 404 unknown GitHub user, or the token cannot see the repository" }
            422 { Write-Host "FAILED   : $user -> 422 cannot invite (for example, inviting the owner themselves)" }
            default { Write-Host "FAILED   : $user -> $($_.Exception.Message)" }
        }
        $failed = $true
    }
}

Write-Host ''
Write-Host "Pending invitations: https://github.com/$slug/settings/access"
if ($failed) { exit 1 }
exit 0
