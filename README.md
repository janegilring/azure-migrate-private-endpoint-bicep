# Azure Migrate with Private Connectivity — Bicep Module

> **Status:** Community reference implementation — not an official Microsoft module.

## Overview

This Bicep module deploys a complete Azure Migrate project with **Private Endpoint–only connectivity**. It addresses the gap where the Azure portal auto-provisions these resources during project creation, but no official IaC template exists for private-connectivity scenarios.

### Problem Statement

When creating an Azure Migrate project with private endpoints via the Azure portal, the service automatically provisions and wires up multiple dependent resources. However:

- No official ARM/Bicep template models this deployment
- The resource model and required sequencing are not documented
- Customers enforcing "IaC-only" policies are blocked

This module was **reverse-engineered from a working portal deployment** and provides a supportable, repeatable IaC path.

## Resources Deployed

| Resource | Type | Private Endpoint Group |
|----------|------|----------------------|
| Storage Account | `Microsoft.Storage/storageAccounts` | `blob` |
| Key Vault | `Microsoft.KeyVault/vaults` | `vault` |
| Recovery Services Vault | `Microsoft.RecoveryServices/vaults` | `AzureSiteRecovery` |
| Migrate Project (hub) | `Microsoft.Migrate/migrateProjects` | `Default` |
| Assessment Project | `Microsoft.Migrate/assessmentProjects` | `Default` |
| Master Site | `Microsoft.OffAzure/MasterSites` | `Default` |
| VMware Site | `Microsoft.OffAzure/VMwareSites` | — |
| Migrate Solutions (3) | `Microsoft.Migrate/migrateProjects/solutions` | — |
| RBAC Role Assignment | `Microsoft.Authorization/roleAssignments` | — |
| Key Vault Access Policy | `Microsoft.KeyVault/vaults/accessPolicies` | — |
| 3 Private DNS Zones | `Microsoft.Network/privateDnsZones` | — |
| 6 Private Endpoints | `Microsoft.Network/privateEndpoints` | — |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  Resource Group                                                     │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │ Migrate      │  │ Assessment   │  │ Recovery Services Vault  │  │
│  │ Project      │──│ Project      │  │ (Site Recovery)          │  │
│  │ (hub)        │  │              │  └──────────┬───────────────┘  │
│  └──────┬───────┘  └──────┬───────┘             │                  │
│         │                 │                      │                  │
│  ┌──────┴───────┐  ┌──────┴───────┐             │                  │
│  │ Master Site  │  │ Storage      │             │                  │
│  │ (appliance)  │  │ Account      │             │                  │
│  └──────┬───────┘  └──────────────┘             │                  │
│         │                                        │                  │
│  ┌──────┴───────┐                                │                  │
│  │ VMware Site  │                                │                  │
│  │ (discovery)  │                                │                  │
│  └──────────────┘                                │                  │
│         │                                        │                  │
│  ┌──────┴───────┐                                │                  │
│  │ Key Vault    │                                │                  │
│  └──────────────┘                                │                  │
│                                                                     │
└─────────────────────────────┬───────────────────────────────────────┘
                              │ Private Endpoints (6)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Existing VNet / Subnet                                             │
│  (privateEndpointNetworkPolicies: Disabled)                         │
│                                                                     │
│  Private DNS Zones:                                                 │
│    • privatelink.blob.core.windows.net                              │
│    • privatelink.vaultcore.azure.net                                │
│    • privatelink.siterecovery.windowsazure.com                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Existing Virtual Network** with a subnet that has `privateEndpointNetworkPolicies` set to `Disabled`
2. **Azure CLI** with Bicep support (`az bicep version` ≥ 0.28)
3. **Permissions:** Contributor + User Access Administrator on the target resource group (User Access Administrator is needed for the RBAC role assignment on the storage account)

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `projectName` | `string` | ✅ | — | Base name for all resources (3-20 chars) |
| `location` | `string` | — | Resource group location | Azure region |
| `privateEndpointSubnetId` | `string` | ✅ | — | Resource ID of the PE subnet |
| `virtualNetworkId` | `string` | ✅ | — | Resource ID of the VNet (for DNS links) |
| `tenantId` | `string` | — | Current tenant | Entra ID tenant |
| `tags` | `object` | — | `{}` | Tags applied to all resources |

## Usage

### Deploy with Azure CLI

```bash
# Create a resource group
az group create \
  --name rg-azure-migrate \
  --location norwayeast

# Deploy the module
az deployment group create \
  --resource-group rg-azure-migrate \
  --template-file bicep/main.bicep \
  --parameters \
    projectName='my-migrate-project' \
    privateEndpointSubnetId='/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>' \
    virtualNetworkId='/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>'
```

### Deploy with Parameters File

```bash
az deployment group create \
  --resource-group rg-azure-migrate \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

### What-If Preview

```bash
az deployment group what-if \
  --resource-group rg-azure-migrate \
  --template-file bicep/main.bicep \
  --parameters bicep/main.bicepparam
```

## File Structure

```
bicep/
├── main.bicep                        # Main orchestration template
├── main.bicepparam                   # Example parameters file
├── bicepconfig.json                  # Enables thisNamespace experimental feature
├── README.md                         # This documentation
└── modules/
    ├── private-endpoint.bicep        # Reusable private endpoint module
    └── private-dns-zone.bicep        # Reusable private DNS zone module
```

## Known Limitations

1. **Bicep type warnings (BCP187):** The `tags` and `identity` properties on `Microsoft.Migrate/migrateProjects` are not in the Bicep type schema but are supported by the Azure REST API. These warnings are cosmetic and do not affect deployment.

2. **Service-managed resources:** After deployment, Azure Migrate may provision additional resources automatically (e.g., `Microsoft.DependencyMap/maps`, `Microsoft.MySqlDiscovery/MySQLSites`, `Microsoft.ApplicationMigration/*`). These are service-managed and should not be included in IaC.

3. **VMware Site identity:** The VMware Site `servicePrincipalIdentityDetails` are populated automatically by the Azure Migrate appliance after registration. The template omits these properties and links the VMware Site to the Discovery Solution via `discoverySolutionId` instead.

4. **Portal PE display:** The portal's Properties blade for the Migrate project shows a "Private endpoint details" table with PE names. This table only displays PEs that were created through the Azure Migrate portal's built-in PE wizard — not standalone PEs created via Bicep/ARM. Our PEs appear as `-` in this table but are **functionally correct** (traffic routes through them, connections are `Approved`, DNS resolves correctly). This is a cosmetic limitation of the portal UI, not a functional issue. Even portal-created deployments show `-` for Key Vault, Storage, and Assessment Project PEs.

5. **Private DNS zones:** This module creates its own DNS zones. If your organization uses centralized DNS zones (e.g., via Azure Landing Zones), pass the existing zone IDs instead or remove the DNS zone module deployments and manage them separately.

6. **Assessment project RP soft-delete:** The Azure Migrate RP retains deleted assessment project names internally. If a deployment fails or a resource group is deleted and recreated with the same `projectName`, the assessment project may fail with `DataPreconditionFailed`. The template mitigates this by appending a resource-group-unique suffix to the assessment project name. If you encounter this error, use a different `projectName` or deploy to a different resource group.

7. **Migrate and Assessment project PE redeployment:** The private endpoint module uses the experimental `this.exists()` function (Bicep ≥ 0.40.2, feature flag `thisNamespace`) to preserve existing PE connections on redeployment. This prevents the `PrivateEndpointConnectionAlreadyExists` error from the Azure Migrate RP on both the Migrate project (`pe-migrate-project`) and Assessment project (`pe-assessment-project`). The feature requires ARM backend support — if the backend has not yet rolled out, fall back to the manual workaround:
   ```bash
   # List existing PE connections on the Migrate project
   az rest --method get \
     --uri "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Migrate/migrateProjects/<name>?api-version=2020-05-01" \
     --query "properties.privateEndpointConnections[].name" -o tsv

   # Delete the PE connection (use the name from above)
   az rest --method delete \
     --uri "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Migrate/migrateProjects/<name>/privateEndpointConnections/<connection-name>?api-version=2020-05-01"
   ```
   For the Assessment project:
   ```bash
   # List existing PE connections on the Assessment project
   az rest --method get \
     --uri "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Migrate/assessmentProjects/<name>?api-version=2020-05-01" \
     --query "properties.privateEndpointConnections[].name" -o tsv

   # Delete the PE connection (use the name from above)
   az rest --method delete \
     --uri "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Migrate/assessmentProjects/<name>/privateEndpointConnections/<connection-name>?api-version=2020-05-01"
   ```
   Other resource types (Storage, Key Vault, Recovery Services) handle PE redeployments correctly.

8. **ALZ Corp policy compatibility — appliance registration requires temporary policy exemption:** When deploying to a Corp Azure Landing Zone subscription with the `Deny-Public-Endpoints` policy, the Bicep module itself deploys successfully (Storage, Key Vault, and Recovery Services Vault all have `publicNetworkAccess: 'Disabled'`). However, the Azure Migrate portal's **"Generate key"** operation (needed for appliance registration) triggers an internal ARM deployment that modifies the Recovery Services Vault without including `publicNetworkAccess: 'Disabled'`, violating the ALZ Deny policy. This is a portal limitation — the portal's internal ARM template is Microsoft-owned and cannot be modified by customers. **Workaround:** Create a temporary, resource-scoped policy exemption on the Recovery Services Vault **before** clicking "Generate key":
    ```bash
    # Create exemption (before clicking "Generate key")
    az policy exemption create \
      --name "rsv-migrate-registration" \
      --policy-assignment "<policy-assignment-id>" \
      --scope "<rsv-resource-id>" \
      --exemption-category Waiver \
      --expiration-date "<7-days-from-now>" \
      --description "Temporary exemption for Azure Migrate appliance registration. Portal Generate key omits publicNetworkAccess."

    # Remove after appliance registration completes
    az policy exemption delete \
      --name "rsv-migrate-registration" \
      --scope "<rsv-resource-id>"
    ```
    Notes: The `--policy-assignment` value can be found via `az policy assignment list --scope "/providers/Microsoft.Management/managementGroups/<mg-name>" --query "[?contains(name, 'Deny-Public')]"`. The exemption is scoped to the RSV resource only (not the resource group) and should be time-bounded (7-day expiration recommended).

9. **Redeployment to same resource group:** The module deploys successfully on initial deployment to a fresh resource group. However, re-deploying to the same resource group will fail on the Assessment project and Migrate project private endpoints due to the `PrivateEndpointConnectionAlreadyExists` error described in limitation #7. The Recovery Services Vault identity issue is now resolved — the Bicep template includes `identity: { type: 'SystemAssigned' }` to ensure the system-assigned managed identity is preserved on subsequent deployments. **Remaining redeployment blocker:** The PE idempotency issue on Assessment and Migrate projects (limitation #7). **Recommendation:** If you need to redeploy the module, deploy to a new resource group, or use the manual workaround provided in limitation #7 to delete existing PE connections before redeploying.

10. **RSV managed identity on redeployment:** The portal's **"Generate key"** operation adds a system-assigned managed identity to the Recovery Services Vault. The Bicep template includes `identity: { type: 'SystemAssigned' }` to ensure this identity is preserved on subsequent deployments. Without this, redeployment after key generation would fail with `ManagedIdentityDetailsNotPresent: Managed Identity details once set needs to present in subsequent PUT Request for the vault`.

## Outputs

| Output | Description |
|--------|-------------|
| `migrateProjectId` | Resource ID of the Migrate Project |
| `assessmentProjectId` | Resource ID of the Assessment Project |
| `storageAccountId` | Resource ID of the Storage Account |
| `keyVaultId` | Resource ID of the Key Vault |
| `recoveryVaultId` | Resource ID of the Recovery Services Vault |
| `masterSiteId` | Resource ID of the Master Site |
| `migrateProjectPrincipalId` | System-assigned identity principal ID |

## Related Links

- [Azure Migrate documentation](https://learn.microsoft.com/en-us/azure/migrate/migrate-services-overview)
- [Use Azure Migrate with private endpoints](https://learn.microsoft.com/en-us/azure/migrate/how-to-use-azure-migrate-with-private-endpoints)
- [bicep-types-az GitHub Issue #2707](https://github.com/Azure/bicep-types-az/issues/2707) — Tracking issue for missing properties in Bicep type definitions
