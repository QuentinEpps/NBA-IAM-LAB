# IAM Scenarios — OKC Thunder & New York Knicks

Five real-world identity events this lab automates end-to-end. Each scenario
documents the business trigger, the IAM response, the scripts involved, and
verification commands to confirm everything worked correctly.

---

## Scenario 1 — OKC Thunder Signs a Player (Onboarding)

**Trigger:** OKC Thunder front office signs a player in the NBA Draft or free agency.

**What happens in Entra ID:**

1. `New-PlayerOnboarding.ps1` executed with `-TeamCode "OKC"`
2. UPN constructed automatically: `firstname.lastname@nba-lab.onmicrosoft.com`
3. `extensionAttribute1` set to `"active"`, `extensionAttribute3` set to `"OKC"`
4. Entra ID evaluates compound dynamic group rules — player added to `OKC-Players-ActiveRoster` and `NBA-AllPlayers-ActiveRoster` within minutes
5. Microsoft 365 license assigned via Graph API
6. `CAP-Players-MFA-CompliantDevice` conditional access policy automatically applies
7. Audit log entry written with timestamp, admin UPN, team, and action

**Script:**
```powershell
./powershell/New-PlayerOnboarding.ps1 `
  -DisplayName "Shai Gilgeous-Alexander" `
  -Position "PG" `
  -JerseyNumber "2" `
  -TeamCode "OKC"
```

**Verification:**
```powershell
# Confirm account exists and is enabled
Get-MgUser -UserId "shai.gilgeousalexander@nba-lab.onmicrosoft.com" | Select DisplayName, AccountEnabled

# Confirm dynamic group membership populated
Get-MgGroupMember -GroupId "<OKC-Players-ActiveRoster-GroupId>" | Where-Object { $_.AdditionalProperties.displayName -eq "Shai Gilgeous-Alexander" }
```

---

## Scenario 2 — New York Knicks Release a Player (Offboarding)

**Trigger:** Knicks front office releases a player from the roster.

**What happens in Entra ID:**

1. `Invoke-PlayerRelease.ps1` executed with the player's UPN
2. `Revoke-MgUserSignInSession` fires immediately — all active sessions terminated
3. Account disabled — no new logins possible
4. `extensionAttribute1` updated from `"active"` to `"released"` — `extensionAttribute3` stays `"NYK"`
5. Dynamic group rules recalculate — player removed from `NYK-Players-ActiveRoster` and `NBA-AllPlayers-ActiveRoster`, added to `NYK-Players-Offboarded`
6. All Microsoft 365 licenses removed
7. JSON audit record written: who, what, when, sessions revoked, licenses removed, 30-day retention window

**Why the order matters:** Sessions are revoked before the account is disabled because disabling alone does not kill existing active sessions. A released player could remain logged into team systems until the session naturally expires — a security gap this script closes immediately.

**Script:**
```powershell
./powershell/Invoke-PlayerRelease.ps1 `
  -PlayerUPN "josh.hart@nba-lab.onmicrosoft.com" `
  -Reason "Contract buyout"
```

**Verification:**
```powershell
# Account should be disabled
(Get-MgUser -UserId "josh.hart@nba-lab.onmicrosoft.com").AccountEnabled  # False

# Should only show NYK-Players-Offboarded
Get-MgUserMemberOf -UserId "josh.hart@nba-lab.onmicrosoft.com" | Select-Object -ExpandProperty AdditionalProperties | Select displayName

# Check audit trail
Get-Content ./logs/audit-trail.json | ConvertFrom-Json | Where-Object { $_.UserUPN -eq "josh.hart@nba-lab.onmicrosoft.com" }
```

---

## Scenario 3 — OKC Medical Staff Emergency PIM Activation (Game Night)

**Trigger:** OKC team physician needs immediate access to a player's health records during a playoff game at Paycom Center — outside normal business hours.

**What happens in Entra ID:**

1. Dr. James Okoro navigates to MyAccess portal (myaccess.microsoft.com)
2. PIM role `PIM-MedicalStaff-PatientData` requires a written justification: "Emergency — playoff game injury assessment, SGA #2"
3. Because activation is outside business hours, an approval request is sent to the on-call admin
4. Upon approval, elevated access is granted for a maximum 2-hour window
5. All access during the window is logged to the Entra ID audit log with a full activity trail
6. At window expiration, elevated access is automatically removed — no manual cleanup required

**Why PIM matters:** Without PIM, Dr. Okoro either has permanent elevated access to sensitive player health records (a least-privilege violation) or has to wait for an admin to manually grant access during a game emergency (an operational failure). PIM solves both problems simultaneously.

**Verification:**
```powershell
# Check PIM activation history for medical staff role
Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance | Where-Object { $_.PrincipalId -eq "<DrOkoroUserId>" }
```

---

## Scenario 4 — OKC Trades a Player to the Knicks (Cross-Team Transfer)

**Trigger:** OKC Thunder trades a player to the New York Knicks at the trade deadline.

**What happens in Entra ID:**

**Phase 1 — OKC offboarding (immediate):**
1. `Invoke-PlayerTrade.ps1` executed: `-FromTeam "OKC" -ToTeam "NYK"`
2. All active sessions revoked immediately
3. Account disabled
4. `extensionAttribute1` set to `"traded"` — player removed from `OKC-Players-ActiveRoster` and `NBA-AllPlayers-ActiveRoster`, added to `OKC-Players-Offboarded`
5. OKC licenses removed
6. Trade snapshot saved to audit log with 72-hour hold expiry timestamp

**Phase 2 — 72-hour trade hold:**
- Account suspended but not deleted — trade can still be voided during league processing
- To cancel: run `Invoke-TradeReversal.ps1` to restore full OKC account state
- To complete: re-run script with `-SkipHold` flag

**Phase 3 — NYK onboarding (after hold):**
1. `extensionAttribute3` updated from `"OKC"` to `"NYK"` — this single change moves the player across all franchise group boundaries simultaneously
2. `extensionAttribute1` set back to `"active"`
3. Player added to `NYK-Players-ActiveRoster` and `NBA-AllPlayers-ActiveRoster`
4. NYK licenses assigned
5. Trade completion audit record written

**Script:**
```powershell
# Initiate trade — OKC offboarding + 72hr hold
./powershell/Invoke-PlayerTrade.ps1 `
  -PlayerUPN "luguentz.dort@nba-lab.onmicrosoft.com" `
  -FromTeam "OKC" `
  -ToTeam "NYK"

# Complete trade after hold (or use -SkipHold for testing)
./powershell/Invoke-PlayerTrade.ps1 `
  -PlayerUPN "luguentz.dort@nba-lab.onmicrosoft.com" `
  -FromTeam "OKC" `
  -ToTeam "NYK" `
  -SkipHold
```

**Verification after completed trade:**
```powershell
# extensionAttribute3 should now be NYK
(Get-MgUser -UserId "luguentz.dort@nba-lab.onmicrosoft.com").OnPremisesExtensionAttributes

# Should show NYK-Players-ActiveRoster and NBA-AllPlayers-ActiveRoster
Get-MgUserMemberOf -UserId "luguentz.dort@nba-lab.onmicrosoft.com" | Select-Object -ExpandProperty AdditionalProperties | Select displayName
```

---

## Scenario 5 — Isaiah Hartenstein Free Agency (Cross-Org Offboarding + Fresh Onboarding)

**Trigger:** Isaiah Hartenstein's contract with the New York Knicks expires. He signs a new deal with the OKC Thunder in free agency.

**Why this is NOT a trade:** A trade involves a direct player transfer between teams with a hold window and potential reversal. Free agency is a contract expiration followed by a completely independent new signing. There is no 72-hour hold, no trade reversal logic, and no `Invoke-PlayerTrade.ps1`. The IAM handling is two separate events.

**Step 1 — NYK offboarding (contract expiration):**
```powershell
./powershell/Invoke-PlayerRelease.ps1 `
  -PlayerUPN "isaiah.hartenstein@nba-lab.onmicrosoft.com" `
  -Reason "Contract expired — free agency"
```

What happens:
- All NYK sessions revoked immediately
- Account disabled
- `extensionAttribute1` set to `"released"` — removed from all NYK groups
- NYK licenses removed
- Audit record written

**Step 2 — OKC onboarding (new contract signed):**
```powershell
./powershell/New-PlayerOnboarding.ps1 `
  -DisplayName "Isaiah Hartenstein" `
  -Position "C" `
  -JerseyNumber "55" `
  -TeamCode "OKC"
```

What happens:
- Fresh Entra ID account created with new OKC UPN
- `extensionAttribute1` set to `"active"`, `extensionAttribute3` set to `"OKC"`
- Added to `OKC-Players-ActiveRoster` and `NBA-AllPlayers-ActiveRoster` via dynamic group rules
- OKC licenses assigned
- New audit record written as a fresh onboarding event

**Verification:**
```powershell
# Old NYK account should be disabled
(Get-MgUser -UserId "isaiah.hartenstein@nba-lab.onmicrosoft.com").AccountEnabled  # False

# New OKC account should be active and in OKC groups
Get-MgUser -UserId "isaiah.hartenstein@nba-lab.onmicrosoft.com" | Select DisplayName, AccountEnabled
Get-MgUserMemberOf -UserId "isaiah.hartenstein@nba-lab.onmicrosoft.com" | Select-Object -ExpandProperty AdditionalProperties | Select displayName
```
