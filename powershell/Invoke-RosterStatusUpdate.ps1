#Requires -Modules Microsoft.Graph.Users

<#
.SYNOPSIS
    Updates a player's roster status within their team's Entra ID environment.

.DESCRIPTION
    Updates extensionAttribute1 (rosterStatus) on a player's Entra ID account.
    extensionAttribute3 (teamCode) is always preserved so the player stays
    in the correct franchise's dynamic groups.
    Dynamic groups recalculate membership automatically within minutes.

.PARAMETER PlayerUPN
    Player's UPN (e.g. "isaiah.hartenstein@nba-lab.onmicrosoft.com")

.PARAMETER NewStatus
    New roster status value.

.EXAMPLE
    # Designate OKC's Isaiah Hartenstein to injured reserve
    ./Invoke-RosterStatusUpdate.ps1 -PlayerUPN "isaiah.hartenstein@nba-lab.onmicrosoft.com" -NewStatus "injuredReserve"

    # Reinstate from IR
    ./Invoke-RosterStatusUpdate.ps1 -PlayerUPN "isaiah.hartenstein@nba-lab.onmicrosoft.com" -NewStatus "active"

    # Suspend a Knicks player
    ./Invoke-RosterStatusUpdate.ps1 -PlayerUPN "mitchell.robinson@nba-lab.onmicrosoft.com" -NewStatus "suspended"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string]$PlayerUPN,
    [Parameter(Mandatory)] [ValidateSet("active","injuredReserve","traded","released","suspended","practiceSquad")] [string]$NewStatus
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Maps rosterStatus to expected dynamic group for documentation purposes
$groupMap = @{
    "active"         = "{TEAM}-Players-ActiveRoster + NBA-AllPlayers-ActiveRoster"
    "injuredReserve" = "{TEAM}-Players-InjuredReserve"
    "traded"         = "{TEAM}-Players-Offboarded"
    "released"       = "{TEAM}-Players-Offboarded"
    "suspended"      = "{TEAM}-Players-Offboarded"
    "practiceSquad"  = "{TEAM}-Players-PracticeSquad"
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry
    if (-not (Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" | Out-Null }
    Add-Content -Path "./logs/roster-changes.log" -Value $entry
}

try {
    $ctx = Get-MgContext
    if (-not $ctx) {
        Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome
    }

    $user          = Get-MgUser -UserId $PlayerUPN -Property "Id,DisplayName,OnPremisesExtensionAttributes"
    $currentStatus = $user.OnPremisesExtensionAttributes.ExtensionAttribute1
    $teamCode      = $user.OnPremisesExtensionAttributes.ExtensionAttribute3
    $expectedGroup = $groupMap[$NewStatus] -replace "{TEAM}", $teamCode

    Write-Log "Player: $($user.DisplayName) | Team: $teamCode"
    Write-Log "Status change: $currentStatus -> $NewStatus"
    Write-Log "Expected group after recalculation: $expectedGroup"

    if ($currentStatus -eq $NewStatus) {
        Write-Log "Status is already '$NewStatus'. No change needed." "WARN"
        return
    }

    if ($PSCmdlet.ShouldProcess($PlayerUPN, "Update rosterStatus '$currentStatus' -> '$NewStatus'")) {

        # Update rosterStatus only — teamCode (extensionAttribute3) is never touched
        # This ensures the player stays within their correct franchise groups
        Update-MgUser -UserId $user.Id -BodyParameter @{
            OnPremisesExtensionAttributes = @{ ExtensionAttribute1 = $NewStatus }
        }
        Write-Log "rosterStatus updated. Dynamic group membership will recalculate within ~10 minutes."

        # Revoke sessions immediately for punitive or departure statuses
        if ($NewStatus -in @("suspended","traded")) {
            Revoke-MgUserSignInSession -UserId $user.Id
            Write-Log "Active sessions revoked (status: $NewStatus)"
        }

        [PSCustomObject]@{
            PlayerUPN      = $PlayerUPN
            DisplayName    = $user.DisplayName
            TeamCode       = $teamCode
            PreviousStatus = $currentStatus
            NewStatus      = $NewStatus
            ExpectedGroup  = $expectedGroup
            Timestamp      = (Get-Date -Format "o")
        }
    }
} catch {
    Write-Log "Status update FAILED for $PlayerUPN`: $_" "ERROR"
    throw
}
