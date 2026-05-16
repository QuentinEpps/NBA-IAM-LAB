#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Offboards a released player from their franchise Entra ID environment.

.DESCRIPTION
    Disables the player's account, revokes all active sessions, removes licenses,
    updates rosterStatus to "released" to trigger dynamic group reassignment
    from the team's ActiveRoster to Offboarded group, and writes a full audit record.

.PARAMETER PlayerUPN
    Player's UPN (e.g. "josh.hart@nba-lab.onmicrosoft.com")

.PARAMETER Reason
    Release reason for audit log. Defaults to "Roster decision".

.PARAMETER RetentionDays
    Days to retain disabled account before deletion. Defaults to 30.

.EXAMPLE
    ./Invoke-PlayerRelease.ps1 -PlayerUPN "josh.hart@nba-lab.onmicrosoft.com" -Reason "Contract buyout"
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param (
    [Parameter(Mandatory)] [string]$PlayerUPN,
    [string]$Reason = "Roster decision",
    [int]$RetentionDays = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry
    if (-not (Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" | Out-Null }
    Add-Content -Path "./logs/offboarding.log" -Value $entry
}

function Write-Audit {
    param([PSCustomObject]$Record)
    $auditPath = "./logs/audit-trail.json"
    $existing  = if (Test-Path $auditPath) { Get-Content $auditPath | ConvertFrom-Json } else { @() }
    ($existing + $Record) | ConvertTo-Json -Depth 5 | Set-Content $auditPath
}

try {
    Write-Log "Release offboarding initiated: $PlayerUPN | Reason: $Reason"

    $ctx = Get-MgContext
    if (-not $ctx) {
        Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome
    }

    $user     = Get-MgUser -UserId $PlayerUPN -Property "Id,DisplayName,AccountEnabled,AssignedLicenses,OnPremisesExtensionAttributes"
    $teamCode = $user.OnPremisesExtensionAttributes.ExtensionAttribute3

    Write-Log "Player: $($user.DisplayName) | Team: $teamCode"

    if ($PSCmdlet.ShouldProcess($PlayerUPN, "Release offboarding")) {

        # Step 1 — Revoke all active sessions immediately
        Revoke-MgUserSignInSession -UserId $user.Id
        Write-Log "All active sessions revoked"

        # Step 2 — Disable account
        Update-MgUser -UserId $user.Id -AccountEnabled:$false
        Write-Log "Account disabled"

        # Step 3 — Update rosterStatus to "released"
        # Triggers dynamic group move: ActiveRoster -> Offboarded
        # extensionAttribute3 (teamCode) preserved so audit trail retains team context
        Update-MgUser -UserId $user.Id -BodyParameter @{
            OnPremisesExtensionAttributes = @{ ExtensionAttribute1 = "released" }
        }
        Write-Log "rosterStatus set to 'released' — dynamic group reassignment triggered for $teamCode"

        # Step 4 — Remove all licenses
        if ($user.AssignedLicenses.Count -gt 0) {
            Set-MgUserLicense -UserId $user.Id -BodyParameter @{
                AddLicenses    = @()
                RemoveLicenses = $user.AssignedLicenses | Select-Object -ExpandProperty SkuId
            }
            Write-Log "$($user.AssignedLicenses.Count) license(s) removed"
        }

        # Step 5 — Write audit record
        $auditRecord = [PSCustomObject]@{
            Action          = "PlayerRelease"
            UserUPN         = $PlayerUPN
            UserId          = $user.Id
            DisplayName     = $user.DisplayName
            TeamCode        = $teamCode
            Reason          = $Reason
            RosterStatus    = "released"
            SessionsRevoked = $true
            LicensesRemoved = $user.AssignedLicenses.Count
            RetentionUntil  = (Get-Date).AddDays($RetentionDays).ToString("yyyy-MM-dd")
            PerformedBy     = (Get-MgContext).Account
            Timestamp       = (Get-Date -Format "o")
        }

        Write-Audit -Record $auditRecord
        Write-Log "Audit record written. Retention until: $($auditRecord.RetentionUntil)"
        Write-Log "Release complete: $($user.DisplayName)"

        $auditRecord
    }
} catch {
    Write-Log "Release FAILED for $PlayerUPN`: $_" "ERROR"
    throw
}
