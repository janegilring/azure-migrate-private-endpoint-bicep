// Private DNS Zone module
// Creates a private DNS zone and optionally links it to a virtual network.

@description('FQDN of the private DNS zone (e.g., privatelink.vaultcore.azure.net).')
param zoneName string

@description('Resource ID of the virtual network to link to the DNS zone.')
param virtualNetworkId string

@description('Whether to enable auto-registration of VM DNS records.')
param registrationEnabled bool = false

@description('Tags to apply to the DNS zone.')
param tags object = {}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${last(split(virtualNetworkId, '/'))}-link'
  parent: dnsZone
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: registrationEnabled
  }
}

@description('Resource ID of the private DNS zone.')
output id string = dnsZone.id

@description('Name of the private DNS zone.')
output name string = dnsZone.name
