// Private Endpoint reusable module
// Creates a private endpoint, optional private DNS zone group, and links to a target resource.
// Uses this.exists() to preserve existing PE connections on redeployment, avoiding
// PrivateEndpointConnectionAlreadyExists errors from resource providers that don't
// handle idempotent connection requests (e.g., Microsoft.Migrate).

@description('Name of the private endpoint.')
param name string

@description('Azure region for the private endpoint.')
param location string

@description('Resource ID of the subnet where the private endpoint will be placed.')
param subnetId string

@description('Resource ID of the target resource to connect via private link.')
param privateLinkServiceId string

@description('Group ID(s) for the private link connection (e.g., "blob", "vault", "Default", "AzureSiteRecovery").')
param groupIds array

@description('Optional: Resource ID of the private DNS zone to associate with this endpoint.')
param privateDnsZoneId string = ''

@description('Tags to apply to the private endpoint.')
param tags object = {}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    // On redeployment, preserve the existing connections to avoid duplicate
    // connection errors from the target resource provider. When the PE does
    // not yet exist, create new connections normally.
    privateLinkServiceConnections: this.exists()
      ? this.existingResource().?properties.?privateLinkServiceConnections ?? []
      : [
          {
            name: name
            properties: {
              privateLinkServiceId: privateLinkServiceId
              groupIds: groupIds
            }
          }
        ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (!empty(privateDnsZoneId)) {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(last(split(privateDnsZoneId, '/')), '.', '-')
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

@description('Resource ID of the private endpoint.')
output id string = privateEndpoint.id

@description('Name of the private endpoint.')
output name string = privateEndpoint.name
