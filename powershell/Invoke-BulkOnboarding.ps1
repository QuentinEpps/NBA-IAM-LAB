#Requires -Modules Microsoft.Graph.Users

<#
.SYNOPSIS
    Bulk onboards all players, coaches, medical staff, and front office
    for both OKC Thunder and New York Knicks from config/roster.json

.EXAMPLE
    ./powershell/Invoke-BulkOnboarding.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$TenantDomain = "yourdomain.onmicrosoft.com",
    [string]$RosterPath   = "./config/roster.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry
    if (-not (Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" | Out-Null }
    Add-Content -Path "./logs/bulk-onboarding.log" -Value $entry
}

function Get-UPN {
    param([string]$Name, [string]$Domain)
    $parts = $Name.Trim().ToLower() -split "\s+"
    $first = $parts[0] -replace "[^a-z0-9]", ""
    $last  = $parts[-1] -replace "[^a-z0-9]", ""
    return "$first.$last@$Domain"
}

function New-OrgUser {
    param(
        [string]$DisplayName,
        [string]$TeamCode,
        [string]$Department,
        [string]$JobTitle,
        [string]$RosterStatus,
        [string]$Jersey,
        [string]$Position,
        [string]$Domain
    )

    $upn          = Get-UPN -Name $DisplayName -Domain $Domain
    $mailNickname = ($upn -split "@")[0]
    $tempPassword = "$TeamCode#$(Get-Random -Minimum 1000 -Maximum 9999)!"

    # Check if user already exists — skip if so
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "SKIP — already exists: $upn" "WARN"
        return
    }

    $userParams = @{
        DisplayName       = $DisplayName
        UserPrincipalName = $upn
        MailNickname      = $mailNickname
        Department        = $Department
        JobTitle          = $JobTitle
        AccountEnabled    = $true
        PasswordProfile   = @{
            Password                      = $tempPassword
            ForceChangePasswordNextSignIn = $true
        }
        OnPremisesExtensionAttributes = @{
            ExtensionAttribute1 = $RosterStatus
            ExtensionAttribute2 = $Jersey
            ExtensionAttribute3 = $TeamCode
            ExtensionAttribute4 = $Position
        }
    }

    try {
        $newUser = New-MgUser -BodyParameter $userParams
        Write-Log "CREATED: $DisplayName | $upn | $TeamCode | $Department"
    } catch {
        Write-Log "FAILED: $DisplayName | $_" "ERROR"
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Verify Graph connection
$ctx = Get-MgContext
if (-not $ctx) {
    Write-Log "Not connected to Microsoft Graph. Run Connect-MgGraph first." "ERROR"
    throw "Graph connection required."
}

Write-Log "Starting bulk onboarding — reading from $RosterPath"

# Load roster
$roster = Get-Content $RosterPath | ConvertFrom-Json
$teams  = $roster.teams.PSObject.Properties

$created = 0
$skipped = 0
$failed  = 0

foreach ($teamProp in $teams) {
    $teamCode = $teamProp.Name
    $team     = $teamProp.Value

    Write-Log "---- $($team.name) ($teamCode) ----"

    # Players
    foreach ($player in $team.players) {
        New-OrgUser `
            -DisplayName  $player.displayName `
            -TeamCode     $teamCode `
            -Department   "Players" `
            -JobTitle     "$($player.position) — $($team.name)" `
            -RosterStatus $player.status `
            -Jersey       $player.jersey `
            -Position     $player.position `
            -Domain       $TenantDomain
    }

    # Coaching staff
    foreach ($coach in $team.coaching) {
        New-OrgUser `
            -DisplayName  $coach.displayName `
            -TeamCode     $teamCode `
            -Department   "Coaching" `
            -JobTitle     "$($coach.title) — $($team.name)" `
            -RosterStatus "" `
            -Jersey       "" `
            -Position     "" `
            -Domain       $TenantDomain
    }

    # Medical staff
    foreach ($med in $team.medical) {
        New-OrgUser `
            -DisplayName  $med.displayName `
            -TeamCode     $teamCode `
            -Department   "Medical" `
            -JobTitle     "$($med.title) — $($team.name)" `
            -RosterStatus "" `
            -Jersey       "" `
            -Position     "" `
            -Domain       $TenantDomain
    }

    # Front office
    foreach ($exec in $team.frontOffice) {
        New-OrgUser `
            -DisplayName  $exec.displayName `
            -TeamCode     $teamCode `
            -Department   "FrontOffice" `
            -JobTitle     "$($exec.title) — $($team.name)" `
            -RosterStatus "" `
            -Jersey       "" `
            -Position     "" `
            -Domain       $TenantDomain
    }
}

Write-Log "Bulk onboarding complete. Check logs/bulk-onboarding.log for full details."
