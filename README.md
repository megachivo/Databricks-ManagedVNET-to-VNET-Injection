# Azure Databricks VNet Injection Updater

This project provides a PowerShell script to automate the process of updating an Azure Databricks workspace to use VNet Injection (or updating its VNet configuration), as described in the [Microsoft documentation](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/update-workspaces).

## Prerequisites

- **Azure CLI (`az`)**: Installed and logged in.
- **PowerShell**: Required to run the script (available in Azure Cloud Shell).
- **Virtual Network (VNet) Configuration**:
  - Must be in the **same region** as the Databricks Workspace.
  - **Subnets**: Requires two subnets (public and private).
  - **Delegation**: Each subnet must be delegated to `Microsoft.Databricks/workspaces`.
  - **Network Security Group (NSG)**: Each subnet must have an NSG associated (typically an empty one).
  - **Outbound Connectivity**: If using No Public IP (NPIP) / Secure Cluster Connectivity, an explicit outbound method (NAT Gateway or Firewall) must be configured on the subnets.

## Usage

This script is ideal for running in the **Azure Cloud Shell** (PowerShell mode).

```powershell
./update_databricks_vnet.ps1 `
  -WorkspaceId "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Databricks/workspaces/<workspace-name>" `
  -VNetId "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" `
  -PublicSubnetName "my-public-subnet" `
  -PrivateSubnetName "my-private-subnet"
```

### Script Features

1. **Validation**: Checks if the provided VNet and Subnets exist.
   - **Region Check**: Ensures the VNet is in the same region as the Workspace.
   - **Delegation Check**: Ensures subnets are delegated to `Microsoft.Databricks/workspaces`.
   - **NSG Check**: Ensures subnets have a Network Security Group associated.
2. **Export**: Exports the current ARM template of the specified Databricks Workspace.
3. **Modification**:
   - Updates the `apiVersion` to `2025-08-01-preview`.
   - Removes legacy parameters (`vnetAddressPrefix`, `natGatewayName`, `publicIpName`).
   - Removes existing storage account parameters to prevent deployment conflicts.
   - Inject new VNet parameters (`customVirtualNetworkId`, `customPublicSubnetName`, `customPrivateSubnetName`).
   - Automatically handles missing default values for workspace name parameters.
4. **Deployment**: Redeploys the updated template to apply the changes.

## Notes

- Ensure the new VNet and subnets have the correct delegations (`Microsoft.Databricks/workspaces`) before running this script.
- The script uses the current Azure CLI session. Run `az login` first if running locally.
