#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Groups

<#
.SYNOPSIS
    Onboards a new player or staff member into their franchise Entra ID environment.

.DESCRIPTION
    Creates an Entra ID user account, sets team-scoped roster status attributes
    to trigger dynamic group membership for the correct franchise (OKC or NYK),
    and assigns Microsoft 365 licenses.

.PARAMETER DisplayName
    Full name of the person (e.g. "Shai Gilgeous-Alexander")

.PARAMETER Position
    Playing position (e.g. "PG", "SG", "SF", "PF", "C")

.PARAMETER JerseyNumber
    Jersey number as string (e.g. "2")

.PARAMETER TeamCode
    Team identifier — must be "OKC" (Thunder) or "NYK" (Knicks)

.PARAMETER Department
    Department assignment — Players, Coaching, Medical, FrontOffice
    Defaults to "Players"

.PARAMETER TenantDomain
    Tenant domain for UPN construction (e.g. "nba-lab.onmicrosoft.com")

.EXAMPLE
    ./New-PlayerOnboarding.ps1 -DisplayName "Shai Gilgeous-Alexander" -Position "PG" -JerseyNumber "2" -TeamCode "OKC"
    ./New-PlayerOnboarding.ps1 -DisplayName "Jalen Brunson" -Position "PG" -JerseyNumber "11" -TeamCode "NYK"
    ./New-PlayerOnboarding.ps1 -DisplayName "Mark Daigneault" -TeamCode "OKC" -Department "Coaching"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string]$DisplayName,
    [string]$Position = "",
    [string]$JerseyNumber = "",
    [Parameter(Mandatory)] [ValidateSet("OKC","NYK")] [string]$TeamCode,
    [ValidateSet("Players","Coaching","Medical","FrontOffice")] [string]$Department = "Players",
    [string]$TenantDomain = "nba-lab.onmicrosoft.com"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$teamConfig = @{
    OKC = @{ Name = "Oklahoma City Thunder"; Arena = "Paycom Center" }
    NYK = @{ Name = "New York Knicks"; Arena = "Madison Square Garden" }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] [$TeamCode] $Message"
    Write-Host $entry
    if (-not (Test-Path "./logs")) { New-Item -ItemType Directory -Path "./logs" | Out-Null }
    Add-Content -Path "./logs/onboarding.log" -Value $entry
}

function Get-UPN {
    param([string]$Name, [string]$Domain)
    $parts = $Name.Trim().ToLower() -split "\s+"
    $first = $parts[0] -replace "[^a-z0-9]", ""
    $last  = $parts[-1] -replace "[^a-z0-9]", ""
    return "$first.$last@$Domain"
}

try {
    $team = $teamConfig[$TeamCode]
    Write-Log "Starting onboarding: $DisplayName | $($team.Name) | Dept: $Department"

    $ctx = Get-MgContext
    if (-not $ctx) {
        Connect-MgGraph -Scopes "User.ReadWrite.All","Group.Read.All" -NoWelcome
    }

    $upn          = Get-UPN -Name $DisplayName -Domain $TenantDomain
    $mailNickname = ($upn -split "@")[0]
    $tempPassword = "$TeamCode#$(Get-Random -Minimum 1000 -Maximum 9999)!"

    Write-Log "UPN: $upn"

    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
    if ($existing) { throw "User already exists: $upn" }

    # extensionAttribute1 = rosterStatus — drives ActiveRoster dynamic group for players
    # extensionAttribute2 = jersey number
    # extensionAttribute3 = teamCode (OKC or NYK) — scopes user to correct franchise groups
    # extensionAttribute4 = position
    $rosterStatus = if ($Department -eq "Players") { "active" } else { "" }

    $userParams = @{
        DisplayName       = $DisplayName
        UserPrincipalName = $upn
        MailNickname      = $mailNickname
        Department        = $Department
        JobTitle          = if ($Position) { "$Position — $($team.Name)" } else { "$Department — $($team.Name)" }
        AccountEnabled    = $true
        PasswordProfile   = @{
            Password                      = $tempPassword
            ForceChangePasswordNextSignIn = $true
        }
        OnPremisesExtensionAttributes = @{
            ExtensionAttribute1 = $rosterStatus
            ExtensionAttribute2 = $JerseyNumber
            ExtensionAttribute3 = $TeamCode
            ExtensionAttribute4 = $Position
        }
    }

    if ($PSCmdlet.ShouldProcess($upn, "Create Entra ID user for $($team.Name)")) {
        $newUser = New-MgUser -BodyParameter $userParams
        Write-Log "User created: $($newUser.Id)"

        # Replace SkuId with your tenant's Microsoft 365 license GUID
        # Run: Get-MgSubscribedSku | Select SkuPartNumber, SkuId
        $licenseSkuId = "c7df2760-2c81-4ef7-b578-5b5392b571df"
        Set-MgUserLicense -UserId $newUser.Id -BodyParameter @{
            AddLicenses    = @(@{ SkuId = $licenseSkuId })
            RemoveLicenses = @()
        }
        Write-Log "License assigned"

        if ($Department -eq "Players") {
            Write-Log "Dynamic groups (${TeamCode}-Players-ActiveRoster + NBA-AllPlayers-ActiveRoster) will populate within 5-10 minutes"
        } else {
            Write-Log "Dynamic group (${TeamCode}-Staff-$Department) will populate within 5-10 minutes"
        }

        [PSCustomObject]@{
            DisplayName  = $DisplayName
            Team         = $team.Name
            TeamCode     = $TeamCode
            UPN          = $upn
            UserId       = $newUser.Id
            Department   = $Department
            RosterStatus = $rosterStatus
            Position     = $Position
            Jersey       = $JerseyNumber
            TempPassword = $tempPassword
            Timestamp    = (Get-Date -Format "o")
        }
    }
} catch {
    Write-Log "Onboarding FAILED for $DisplayName`: $_" "ERROR"
    throw
}
