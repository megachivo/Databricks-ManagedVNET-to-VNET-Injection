# Azure Databricks VNet Injection Updater

This project provides scripts to automate the process of updating an Azure Databricks workspace to use VNet Injection (or updating its VNet configuration), as described in the [Microsoft documentation](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/update-workspaces).

## Prerequisites

- **Azure CLI (`az`)**: Installed and logged in.
- **`jq`**: Installed (required for Bash script only).
- **PowerShell**: Required for the `.ps1` script (standard in Azure Cloud Shell).

## Usage (PowerShell)

Ideal for running in the Azure Portal (Cloud Shell).

```powershell
./update_databricks_vnet.ps1 `
  -WorkspaceId "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Databricks/workspaces/<workspace-name>" `
  -VNetId "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" `
  -PublicSubnetName "my-public-subnet" `
  -PrivateSubnetName "my-private-subnet"
```

## Usage (Bash)

```bash
./update_databricks_vnet.sh \
  --workspace-id "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Databricks/workspaces/<workspace-name>" \
  --vnet-id "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/virtualNetworks/<vnet-name>" \
  --public-subnet "my-public-subnet" \
  --private-subnet "my-private-subnet"
```

## What it does

1. **Exports** the current ARM template of the specified Databricks Workspace using `az group export`.
2. **Modifies** the template locally (using `jq` in Bash or `ConvertFrom-Json` in PowerShell) to:
   - Update the `apiVersion` to `2025-08-01-preview`.
   - Remove legacy parameters (`vnetAddressPrefix`, `natGatewayName`, `publicIpName`).
   - Add/Update VNet Injection parameters (`customVirtualNetworkId`, `customPublicSubnetName`, `customPrivateSubnetName`).
   - Remove read-only properties like `provisioningState`.
3. **Deploys** the updated template back to the resource group in `Incremental` mode to apply the changes.

## Notes

- Ensure the new VNet and subnets exist and have the correct delegations (Microsoft.Databricks/workspaces) before running this script.
- The script uses the current Azure CLI session. Run `az login` first.
