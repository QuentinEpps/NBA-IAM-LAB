#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Executes a player trade between OKC Thunder and New York Knicks.

.DESCRIPTION
    Handles the full cross-team identity transfer — franchise offboarding,
    72-hour trade hold with reversal capability, and new franchise onboarding.
    extensionAttribute3 (teamCode) is updated to reflect the new franchise,
    triggering automatic dynamic group reassignment on both sides.

.PARAMETER PlayerUPN
    Player's current UPN (e.g. "luguentz.dort@nba-lab.onmicrosoft.com")

.PARAMETER FromTeam
    Originating team — "OKC" or "NYK"

.PARAMETER ToTeam
    Destination team — "OKC" or "NYK"

.PARAMETER SkipHold
    Bypasses the 72-hour hold and completes onboarding immediately.
    Use for testing only.

.EXAMPLE
    # OKC trades a player to the Knicks
    ./Invoke-PlayerTrade.ps1 -PlayerUPN "luguentz.dort@nba-lab.onmicrosoft.com" -FromTeam "OKC" -ToTeam "NYK"

    # Skip hold for testing
    ./Invoke-PlayerTrade.ps1 -PlayerUPN "luguentz.dort@nba-lab.onmicrosoft.com" -FromTeam "OKC" -ToTeam "NYK" -SkipHold

.NOTES
    Isaiah Hartenstein's move from NYK to OKC was a FREE AGENCY signing, not a trade.
    Use Invoke-PlayerRelease.ps1 for the NYK offboarding and New-PlayerOnboarding.ps1
    for the OKC onboarding in that scenario. No trade hold applies.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param (
    [Parameter(Mandatory)] [string]$PlayerUPN,
    [Parameter(Mandatory)] [ValidateSet("OKC","NYK")] [string]$FromTeam,
    [Parameter(Mandatory)] [ValidateSet("OKC","NYK")] [string]$ToTeam,
    [switch]$SkipHold
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$teamConfig = @{
    OKC = @{ Name = "Oklahoma City Thunder"; LicenseSkuId = "c7df2760-2c81-4ef7-b578-5b5392b571df" }
    NYK = @{ Name = "New York Knicks";        LicenseSkuId = "c7df2760-2c81-4ef7-b578-5b5392b571df" }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] [TRADE:$FromTeam->$ToTeam] $Message"
    Write-Host $entry
    if (-not (Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" | Out-Null }
    Add-Content -Path "./logs/trades.log" -Value $entry
}

function Write-Audit {
    param([PSCustomObject]$Record)
    $auditPath = "./logs/audit-trail.json"
    $existing  = if (Test-Path $auditPath) { Get-Content $auditPath | ConvertFrom-Json } else { @() }
    ($existing + $Record) | ConvertTo-Json -Depth 5 | Set-Content $auditPath
}

try {
    if ($FromTeam -eq $ToTeam) { throw "FromTeam and ToTeam cannot be the same." }

    $ctx = Get-MgContext
    if (-not $ctx) {
        Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome
    }

    $user = Get-MgUser -UserId $PlayerUPN -Property "Id,DisplayName,AccountEnabled,AssignedLicenses,OnPremisesExtensionAttributes,JobTitle"
    Write-Log "Trade initiated: $($user.DisplayName) | $($teamConfig[$FromTeam].Name) -> $($teamConfig[$ToTeam].Name)"

    if ($PSCmdlet.ShouldProcess($PlayerUPN, "Execute trade $FromTeam -> $ToTeam")) {

        # ── PHASE 1: FROM-TEAM OFFBOARDING ────────────────────────────────────
        Write-Log "Phase 1: $FromTeam offboarding"

        Revoke-MgUserSignInSession -UserId $user.Id
        Write-Log "All active sessions revoked"

        Update-MgUser -UserId $user.Id -AccountEnabled:$false
        Write-Log "Account disabled"

        # Set rosterStatus to "traded" — moves player out of ActiveRoster
        # extensionAttribute3 stays as FromTeam during the hold period
        Update-MgUser -UserId $user.Id -BodyParameter @{
            OnPremisesExtensionAttributes = @{ ExtensionAttribute1 = "traded" }
        }
        Write-Log "rosterStatus set to 'traded' — removed from ${FromTeam}-Players-ActiveRoster"

        if ($user.AssignedLicenses.Count -gt 0) {
            Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                AddLicenses    = @()
                RemoveLicenses = $user.AssignedLicenses | Select-Object -ExpandProperty SkuId
            }
            Write-Log "$($user.AssignedLicenses.Count) license(s) removed"
        }

        # Save snapshot for potential reversal during hold window
        $holdExpiry = (Get-Date).AddHours(72).ToString("o")
        Write-Audit -Record ([PSCustomObject]@{
            Action      = "TradeSnapshot"
            UserUPN     = $PlayerUPN
            UserId      = $user.Id
            DisplayName = $user.DisplayName
            FromTeam    = $FromTeam
            ToTeam      = $ToTeam
            HoldExpiry  = $holdExpiry
            PerformedBy = (Get-MgContext).Account
            Timestamp   = (Get-Date -Format "o")
        })
        Write-Log "Trade snapshot saved — hold expires: $holdExpiry"

        # ── PHASE 2: 72-HOUR HOLD ─────────────────────────────────────────────
        if (-not $SkipHold) {
            Write-Log "72-hour trade hold active."
            Write-Log "To cancel: run Invoke-TradeReversal.ps1 -PlayerUPN '$PlayerUPN'"
            Write-Log "To complete: re-run with -SkipHold flag after hold expires."
            return
        }

        # ── PHASE 3: TO-TEAM ONBOARDING ───────────────────────────────────────
        Write-Log "Phase 3: $ToTeam onboarding"

        Update-MgUser -UserId $user.Id -BodyParameter @{
            AccountEnabled = $true
            OnPremisesExtensionAttributes = @{
                ExtensionAttribute1 = "active"   # rosterStatus back to active
                ExtensionAttribute3 = $ToTeam    # teamCode updated to new franchise
            }
        }
        Write-Log "Account re-enabled — teamCode updated to $ToTeam"
        Write-Log "Dynamic groups: added to ${ToTeam}-Players-ActiveRoster + NBA-AllPlayers-ActiveRoster"

        Set-MgUserLicense -UserId $user.Id -BodyParameter @{
            AddLicenses    = @(@{ SkuId = $teamConfig[$ToTeam].LicenseSkuId })
            RemoveLicenses = @()
        }
        Write-Log "$ToTeam license assigned"

        Write-Audit -Record ([PSCustomObject]@{
            Action      = "TradeCompleted"
            UserUPN     = $PlayerUPN
            UserId      = $user.Id
            DisplayName = $user.DisplayName
            FromTeam    = $FromTeam
            ToTeam      = $ToTeam
            PerformedBy = (Get-MgContext).Account
            Timestamp   = (Get-Date -Format "o")
        })

        Write-Log "Trade complete: $($user.DisplayName) is now a $($teamConfig[$ToTeam].Name) player"

        [PSCustomObject]@{
            Player    = $user.DisplayName
            FromTeam  = $FromTeam
            ToTeam    = $ToTeam
            Status    = "TradeCompleted"
            Timestamp = (Get-Date -Format "o")
        }
    }
} catch {
    Write-Log "Trade FAILED for $PlayerUPN`: $_" "ERROR"
    throw
}
