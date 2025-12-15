<#
.SYNOPSIS
    Updates an Azure Databricks workspace to use VNet Injection (or updates its VNet config) using Azure CLI and PowerShell.
    Can be run from Azure Cloud Shell (PowerShell).

.DESCRIPTION
    This script exports the current ARM template of a Databricks workspace, modifies it to include VNet injection parameters,
    removes legacy parameters, and redeploys it.

.EXAMPLE
    ./update_databricks_vnet.ps1 -WorkspaceId "/subscriptions/.../workspaces/my-ws" -VNetId "/subscriptions/.../virtualNetworks/my-vnet" -PublicSubnetName "pub-subnet" -PrivateSubnetName "priv-subnet"
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Resource ID of the Databricks Workspace")]
    [string]$WorkspaceId,

    [Parameter(Mandatory=$true, HelpMessage="Resource ID of the target Virtual Network")]
    [string]$VNetId,

    [Parameter(Mandatory=$true, HelpMessage="Name of the Public Subnet")]
    [string]$PublicSubnetName,

    [Parameter(Mandatory=$true, HelpMessage="Name of the Private Subnet")]
    [string]$PrivateSubnetName
)

$ErrorActionPreference = "Stop"

# Check for Azure CLI
if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI ('az') is not installed or not in the path."
    exit 1
}

Write-Host "Parsing Workspace ID..." -ForegroundColor Cyan
# Regex to extract components from Resource ID
if ($WorkspaceId -match "subscriptions/(?<subId>[^/]+)/resourceGroups/(?<rgName>[^/]+)/.+/workspaces/(?<wsName>[^/]+)") {
    $SubscriptionId = $Matches['subId']
    $ResourceGroup = $Matches['rgName']
    $WorkspaceName = $Matches['wsName']
} else {
    Write-Error "Invalid Workspace ID format."
    exit 1
}

Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Workspace: $WorkspaceName"

# Set Subscription
Write-Host "Setting active subscription..." -ForegroundColor Cyan
az account set --subscription $SubscriptionId

# Validate VNet existence
Write-Host "Validating VNet existence..." -ForegroundColor Cyan
if (-not (az network vnet show --ids $VNetId --query "id" -o tsv 2>$null)) {
    Write-Warning "VNet with ID '$VNetId' not found."
    do {
        $VNetId = Read-Host "Please re-enter the valid VNet Resource ID"
    } while (-not (az network vnet show --ids $VNetId --query "id" -o tsv 2>$null))
}

# Extract VNet name and Resource Group for subnet validation
if ($VNetId -match "resourceGroups/(?<rg>[^/]+)/.+/virtualNetworks/(?<name>[^/]+)") {
    $VNetRG = $Matches['rg']
    $VNetName = $Matches['name']
}

# Validate Public Subnet
Write-Host "Validating Public Subnet..." -ForegroundColor Cyan
if (-not (az network vnet subnet show --resource-group $VNetRG --vnet-name $VNetName --name $PublicSubnetName --query "id" -o tsv 2>$null)) {
    Write-Warning "Public Subnet '$PublicSubnetName' not found in VNet '$VNetName'."
    do {
        $PublicSubnetName = Read-Host "Please re-enter the valid Public Subnet Name"
    } while (-not (az network vnet subnet show --resource-group $VNetRG --vnet-name $VNetName --name $PublicSubnetName --query "id" -o tsv 2>$null))
}

# Validate Private Subnet
Write-Host "Validating Private Subnet..." -ForegroundColor Cyan
if (-not (az network vnet subnet show --resource-group $VNetRG --vnet-name $VNetName --name $PrivateSubnetName --query "id" -o tsv 2>$null)) {
    Write-Warning "Private Subnet '$PrivateSubnetName' not found in VNet '$VNetName'."
    do {
        $PrivateSubnetName = Read-Host "Please re-enter the valid Private Subnet Name"
    } while (-not (az network vnet subnet show --resource-group $VNetRG --vnet-name $VNetName --name $PrivateSubnetName --query "id" -o tsv 2>$null))
}

# Export Template
Write-Host "Exporting current ARM template..." -ForegroundColor Cyan
$TemplateFile = "exported_template.json"
$ModifiedFile = "modified_template.json"

az group export --resource-group $ResourceGroup --resource-ids $WorkspaceId --output json > $TemplateFile

if (-not (Test-Path $TemplateFile) -or (Get-Item $TemplateFile).Length -eq 0) {
    Write-Error "Failed to export template."
    exit 1
}

# Modify JSON using PowerShell
Write-Host "Modifying template for VNet injection..." -ForegroundColor Cyan

try {
    $json = Get-Content -Path $TemplateFile -Raw | ConvertFrom-Json

    # Locate the Databricks workspace resource
    $resources = $json.resources
    $found = $false

    foreach ($res in $resources) {
        if ($res.type -eq "Microsoft.Databricks/workspaces") {
            $found = $true
            
            # Update API Version
            $res.apiVersion = "2025-08-01-preview"

            # Remove legacy properties if they exist
            $legacyProps = @("vnetAddressPrefix", "natGatewayName", "publicIpName", "storageAccountName", "storageAccountSkuName")
            if ($res.properties.parameters) {
                foreach ($prop in $legacyProps) {
                    if ($res.properties.parameters.PSObject.Properties.Match($prop)) {
                        $res.properties.parameters.PSObject.Properties.Remove($prop)
                    }
                }
            }

            # Remove read-only provisioningState
            if ($res.properties.PSObject.Properties.Match("provisioningState")) {
                $res.properties.PSObject.Properties.Remove("provisioningState")
            }

            # Ensure parameters object exists
            if (-not $res.properties.parameters) {
                $res.properties | Add-Member -MemberType NoteProperty -Name "parameters" -Value ([PSCustomObject]@{})
            }

            # Add/Update VNet Injection parameters
            # Note: We use Add-Member -Force to overwrite if exists or just standard assignment
            # Using a helper object to construct the parameter structure expected by ARM: { "value": "..." }
            
            $res.properties.parameters | Add-Member -MemberType NoteProperty -Name "customVirtualNetworkId" -Value ([PSCustomObject]@{ value = $VNetId }) -Force
            $res.properties.parameters | Add-Member -MemberType NoteProperty -Name "customPublicSubnetName" -Value ([PSCustomObject]@{ value = $PublicSubnetName }) -Force
            $res.properties.parameters | Add-Member -MemberType NoteProperty -Name "customPrivateSubnetName" -Value ([PSCustomObject]@{ value = $PrivateSubnetName }) -Force
        }
    }

    if (-not $found) {
        Write-Error "Could not find Microsoft.Databricks/workspaces resource in the exported template."
        exit 1
    }

    # Save modified JSON
    $json | ConvertTo-Json -Depth 100 | Set-Content -Path $ModifiedFile
}
catch {
    Write-Error "Error processing JSON: $_"
    exit 1
}

# Parameters Handling
# When exporting, some parameters might be parameterized in the ARM template but not have default values in the 'parameters' section.
# We need to ensure we pass the workspace name if it was parameterized.

$deploymentParams = @()
if ($json.parameters -and $json.parameters.PSObject.Properties.Match("workspaceName")) {
   # Check if it lacks a default value
   if (-not $json.parameters.workspaceName.defaultValue) {
       $deploymentParams += "--parameters workspaceName=$WorkspaceName"
   }
}
# Also check for any other parameters that look like the workspace name parameter that the user mentioned
# The export command often auto-generates parameter names like "workspaces_name_name"

# To be safe, we can try to detect parameters that don't have default values and see if we can fill them, 
# but for now, let's just use the --parameters argument if we detect the standard pattern or pass the template as-is 
# and let the user interact if needed. But since this is a script, we should try to automate.

# BETTER APPROACH:
# We will inspect the 'parameters' section of the exported JSON.
# Any parameter that does NOT have a 'defaultValue' needs to be supplied.
# We know 'workspaceName' is likely one of them.

$paramsToPass = @{}

if ($json.parameters) {
    foreach ($paramName in $json.parameters.PSObject.Properties.Name) {
        $paramObj = $json.parameters.$paramName
        if (-not $paramObj.defaultValue) {
            # Try to guess the value based on name
            if ($paramName -like "*workspace*" -or $paramName -like "*name*") {
                $paramsToPass[$paramName] = $WorkspaceName
            }
        }
    }
}

$paramArgs = @()
foreach ($key in $paramsToPass.Keys) {
    $paramArgs += "--parameters"
    $paramArgs += "$key=$($paramsToPass[$key])"
}

# Deploy
Write-Host "Deploying updated template..." -ForegroundColor Cyan
az deployment group create `
    --resource-group $ResourceGroup `
    --name "vnet-update-deployment-$(Get-Date -Format 'yyyyMMddHHmm')" `
    --template-file $ModifiedFile `
    --mode Incremental `
    @paramArgs

Write-Host "Deployment initiated successfully." -ForegroundColor Green

