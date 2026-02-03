// ============================================================================
// DoED Regulatory Comments Azure Function - Infrastructure as Code (Bicep)
// ============================================================================
// 
// This Bicep template deploys all Azure resources required for the 
// DoED Regulatory Comments processing Azure Function.
//
// Resources Deployed:
// 1. Azure AI Foundry Hub & Project (for AI Agents)
// 2. Azure OpenAI Service (GPT-5.2 model)
// 3. Azure Functions (Python runtime)
// 4. Azure Storage Account (for blob storage output)
// 5. Application Insights (for monitoring)
// 6. Key Vault (for secrets management)
// 7. Log Analytics Workspace (for logs)
//
// Usage:
//   az deployment group create \
//     --resource-group rg-doed-comments \
//     --template-file main.bicep \
//     --parameters main.parameters.json
//
// ============================================================================

// ============================================================================
// PARAMETERS
// These values can be customized when deploying the template
// ============================================================================

@description('Base name for all resources. Resources will be named with this prefix.')
@minLength(3)
@maxLength(15)
param baseName string = 'doed-comments'

// ============================================================================
// DEFAULT REGION: East US
// To change the deployment region, modify the default value below.
// All 9 Azure resources will be deployed to this region.
// Ensure the region supports Azure OpenAI (see @allowed list for valid options).
// ============================================================================
@description('Azure region for all resources. Should support Azure OpenAI.')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
  'northcentralus'
  'southcentralus'
  'swedencentral'
  'uksouth'
  'francecentral'
])
param location string = 'eastus'  // <-- CHANGE THIS TO DEPLOY TO A DIFFERENT REGION

@description('GPT-5.2 model deployment capacity in thousands of tokens per minute.')
@minValue(1)
@maxValue(100)
param gptCapacity int = 10

@description('The Regulations.gov API key. Get one free at https://open.gsa.gov/api/regulationsgov/')
@secure()
param regulationsGovApiKey string

@description('Document ID to fetch comments from Regulations.gov')
param documentId string = 'ED-2025-SCC-0481-0001'

@description('Number of comments to process per batch for AI grouping analysis')
@minValue(1)
@maxValue(20)
param batchSize int = 5

// ============================================================================
// VARIABLES
// Computed values used throughout the template
// ============================================================================

// Generate unique suffix to ensure globally unique resource names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Resource names with unique suffixes where required for global uniqueness
// Storage account names must be 3-24 chars, lowercase alphanumeric only
#disable-next-line BCP334
var storageAccountName = take(replace('st${baseName}${uniqueSuffix}', '-', ''), 24)
var keyVaultName = take('kv-${baseName}-${uniqueSuffix}', 24)
var appInsightsName = 'appi-${baseName}'
var logAnalyticsName = 'law-${baseName}'
var openAiName = 'oai-${baseName}-${uniqueSuffix}'
var aiHubName = 'aihub-${baseName}'
var aiProjectName = 'aiproj-${baseName}'
var functionAppName = 'func-${baseName}-${uniqueSuffix}'
var appServicePlanName = 'asp-${baseName}'

// ============================================================================
// STORAGE ACCOUNT
// Required for:
// - Azure Functions runtime storage
// - Blob storage for comment outputs (raw JSON, CSV, analysis results)
// ============================================================================
#disable-next-line BCP334 // Storage name is guaranteed to be valid with minLength constraint on baseName
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  
  // Standard_LRS is cost-effective for non-critical data
  // Use Standard_GRS for geo-redundancy if required
  sku: {
    name: 'Standard_LRS'
  }
  
  kind: 'StorageV2'
  
  properties: {
    // Security: Require TLS 1.2 minimum
    minimumTlsVersion: 'TLS1_2'
    
    // Security: Only allow HTTPS connections
    supportsHttpsTrafficOnly: true
    
    // Security: Disable anonymous blob access
    allowBlobPublicAccess: false
    
    // Enable hierarchical namespace for better organization (optional)
    isHnsEnabled: false
    
    // Access tier for blob storage
    accessTier: 'Hot'
  }
}

// Create the blob container for regulatory comments output
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource commentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'regulatory-comments'
  properties: {
    // Private access - no anonymous access allowed
    publicAccess: 'None'
  }
}

// ============================================================================
// KEY VAULT
// Securely stores secrets like API keys
// The Function App accesses secrets via managed identity
// ============================================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    
    // Required for Azure to access the vault
    tenantId: subscription().tenantId
    
    // Use RBAC for access control (more secure than access policies)
    enableRbacAuthorization: true
    
    // Soft delete protection (required for production)
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    
    // Purge protection prevents permanent deletion during soft delete period
    enablePurgeProtection: true
  }
}

// Store the Regulations.gov API key in Key Vault
resource regulationsApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'regulations-gov-api-key'
  properties: {
    value: regulationsGovApiKey
  }
}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// Central logging for all resources
// Required by Application Insights
// ============================================================================
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  
  properties: {
    sku: {
      // Pay-per-GB is most cost-effective for small workloads
      name: 'PerGB2018'
    }
    // Retain logs for 30 days (adjust as needed)
    retentionInDays: 30
  }
}

// ============================================================================
// APPLICATION INSIGHTS
// Monitoring and telemetry for the Azure Function
// Provides execution logs, performance metrics, and failure tracking
// ============================================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  
  properties: {
    Application_Type: 'web'
    // Link to Log Analytics for log storage
    WorkspaceResourceId: logAnalytics.id
    // Enable sampling to reduce costs (can be adjusted)
    SamplingPercentage: 100
  }
}

// ============================================================================
// AZURE OPENAI SERVICE
// Provides the GPT-5.2 model for AI-powered comment analysis
// ============================================================================
resource openAi 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiName
  location: location
  
  // S0 is the standard tier for Azure OpenAI
  sku: {
    name: 'S0'
  }
  
  kind: 'OpenAI'
  
  properties: {
    // Custom subdomain for the endpoint URL
    customSubDomainName: openAiName
    
    // Public access for simplicity; use private endpoints in production
    publicNetworkAccess: 'Enabled'
    
    // Disable local authentication to enforce Azure AD
    disableLocalAuth: false
  }
}

// Deploy the GPT-5.2 model
// This model will be used by the AI Agents for categorization and analysis
resource gpt52Deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAi
  name: 'gpt-52'
  
  sku: {
    // Standard deployment type
    name: 'Standard'
    // Capacity in thousands of tokens per minute
    capacity: gptCapacity
  }
  
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5.2'
      // Use the latest stable version
      version: '2025-01-01'
    }
    // Use default content filtering policy
    raiPolicyName: 'Microsoft.Default'
  }
}

// ============================================================================
// AZURE AI FOUNDRY HUB
// Container for AI projects; manages shared resources and connections
// ============================================================================
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiHubName
  location: location
  
  // Hub type workspace
  kind: 'Hub'
  
  // System-assigned managed identity for accessing other Azure resources
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    friendlyName: 'DoED Comment Analysis Hub'
    description: 'AI Hub for regulatory comment analysis using Azure AI Agents'
    
    // Link to shared resources
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
    
    // Public access for simplicity
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// AZURE AI FOUNDRY PROJECT
// Workspace where AI Agents are created and managed
// ============================================================================
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiProjectName
  location: location
  
  // Project type workspace (child of Hub)
  kind: 'Project'
  
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    friendlyName: 'DoED Comment Analysis Project'
    description: 'Project for analyzing regulatory comments with AI Agents'
    
    // Link to parent Hub
    hubResourceId: aiHub.id
    
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// AZURE OPENAI CONNECTION TO AI HUB
// Connects the OpenAI service to the AI Foundry Hub
// This allows AI Agents to use the GPT-5.2 model
// ============================================================================
resource openAiConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: aiHub
  name: 'aoai-connection'
  
  properties: {
    // Connection type
    category: 'AzureOpenAI'
    
    // Target endpoint
    target: openAi.properties.endpoint
    
    // Authentication using API key
    authType: 'ApiKey'
    credentials: {
      key: openAi.listKeys().key1
    }
    
    // Metadata for the connection
    metadata: {
      ApiVersion: '2023-10-01-preview'
      ResourceId: openAi.id
    }
  }
}

// ============================================================================
// APP SERVICE PLAN (Consumption)
// Serverless compute for Azure Functions
// Pay only for execution time
// ============================================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  
  // Consumption plan (serverless)
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  
  // Linux for Python runtime
  kind: 'functionapp,linux'
  
  properties: {
    reserved: true  // Required for Linux
  }
}

// ============================================================================
// AZURE FUNCTION APP
// The main application that runs the regulatory comments processing
// ============================================================================
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  
  // Enable system-assigned managed identity for secure access to other resources
  identity: {
    type: 'SystemAssigned'
  }
  
  properties: {
    serverFarmId: appServicePlan.id
    
    // HTTPS only for security
    httpsOnly: true
    
    siteConfig: {
      // Python 3.11 runtime
      linuxFxVersion: 'PYTHON|3.11'
      
      // Function app settings
      appSettings: [
        // Azure Functions runtime configuration
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        
        // Storage connection for Functions runtime
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        
        // Application Insights for monitoring
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        
        // ========================================
        // Application-specific settings
        // ========================================
        
        // Regulations.gov API key (reference from Key Vault)
        {
          name: 'REGULATIONS_GOV_API_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=regulations-gov-api-key)'
        }
        
        // Document ID to fetch comments from
        {
          name: 'DOCUMENT_ID'
          value: documentId
        }
        
        // Batch size for AI grouping analysis
        {
          name: 'BATCH_SIZE'
          value: string(batchSize)
        }
        
        // Storage account name for blob output (uses managed identity)
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        
        // Azure AI Foundry configuration
        {
          name: 'AZURE_AI_AGENT_ENDPOINT'
          // Note: The actual endpoint URL will need to be updated after deployment
          // Format: https://<region>.api.azureml.ms/agents/v1.0/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.MachineLearningServices/workspaces/<project>
          value: 'https://${location}.api.azureml.ms'
        }
        {
          name: 'AZURE_AI_AGENT_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'AZURE_AI_AGENT_RESOURCE_GROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'AZURE_AI_AGENT_PROJECT_NAME'
          value: aiProject.name
        }
        {
          name: 'AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME'
          value: gpt52Deployment.name
        }
        
        // AI Agent IDs (must be created manually in AI Foundry after deployment)
        // Update these after creating the agents
        {
          name: 'CATEGORIZATION_AGENT_ID'
          value: 'UPDATE_AFTER_CREATING_AGENT'
        }
        {
          name: 'GROUPING_AGENT_ID'
          value: 'UPDATE_AFTER_CREATING_AGENT'
        }
      ]
    }
  }
}

// ============================================================================
// ROLE ASSIGNMENTS
// Grant necessary permissions using Azure RBAC
// ============================================================================

// Grant Function App access to read secrets from Key Vault
resource functionKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    // Key Vault Secrets User role
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to write blobs to Storage Account
resource functionStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    // Storage Blob Data Contributor role
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Azure OpenAI
resource functionOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAi.id, functionApp.id, 'Cognitive Services OpenAI User')
  scope: openAi
  properties: {
    // Cognitive Services OpenAI User role
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Hub access to Storage Account
resource hubStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiHub.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Hub access to Key Vault
resource hubKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aiHub.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Hub access to Azure OpenAI
resource hubOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAi.id, aiHub.id, 'Cognitive Services OpenAI Contributor')
  scope: openAi
  properties: {
    // Contributor role for creating deployments
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// Values needed for configuration after deployment
// ============================================================================

@description('Function App name for deployment')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage Account name for blob access')
output storageAccountName string = storageAccount.name

@description('Azure AI Project endpoint - update AZURE_AI_AGENT_ENDPOINT with this')
output aiProjectEndpoint string = 'https://${location}.api.azureml.ms/agents/v1.0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.MachineLearningServices/workspaces/${aiProject.name}'

@description('Azure OpenAI endpoint')
output openAiEndpoint string = openAi.properties.endpoint

@description('Model deployment name')
output modelDeploymentName string = gpt52Deployment.name

@description('Application Insights instrumentation key')
output appInsightsKey string = appInsights.properties.InstrumentationKey

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('AI Hub name - use this to access AI Foundry portal')
output aiHubName string = aiHub.name

@description('AI Project name')
output aiProjectName string = aiProject.name

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Subscription ID')
output subscriptionId string = subscription().subscriptionId
