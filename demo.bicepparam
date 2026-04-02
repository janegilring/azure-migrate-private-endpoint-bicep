using './main.bicep'

// ──────────────────────────────────────────────
// Example parameters for Azure Migrate with Private Connectivity
// ──────────────────────────────────────────────
// Update the values below to match your environment.

param projectName = 'azure-migrate-demo'
param location = 'norwayeast'

// Provide the resource ID of your existing subnet for private endpoints.
// The subnet must have privateEndpointNetworkPolicies set to 'Disabled'.
param privateEndpointSubnetId = '/subscriptions/bb28588b-7215-41ce-b24f-6ac35226c2c9/resourceGroups/arcbox-itpro-rg/providers/Microsoft.Network/virtualNetworks/ArcBox-VNet/subnets/PESubnet'

// Provide the resource ID of your existing virtual network (for DNS zone VNet links).
param virtualNetworkId = '/subscriptions/bb28588b-7215-41ce-b24f-6ac35226c2c9/resourceGroups/arcbox-itpro-rg/providers/Microsoft.Network/virtualNetworks/ArcBox-VNet'

// Object ID of the principal that should receive Key Vault access policies.
// Leave empty if using RBAC or configuring access policies separately.
param keyVaultAccessPolicyObjectId = ''

param tags = {
  environment: 'production'
  system: 'Azure Migrate'
}
