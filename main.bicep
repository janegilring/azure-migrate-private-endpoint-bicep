// Azure Migrate with Private Connectivity — Main Bicep Template
//
// Deploys Azure Migrate project infrastructure with private endpoint connectivity:
//   - Storage Account (utility storage, blob PE)
//   - Key Vault (secrets management, vault PE)
//   - Recovery Services Vault (migration, Site Recovery PE)
//   - Migrate Project (hub resource, Default PE)
//   - Assessment Project (assessment engine, Default PE)
//   - Master Site (appliance orchestration, Default PE)
//   - VMware Site (discovery source)
//   - Private DNS zones and VNet links
//   - 6 private endpoints with DNS zone groups
//
// Prerequisites:
//   - Existing VNet with a subnet configured for private endpoints
//     (privateEndpointNetworkPolicies must be Disabled on the subnet)
//   - Contributor + User Access Administrator on the target resource group
//
// Reference deployment inspected from:
//   Subscription: 46459af8-726e-4515-a736-dd473698a2db
//   Resource groups: rg-azure-migration, rg-networking

// ──────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────

@description('Base name used to derive resource names. Must be 3-20 characters, lowercase alphanumeric.')
@minLength(3)
@maxLength(20)
param projectName string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Resource ID of the existing subnet for private endpoints. The subnet must have privateEndpointNetworkPolicies set to Disabled.')
param privateEndpointSubnetId string

@description('Resource ID of the existing virtual network (used for DNS zone VNet links).')
param virtualNetworkId string

@description('Tenant ID for Key Vault. Defaults to the current tenant.')
param tenantId string = subscription().tenantId

@description('Tags to apply to all resources.')
param tags object = {}

// ──────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────

// Derive deterministic but unique names from projectName
var uniqueSuffix = uniqueString(resourceGroup().id, projectName)
var storageAccountName = toLower('${take(replace(projectName, '-', ''), 14)}${take(uniqueSuffix, 10)}')
var keyVaultName = '${take(replace(projectName, '-', ''), 12)}-${take(uniqueSuffix, 8)}-kv'
var recoveryVaultName = '${projectName}-rsv'
var migrateProjectName = projectName
var assessmentProjectName = '${projectName}-assess-${take(uniqueSuffix, 4)}'
var masterSiteName = '${projectName}-mastersite'
var vmwareSiteName = '${projectName}-vmwaresite'

var migrateTags = union(tags, {
  'Migrate Project': projectName
})

// ──────────────────────────────────────────────
// Storage Account
// ──────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: migrateTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ──────────────────────────────────────────────
// Key Vault
// ──────────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: migrateTags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableSoftDelete: true
    enablePurgeProtection: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ──────────────────────────────────────────────
// Recovery Services Vault
// ──────────────────────────────────────────────

resource recoveryVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: recoveryVaultName
  location: location
  tags: migrateTags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

// ──────────────────────────────────────────────
// Azure Migrate Project (hub)
// ──────────────────────────────────────────────

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: migrateProjectName
  location: location
  tags: migrateTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    utilityStorageAccountId: storageAccount.id
  }
}

// ──────────────────────────────────────────────
// Managed Identity Permissions
// ──────────────────────────────────────────────
// The Migrate project's system-assigned managed identity needs access to
// the storage account and Key Vault. Without these, the assessment project
// creation fails with DataPreconditionFailed.

// Storage Blob Data Contributor for the Migrate project managed identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, migrateProject.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    )
    principalId: migrateProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault RBAC role assignments for the Migrate project managed identity
// Key Vault Secrets Officer - get, list, set secrets
resource kvSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, migrateProject.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
    )
    principalId: migrateProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Crypto Officer - get, list, create keys
resource kvCryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, migrateProject.id, '14b46e9e-c2b7-41b4-b07b-48a6ebf60603')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '14b46e9e-c2b7-41b4-b07b-48a6ebf60603' // Key Vault Crypto Officer
    )
    principalId: migrateProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Certificates Officer - get, list certificates
resource kvCertificatesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, migrateProject.id, 'a4417e6f-fecd-4de8-b567-7b0420556985')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a4417e6f-fecd-4de8-b567-7b0420556985' // Key Vault Certificates Officer
    )
    principalId: migrateProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ──────────────────────────────────────────────
// Migrate Solutions (registered tools)
// ──────────────────────────────────────────────

// Solutions must be created before the Assessment Project and VMware Site
// that reference them. The portal-standard naming convention uses names
// longer than 24 chars, so the 2018-09-01-preview API is required.

resource solutionDiscovery 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  name: 'Servers-Discovery-ServerDiscovery'
  parent: migrateProject
  properties: {
    goal: 'Servers'
    purpose: 'Discovery'
    tool: 'ServerDiscovery'
    status: 'Active'
    details: {
      extendedDetails: {
        // PE details tell the RP (and portal) that private endpoints are in use
        privateEndpointDetails: '{"subnetId":"${privateEndpointSubnetId}","virtualNetworkLocation":"${location}","skipPrivateDnsZoneCreation":false}'
        keyVaultId: keyVault.id
        keyVaultUrl: keyVault.properties.vaultUri
        masterSiteId: masterSite.id
      }
    }
  }
}

resource solutionAssessment 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  name: 'Servers-Assessment-ServerAssessment'
  parent: migrateProject
  properties: {
    goal: 'Servers'
    purpose: 'Assessment'
    tool: 'ServerAssessment'
    status: 'Active'
    details: {
      extendedDetails: {
        // Use resourceId() to avoid circular dependency with assessmentProject
        projectId: resourceId('Microsoft.Migrate/assessmentProjects', assessmentProjectName)
      }
    }
  }
}

resource solutionMigration 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  name: 'Servers-Migration-ServerMigration'
  parent: migrateProject
  properties: {
    goal: 'Servers'
    purpose: 'Migration'
    tool: 'ServerMigration'
    status: 'Active'
    details: {
      extendedDetails: {
        vaultId: recoveryVault.id
      }
    }
  }
}

// ──────────────────────────────────────────────
// Master Site (appliance orchestrator)
// ──────────────────────────────────────────────

// Note: tags property is not in the MasterSites type definition but is supported at runtime.
resource masterSite 'Microsoft.OffAzure/masterSites@2023-06-06' = {
  name: masterSiteName
  location: location
  properties: {
    publicNetworkAccess: 'Disabled'
    allowMultipleSites: true
    customerStorageAccountArmId: storageAccount.id
    sites: []
  }
}

// ──────────────────────────────────────────────
// VMware Site (discovery source)
// ──────────────────────────────────────────────

resource vmwareSite 'Microsoft.OffAzure/vmwareSites@2023-06-06' = {
  name: vmwareSiteName
  location: location
  properties: {
    discoverySolutionId: solutionDiscovery.id
    discoveryScenario: 'Migrate'
    agentDetails: {
      keyVaultId: keyVault.id
      keyVaultUri: keyVault.properties.vaultUri
    }
  }
}

// ──────────────────────────────────────────────
// Assessment Project
// ──────────────────────────────────────────────

resource assessmentProject 'Microsoft.Migrate/assessmentProjects@2019-10-01' = {
  name: assessmentProjectName
  location: location
  tags: migrateTags
  properties: {
    publicNetworkAccess: 'Disabled'
    projectStatus: 'Active'
    customerStorageAccountArmId: storageAccount.id
    assessmentSolutionId: solutionAssessment.id
  }
  dependsOn: [
    storageRoleAssignment
    kvSecretsRole
    kvCryptoRole
    kvCertificatesRole
  ]
}

// ──────────────────────────────────────────────
// Private DNS Zones
// ──────────────────────────────────────────────

module dnsZoneBlob 'modules/private-dns-zone.bicep' = {
  name: 'dns-privatelink-blob'
  params: {
    zoneName: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkId: virtualNetworkId
    tags: migrateTags
  }
}

module dnsZoneKeyVault 'modules/private-dns-zone.bicep' = {
  name: 'dns-privatelink-vaultcore'
  params: {
    zoneName: 'privatelink.vaultcore.azure.net'
    virtualNetworkId: virtualNetworkId
    tags: migrateTags
  }
}

module dnsZoneSiteRecovery 'modules/private-dns-zone.bicep' = {
  name: 'dns-privatelink-siterecovery'
  params: {
    zoneName: 'privatelink.siterecovery.windowsazure.com'
    virtualNetworkId: virtualNetworkId
    tags: migrateTags
  }
}

// ──────────────────────────────────────────────
// Private Endpoints
// ──────────────────────────────────────────────

module peMigrateProject 'modules/private-endpoint.bicep' = {
  name: 'pe-migrate-project'
  params: {
    name: '${migrateProjectName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: migrateProject.id
    groupIds: [ 'Default' ]
    tags: migrateTags
  }
}

module peAssessmentProject 'modules/private-endpoint.bicep' = {
  name: 'pe-assessment-project'
  params: {
    name: '${assessmentProjectName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: assessmentProject.id
    groupIds: [ 'Default' ]
    tags: migrateTags
  }
}

module peStorage 'modules/private-endpoint.bicep' = {
  name: 'pe-storage-blob'
  params: {
    name: '${storageAccountName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: storageAccount.id
    groupIds: [ 'blob' ]
    privateDnsZoneId: dnsZoneBlob.outputs.id
    tags: migrateTags
  }
}

module peKeyVault 'modules/private-endpoint.bicep' = {
  name: 'pe-keyvault'
  params: {
    name: '${keyVaultName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: keyVault.id
    groupIds: [ 'vault' ]
    privateDnsZoneId: dnsZoneKeyVault.outputs.id
    tags: migrateTags
  }
}

module peRecoveryVault 'modules/private-endpoint.bicep' = {
  name: 'pe-recovery-vault'
  params: {
    name: '${recoveryVaultName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: recoveryVault.id
    groupIds: [ 'AzureSiteRecovery' ]
    privateDnsZoneId: dnsZoneSiteRecovery.outputs.id
    tags: migrateTags
  }
}

module peMasterSite 'modules/private-endpoint.bicep' = {
  name: 'pe-master-site'
  params: {
    name: '${masterSiteName}-pe'
    location: location
    subnetId: privateEndpointSubnetId
    privateLinkServiceId: masterSite.id
    groupIds: [ 'Default' ]
    tags: migrateTags
  }
}

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────

@description('Resource ID of the Migrate Project.')
output migrateProjectId string = migrateProject.id

@description('Resource ID of the Assessment Project.')
output assessmentProjectId string = assessmentProject.id

@description('Resource ID of the Storage Account.')
output storageAccountId string = storageAccount.id

@description('Resource ID of the Key Vault.')
output keyVaultId string = keyVault.id

@description('Resource ID of the Recovery Services Vault.')
output recoveryVaultId string = recoveryVault.id

@description('Resource ID of the Master Site.')
output masterSiteId string = masterSite.id

@description('System-assigned identity principal ID of the Migrate Project.')
output migrateProjectPrincipalId string = migrateProject.identity.principalId
