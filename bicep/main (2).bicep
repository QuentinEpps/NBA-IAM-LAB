// ============================================================
// NBA IAM Lab — Base Infrastructure
// OKC Thunder & New York Knicks | Microsoft Entra ID Lab
//
// Deploys the Azure resource scaffolding that supports the
// identity governance lab. Entra ID objects (users, groups,
// conditional access policies, PIM) are managed via PowerShell
// and Microsoft Graph — not ARM/Bicep — since Entra ID
// resources live outside the Azure resource model.
//
// What this deploys:
//   - Resource Group (via subscription scope)
//   - Log Analytics Workspace (audit log ingestion)
//   - Key Vault (secure storage for lab secrets and temp passwords)
// ============================================================

targetScope = 'subscription'

// ── Parameters ───────────────────────────────────────────────
@description('Azure region for all resources')
param location string = 'eastus'

@description('Environment tag')
param environment string = 'lab'

@description('Project name used for resource naming')
param projectName string = 'nba-iam-lab'

@description('Your Azure AD tenant ID')
param tenantId string

// ── Resource Group ───────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${projectName}-${environment}'
  location: location
  tags: {
    Project    : projectName
    Environment: environment
    ManagedBy  : 'Bicep'
    Purpose    : 'NBA IAM Portfolio Lab — OKC Thunder and NY Knicks'
  }
}

// ── Log Analytics Workspace ──────────────────────────────────
// Ingests Entra ID audit logs and sign-in logs for the lab
// Enables querying identity events across both franchises
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  scope: rg
  params: {
    workspaceName: 'law-${projectName}-${environment}'
    location     : location
    tags         : rg.tags
    retentionDays: 90
  }
}

// ── Key Vault ─────────────────────────────────────────────────
// Stores temporary passwords generated during player onboarding
// Access restricted to lab admin identity only
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  scope: rg
  params: {
    keyVaultName: 'kv-${projectName}-${uniqueString(rg.id)}'
    location    : location
    tags        : rg.tags
    tenantId    : tenantId
  }
}

// ── Outputs ───────────────────────────────────────────────────
output resourceGroupName string = rg.name
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId
output keyVaultUri string = keyVault.outputs.keyVaultUri
