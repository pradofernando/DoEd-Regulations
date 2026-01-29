# DoED Regulatory Comments Azure Function

Automated Azure Function that runs daily at 3AM EST to fetch, process, and analyze public comments from Regulations.gov.

## Overview

This Azure Function automates the complete workflow:

1. **Fetch Comments** - Retrieves comments from Regulations.gov API
2. **Extract Attachments** - Downloads and extracts text from PDF/DOCX attachments
3. **Consolidate Data** - Combines inline text and attachment text into CSV format
4. **AI Categorization** - Uses Azure AI Agent to categorize each comment
5. **Group Analysis** - Analyzes and groups similar comments with AI Agent
6. **Store Results** - Saves all outputs to Azure Blob Storage

## Schedule

- **Trigger**: Timer Trigger (CRON: `0 0 8 * * *`)
- **Schedule**: Daily at 3AM EST (8AM UTC)
- **Execution**: Automatic, no manual intervention required

## Prerequisites

### Azure Resources Required

1. **Azure Functions** - Python 3.9+ runtime
2. **Azure Storage Account** - For blob storage output
3. **Azure OpenAI** - AI Agents for analysis
4. **Regulations.gov API Key** - Free from https://open.gsa.gov/api/regulationsgov/

### Python Dependencies

All dependencies are listed in `requirements.txt`:
- `azure-functions` - Azure Functions runtime
- `semantic-kernel` - Azure AI Agent integration
- `azure-identity` - Authentication
- `azure-storage-blob` - Blob storage
- `requests` - HTTP requests
- `PyPDF2` - PDF text extraction
- `python-docx` - DOCX text extraction

## Configuration

### Environment Variables

Configure these settings in Azure Portal → Function App → Configuration or in `local.settings.json` for local development:

| Variable | Description | Example |
|----------|-------------|---------|
| `REGULATIONS_GOV_API_KEY` | API key from Regulations.gov | `abc123...` |
| `DOCUMENT_ID` | Document ID to fetch comments from | `ED-2025-SCC-0481-0001` |
| `CATEGORIZATION_AGENT_ID` | Azure AI Agent ID for categorization | `asst_COd3...` |
| `GROUPING_AGENT_ID` | Azure AI Agent ID for grouping | `asst_mXQ...` |
| `BATCH_SIZE` | Number of comments per batch for grouping | `5` |
| `MAX_COMMENTS` | Limit number of comments to process (empty = all) | `10` or empty |
| `AZURE_STORAGE_ACCOUNT_NAME` | Storage account name for blob storage (uses managed identity) | `storeregulatory` |
| `AZURE_AI_AGENT_ENDPOINT` | Azure AI Foundry project endpoint | `https://your-resource.services.ai.azure.com/api/projects/your-project` |
| `AZURE_AI_AGENT_SUBSCRIPTION_ID` | Azure subscription ID | `04111ead-4a81-46d8-bc64-...` |
| `AZURE_AI_AGENT_RESOURCE_GROUP_NAME` | Resource group name for AI project | `rg-your-project` |
| `AZURE_AI_AGENT_PROJECT_NAME` | Azure AI Foundry project name | `your-project-name` |
| `AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME` | Model deployment name in Azure OpenAI | `gpt-4-mini` |

### Local Settings (local.settings.json)

```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "REGULATIONS_GOV_API_KEY": "your_api_key",
    "DOCUMENT_ID": "ED-2025-SCC-0481-0001",
    "CATEGORIZATION_AGENT_ID": "asst_COd3DzxCx0SUmQfXKwK0tcl5",
    "GROUPING_AGENT_ID": "asst_mXQoLXXZyOC1eqovZSTxHRKW",
    "BATCH_SIZE": "5",
    "MAX_COMMENTS": "",
    "AZURE_STORAGE_ACCOUNT_NAME": "your_storage_account_name",
    "AZURE_AI_AGENT_ENDPOINT": "https://your-resource.services.ai.azure.com/api/projects/your-project",
    "AZURE_AI_AGENT_SUBSCRIPTION_ID": "your-subscription-id",
    "AZURE_AI_AGENT_RESOURCE_GROUP_NAME": "rg-your-resource-group",
    "AZURE_AI_AGENT_PROJECT_NAME": "your-project-name",
    "AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME": "your-model-deployment"
  }
}
```

**Note:** Copy `local.settings.json.example` to `local.settings.json` and update with your actual values.

## Local Development

### Setup

```powershell
# Navigate to function directory
cd azure_func\doed_regulatory_comments_func

# Create virtual environment (optional but recommended)
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt

# Install Azure Functions Core Tools (if not already installed)
# Download from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local
```

### Configure Settings

1. Copy the example settings and add your API keys:
   ```powershell
   # Edit local.settings.json with your API keys
   notepad local.settings.json
   ```

2. Add your actual API keys and connection strings

### Run Locally

```powershell
# Start the function locally
func start

# The function will show:
# - HTTP endpoint for manual triggering (if needed)
# - Next scheduled run time
# - Logs in real-time
```

### Test Manually

To trigger the function manually without waiting for the schedule:

```powershell
# Add run_on_startup=True to the decorator temporarily:
# @app.schedule(schedule="0 0 8 * * *", arg_name="myTimer", run_on_startup=True)

# Or use the Azure Functions Core Tools Admin endpoint
# POST to the admin trigger endpoint shown in func start output
```

## Deployment to Azure

### Option 1: VS Code Extension

1. Install "Azure Functions" extension in VS Code
2. Sign in to Azure
3. Click "Deploy to Function App" in the Azure tab
4. Select or create a Function App
5. Wait for deployment to complete

### Option 2: Azure CLI

```powershell
# Login to Azure
az login

# Create a resource group (if needed)
az group create --name rg-regulatory-comments --location eastus

# Create a storage account (if needed)
az storage account create --name storegulatorycomments --resource-group rg-regulatory-comments --location eastus --sku Standard_LRS

# Create a Function App
az functionapp create `
  --name func-regulatory-comments `
  --resource-group rg-regulatory-comments `
  --storage-account storegulatorycomments `
  --consumption-plan-location eastus `
  --runtime python `
  --runtime-version 3.9 `
  --functions-version 4 `
  --os-type Linux

# Deploy the function
cd c:\src\doed_regulatory_comment_project\azure_func\doed_regulatory_comments_func
func azure functionapp publish func-regulatory-comments
```

### Option 3: GitHub Actions

See `.github/workflows/azure-function-deploy.yml` for CI/CD setup.

### Post-Deployment Configuration

After deployment, configure the environment variables in Azure Portal:

1. Go to Azure Portal → Function App
2. Select "Configuration" under Settings
3. Add Application Settings for all environment variables listed above
4. Click "Save"
5. Restart the function app

## Monitoring

### View Logs

**Azure Portal:**
1. Go to Function App → Functions → regulatory_comments_daily
2. Click "Monitor" tab
3. View execution history, logs, and metrics

**VS Code:**
1. Install "Azure Functions" extension
2. Connect to your subscription
3. Right-click function → "Start Streaming Logs"

**Azure CLI:**
```powershell
az webapp log tail --name func-regulatory-comments --resource-group rg-regulatory-comments
```

### Application Insights (Recommended)

Enable Application Insights for advanced monitoring:

1. Go to Function App → Application Insights
2. Click "Turn on Application Insights"
3. Create or select an Application Insights resource
4. View detailed telemetry, performance, and failures

## Output Storage

All outputs are saved to Azure Blob Storage in the `regulatory-comments` container:

```
regulatory-comments/
├── 1_fetch/
│   ├── comments_raw_20260120_080000.json          # Raw API response
│   └── comments_extracted_20260120_080000.json    # Simplified comments
├── 2_consolidate/
│   └── comments_consolidated_20260120_080000.csv  # CSV with attachment text
└── 3_analysis/
    ├── categorizations_20260120_080000.json       # Individual categorizations
    ├── grouped_analysis_20260120_080000.json      # Final analysis (JSON - technical)
    └── grouped_analysis_20260120_080000.csv       # Final analysis (CSV - for end users)
```

### Accessing Output Files

**Azure Portal:**
1. Go to Storage Account → Containers → regulatory-comments
2. Browse and download files

**Azure Storage Explorer:**
1. Download: https://azure.microsoft.com/en-us/features/storage-explorer/
2. Connect to your subscription
3. Navigate to storage account → Blob Containers → regulatory-comments

**Azure CLI:**
```powershell
# List all blobs
az storage blob list --container-name regulatory-comments --account-name storegulatorycomments --output table

# Download a specific file
az storage blob download --container-name regulatory-comments --name "3_analysis/grouped_analysis_20260120_080000.json" --file "output.json" --account-name storegulatorycomments
```

## Workflow Details

### Phase 1: Fetch Comments
- Connects to Regulations.gov API
- Fetches all comments for specified document ID
- Handles pagination automatically
- Includes attachment metadata
- Saves raw JSON and extracted comments

### Phase 2: Consolidate with Attachments
- Downloads PDF and DOCX attachments
- Extracts text using PyPDF2 and python-docx
- Combines inline comment text with attachment text
- Creates CSV with all comment data
- Handles rate limiting and retries

### Phase 3: AI Categorization
- Uses Azure AI Agent (categorization_agent_id)
- Processes each comment individually
- Streams responses for real-time monitoring
- Saves categorizations as JSON
- Includes submission numbers and metadata

### Phase 4: Group Analysis
- Uses Azure AI Agent (grouping_agent_id)
- Processes categorizations in batches
- Maintains thread context across batches
- Generates collective analysis
- Identifies themes, patterns, and sentiment

## Troubleshooting

### Function Not Triggering

**Check schedule:**
```powershell
# Verify CRON expression in function_app.py
# 0 0 8 * * * = 8AM UTC = 3AM EST
```

**Check function app is running:**
```powershell
az functionapp show --name func-regulatory-comments --resource-group rg-regulatory-comments --query "state"
```

### Missing Environment Variables

**Symptoms:** Function fails immediately with configuration errors

**Solution:**
1. Check all environment variables are configured in Azure Portal
2. Verify connection strings are correct
3. Ensure API keys are valid

### Blob Upload Failures

**Symptoms:** Function completes but no output files

**Solution:**
1. Verify `AZURE_STORAGE_CONNECTION_STRING` is correct
2. Check storage account exists and is accessible
3. Ensure function app has permissions to write to storage
4. Check storage account firewall settings

### AI Agent Errors

**Symptoms:** Function fails during categorization or grouping

**Solution:**
1. Verify agent IDs are correct
2. Check Azure OpenAI endpoint is accessible
3. Ensure managed identity has permissions to Azure OpenAI
4. Review Application Insights for detailed error messages

### Rate Limiting

**Symptoms:** Errors from Regulations.gov API

**Solution:**
- API has built-in delays (0.3-0.5 seconds between requests)
- If still hitting limits, increase delays in code
- Consider processing fewer comments per run

## Cost Optimization

### Estimated Costs (Monthly)

- **Azure Functions (Consumption)**: ~$0.50/month
- **Azure Storage**: ~$1.00/month (depending on data volume)
- **Azure OpenAI**: Varies based on usage (use Global Provisioned for predictable costs)

### Tips to Reduce Costs

1. **Use Consumption Plan**: Only pay for execution time
2. **Optimize batch size**: Larger batches = fewer API calls
3. **Enable blob lifecycle management**: Auto-delete old files after 90 days
4. **Monitor token usage**: Review Application Insights for optimization opportunities

## Security Best Practices

1. **Use Managed Identity**: Function uses DefaultAzureCredential for Azure resources (Storage, AI Agents)
   - Locally: Uses `az login` credentials
   - In Azure: Uses function's managed identity
   - Grant managed identity "Storage Blob Data Contributor" role on storage account
2. **Rotate API Keys**: Regularly rotate Regulations.gov API key
3. **Restrict Storage Access**: Use private endpoints or firewall rules
4. **Enable HTTPS Only**: Ensure function app requires HTTPS
5. **Use Key Vault**: Store secrets in Azure Key Vault (reference in app settings)

## Support and Maintenance

### Updating the Function

```powershell
# Make changes to function_app.py
# Test locally with func start
# Deploy updates
func azure functionapp publish func-regulatory-comments
```

### Monitoring Health

1. Set up Application Insights alerts for failures
2. Create Azure Monitor alerts for execution metrics
3. Review logs daily for the first week after deployment

### Scheduled Maintenance

- Review output files monthly for quality
- Monitor storage account size and clean up old files
- Update dependencies quarterly: `pip install --upgrade -r requirements.txt`

## Version History

- **v1.0** (Jan 2026) - Initial Azure Function with complete workflow automation

## License

Internal use only - Department of Education analysis project
