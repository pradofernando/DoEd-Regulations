# ============================================================================
# Deploy DoED Regulatory Comments Azure Function Infrastructure
# ============================================================================
#
# This script deploys all Azure resources required for the regulatory
# comments processing Azure Function.
#
# Prerequisites:
# - Azure CLI installed (az --version)
# - Logged in to Azure (az login)
# - Bicep CLI installed (az bicep install)
#
# Usage:
#   .\deploy.ps1 -ResourceGroupName "rg-doed-comments" -Location "eastus" -RegulationsGovApiKey "your-api-key"
#
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rg-doed-comments",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$true)]
    [string]$RegulationsGovApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$DocumentId = "ED-2025-SCC-0481-0001",
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 5,
    
    [Parameter(Mandatory=$false)]
    [int]$GptCapacity = 10
)

# Check if logged in to Azure
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in to Azure. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "DoED Regulatory Comments - Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Subscription: $($account.name)" -ForegroundColor White
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "Location: $Location" -ForegroundColor White
Write-Host "Document ID: $DocumentId" -ForegroundColor White
Write-Host ""

# Create resource group if it doesn't exist
Write-Host "Checking resource group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    Write-Host "Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "Resource group created." -ForegroundColor Green
} else {
    Write-Host "Resource group already exists." -ForegroundColor Green
}

# Deploy Bicep template
Write-Host ""
Write-Host "Deploying infrastructure (this may take 10-15 minutes)..." -ForegroundColor Yellow
Write-Host ""

$deploymentName = "doed-comments-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployment = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file "$PSScriptRoot\main.bicep" `
    --parameters baseName="doed-comments" `
    --parameters location=$Location `
    --parameters gptCapacity=$GptCapacity `
    --parameters regulationsGovApiKey=$RegulationsGovApiKey `
    --parameters documentId=$DocumentId `
    --parameters batchSize=$BatchSize `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deployment failed!" -ForegroundColor Red
    Write-Host $deployment
    exit 1
}

$result = $deployment | ConvertFrom-Json

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "Deployment Succeeded!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Display outputs
Write-Host "Deployment Outputs:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function App Name: $($result.properties.outputs.functionAppName.value)" -ForegroundColor White
Write-Host "Function App URL: $($result.properties.outputs.functionAppUrl.value)" -ForegroundColor White
Write-Host "Storage Account: $($result.properties.outputs.storageAccountName.value)" -ForegroundColor White
Write-Host "AI Hub Name: $($result.properties.outputs.aiHubName.value)" -ForegroundColor White
Write-Host "AI Project Name: $($result.properties.outputs.aiProjectName.value)" -ForegroundColor White
Write-Host "OpenAI Endpoint: $($result.properties.outputs.openAiEndpoint.value)" -ForegroundColor White
Write-Host "Model Deployment: $($result.properties.outputs.modelDeploymentName.value)" -ForegroundColor White
Write-Host ""

Write-Host "============================================" -ForegroundColor Yellow
Write-Host "NEXT STEPS" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Open Azure AI Foundry portal:" -ForegroundColor White
Write-Host "   https://ai.azure.com" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Navigate to your project: $($result.properties.outputs.aiProjectName.value)" -ForegroundColor White
Write-Host ""
Write-Host "3. Create two AI Agents:" -ForegroundColor White
Write-Host "   a) Categorization Agent - for individual comment analysis" -ForegroundColor Gray
Write-Host "   b) Grouping Agent - for collective analysis" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Update the Function App configuration with agent IDs:" -ForegroundColor White
Write-Host "   az functionapp config appsettings set \" -ForegroundColor Gray
Write-Host "     --name $($result.properties.outputs.functionAppName.value) \" -ForegroundColor Gray
Write-Host "     --resource-group $ResourceGroupName \" -ForegroundColor Gray
Write-Host "     --settings CATEGORIZATION_AGENT_ID=<agent-id> GROUPING_AGENT_ID=<agent-id>" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Deploy the Function code:" -ForegroundColor White
Write-Host "   cd azure_func\doed_regulatory_comments_func" -ForegroundColor Gray
Write-Host "   func azure functionapp publish $($result.properties.outputs.functionAppName.value)" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
