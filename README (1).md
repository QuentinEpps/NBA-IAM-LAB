# 🏀 NBA Identity & Access Management Lab
### Oklahoma City Thunder & New York Knicks

> A hands-on Microsoft Entra ID portfolio project modeling two NBA franchises' full identity infrastructure — dynamic group membership, automated lifecycle management, cross-team trade workflows, conditional access policies, and privileged identity management.

---

## Overview

Professional sports organizations have unusually demanding IAM requirements. Rosters change constantly, staff roles carry strict data access boundaries (HIPAA for medical staff, financial controls for front office), and access must be provisioned and revoked rapidly when players are drafted, traded, injured, or released.

This lab models that environment end-to-end using **Microsoft Entra ID**, **PowerShell**, **Microsoft Graph API**, and **Bicep** — across two real NBA franchises operating as separate organizational units inside a single tenant.

---

## Architecture

```
Entra ID Tenant — NBA League
│
├── OKC Thunder
│   ├── OKC-Players-ActiveRoster        ← extensionAttribute1="active" + extensionAttribute3="OKC"
│   ├── OKC-Players-InjuredReserve      ← extensionAttribute1="injuredReserve" + extensionAttribute3="OKC"
│   ├── OKC-Players-Offboarded          ← extensionAttribute1="released"/"traded" + extensionAttribute3="OKC"
│   ├── OKC-Staff-Medical               ← department="Medical" + extensionAttribute3="OKC"
│   ├── OKC-Staff-Coaching              ← department="Coaching" + extensionAttribute3="OKC"
│   └── OKC-FrontOffice                 ← department="FrontOffice" + extensionAttribute3="OKC"
│
├── New York Knicks
│   ├── NYK-Players-ActiveRoster        ← extensionAttribute1="active" + extensionAttribute3="NYK"
│   ├── NYK-Players-InjuredReserve      ← extensionAttribute1="injuredReserve" + extensionAttribute3="NYK"
│   ├── NYK-Players-Offboarded          ← extensionAttribute1="released"/"traded" + extensionAttribute3="NYK"
│   ├── NYK-Staff-Medical               ← department="Medical" + extensionAttribute3="NYK"
│   ├── NYK-Staff-Coaching              ← department="Coaching" + extensionAttribute3="NYK"
│   └── NYK-FrontOffice                 ← department="FrontOffice" + extensionAttribute3="NYK"
│
├── League-Wide Groups
│   ├── NBA-AllPlayers-ActiveRoster     ← all active players, both teams
│   └── NBA-Scouting-ReadAccess         ← coaches + front office cross-team scouting access
│
├── Conditional Access Policies
│   ├── CAP-Players-MFA-CompliantDevice          ← all active roster players, both teams
│   ├── CAP-OKC-Executives-LocationRestricted    ← Paycom Center IP range
│   └── CAP-NYK-Executives-LocationRestricted    ← Madison Square Garden IP range
│
├── Privileged Identity Management
│   └── PIM-MedicalStaff-PatientData    ← JIT, 2hr window, justification required
│
└── Lifecycle Automation
    ├── New-PlayerOnboarding.ps1
    ├── Invoke-PlayerRelease.ps1
    ├── Invoke-PlayerTrade.ps1
    └── Invoke-RosterStatusUpdate.ps1
```

---

## Rosters

### OKC Thunder

| Player | Position | Jersey | Status |
|---|---|---|---|
| Shai Gilgeous-Alexander | PG | 2 | Active |
| Jalen Williams | SG | 8 | Active |
| Chet Holmgren | C | 7 | Active |
| Luguentz Dort | SF | 5 | Active |
| Isaiah Hartenstein | C | 55 | Active |
| Alex Caruso | SG | 6 | Active |
| Cason Wallace | PG | 22 | Active |
| Ajay Mitchell | SG | 12 | Active |
| Isaiah Joe | SG | 11 | Active |
| Aaron Wiggins | SF | 21 | Active |
| Jaylin Williams | PF | 6 | Active |
| Kenrich Williams | SF | 34 | Active |
| Ousmane Dieng | SF | 13 | Active |
| Nikola Topic | PG | 44 | Active |
| Jared McCain | SG | 3 | Active |
| Payton Sandfort | SF | 19 | Active |

| Staff | Role | Department |
|---|---|---|
| Mark Daigneault | Head Coach | Coaching |
| Kameron Woods | Assistant Coach | Coaching |
| Sam Presti | Executive VP & General Manager | Front Office |
| Danny Barth | Executive VP & Chief Administrative Officer | Front Office |
| Clay Bennett | Governor & Owner | Front Office |
| Dr. James Okoro | Team Physician | Medical |
| Tony Dobbins | Head Athletic Trainer | Medical |

---

### New York Knicks

| Player | Position | Jersey | Status |
|---|---|---|---|
| Jalen Brunson | PG | 11 | Active |
| Karl-Anthony Towns | C | 32 | Active |
| OG Anunoby | SF | 8 | Active |
| Mikal Bridges | SF | 25 | Active |
| Josh Hart | SG | 3 | Active |
| Mitchell Robinson | C | 23 | Active |
| Miles McBride | SG | 2 | Active |
| Tyler Kolek | PG | 17 | Active |
| Jose Alvarado | PG | 15 | Active |
| Jordan Clarkson | SG | 0 | Active |
| Jeremy Sochan | PF | 10 | Active |
| Guerschon Yabusele | PF | 28 | Active |
| Landry Shamet | SG | 20 | Active |
| Kevin McCullar Jr. | SG | 13 | Active |
| Ariel Hukporti | C | 41 | Active |
| Pacome Dadiet | SF | 7 | Active |
| Mohamed Diawara | SG | 4 | Active |

| Staff | Role | Department |
|---|---|---|
| Mike Brown | Head Coach | Coaching |
| Maurice Cheeks | Assistant Coach | Coaching |
| Rick Brunson | Assistant Coach | Coaching |
| Jordan Brink | Assistant Coach | Coaching |
| Ricardo Fois | Assistant Coach | Coaching |
| Mark Bryant | Assistant Coach | Coaching |
| Darren Erman | Assistant Coach | Coaching |
| Leon Rose | President | Front Office |
| William Wesley | Executive VP & Senior Advisor | Front Office |
| Gersson Rosas | Senior VP of Basketball Operations | Front Office |
| Frank Zanin | Assistant General Manager | Front Office |
| Brock Aller | Cap Strategist | Front Office |
| Dr. Sarah Chen | Team Physician | Medical |
| Mike Saunders | Head Athletic Trainer | Medical |

---

## Dynamic Group Membership Rules

| Group | Membership Rule |
|---|---|
| OKC-Players-ActiveRoster | `(user.extensionAttribute1 -eq "active") -and (user.extensionAttribute3 -eq "OKC")` |
| OKC-Players-InjuredReserve | `(user.extensionAttribute1 -eq "injuredReserve") -and (user.extensionAttribute3 -eq "OKC")` |
| OKC-Players-Offboarded | `(user.extensionAttribute1 -eq "released" -or user.extensionAttribute1 -eq "traded") -and (user.extensionAttribute3 -eq "OKC")` |
| NYK-Players-ActiveRoster | `(user.extensionAttribute1 -eq "active") -and (user.extensionAttribute3 -eq "NYK")` |
| NYK-Players-InjuredReserve | `(user.extensionAttribute1 -eq "injuredReserve") -and (user.extensionAttribute3 -eq "NYK")` |
| NYK-Players-Offboarded | `(user.extensionAttribute1 -eq "released" -or user.extensionAttribute1 -eq "traded") -and (user.extensionAttribute3 -eq "NYK")` |
| NBA-AllPlayers-ActiveRoster | `user.extensionAttribute1 -eq "active"` |

---

## Scenarios

See [docs/SCENARIOS.md](docs/SCENARIOS.md) for five end-to-end walkthroughs:

1. **OKC drafts a player** — full onboarding into OKC org with dynamic group population
2. **Knicks release a player** — offboarding, session revocation, license removal, audit trail
3. **OKC medical staff emergency PIM activation** — game night just-in-time access
4. **OKC trades a player to the Knicks** — cross-team transfer with 72hr hold and reversal capability
5. **Isaiah Hartenstein free agency** — contract expiration offboarding from NYK + fresh OKC onboarding

---

## Deployment

### Prerequisites

- Azure subscription with Entra ID P2 license
- PowerShell 7+ with Microsoft.Graph module
- Azure CLI

```powershell
# Install and connect
Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Policy.ReadWrite.ConditionalAccess","RoleManagement.ReadWrite.Directory"

# Deploy base infrastructure
az group create --name rg-nba-iam-lab --location eastus
az deployment group create --resource-group rg-nba-iam-lab --template-file bicep/main.bicep

# Onboard a player
./powershell/New-PlayerOnboarding.ps1 -DisplayName "Shai Gilgeous-Alexander" -Position "PG" -JerseyNumber "2" -TeamCode "OKC"

# Execute a trade
./powershell/Invoke-PlayerTrade.ps1 -PlayerUPN "player@nba-lab.com" -FromTeam "OKC" -ToTeam "NYK"
```

---

## Skills Demonstrated

| Skill | Implementation |
|---|---|
| Entra ID Administration | Multi-team user lifecycle, compound extension attributes, license management |
| Dynamic Group Membership | Team-scoped compound rules, league-wide group layer, automatic recalculation |
| Conditional Access | Team-specific location policies, device compliance, session controls |
| Privileged Identity Management | JIT activation, approval workflows, audit logging — both teams |
| PowerShell & Graph API | Team-aware lifecycle scripts with error handling, logging, -WhatIf support |
| Infrastructure as Code | Bicep templates for repeatable, auditable environment deployment |
| Identity Governance | Cross-org trade handling, free agency offboarding, least-privilege design, JSON audit logging |

---

## Project Structure

```
nba-iam-lab/
├── bicep/                  # Infrastructure as Code
├── powershell/             # Lifecycle automation scripts
│   ├── New-PlayerOnboarding.ps1
│   ├── Invoke-PlayerRelease.ps1
│   ├── Invoke-PlayerTrade.ps1
│   └── Invoke-RosterStatusUpdate.ps1
├── docs/
│   └── SCENARIOS.md
├── config/
│   └── roster.json         # Complete org — both teams
├── logs/
│   └── audit-trail.json
└── README.md
```

---

## License
MIT
