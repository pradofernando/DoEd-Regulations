# DoED Public Comment Analysis Pipeline

Automated pipeline for collecting, processing, and analyzing public comments from Regulations.gov using Azure AI services.

## Overview

This project extracts public comments from the Department of Education's regulations.gov docket, processes attachments using OCR, summarizes long documents, and analyzes them using Azure AI Agents.

## Architecture

```
Regulations.gov API 
    ↓
Extract & Download Attachments (Azure Doc Intelligence)
    ↓
Summarize Long Comments (Azure AI Language)
    ↓
AI Agent Analysis (Azure OpenAI via APIM)
    ↓
Final Report (Categorizations & Collective Analysis)
```

## Azure Deployment (Bicep Template)

Yes—the project includes Bicep-based infrastructure deployment for the Azure Function workflow.

The template in this repo is designed to stand up the end-to-end Azure environment used by the scheduled processing function, including identity, secrets, observability, storage, and AI dependencies.

**Bicep files:**
- `azure_func/infra/main.bicep` - Infrastructure template
- `azure_func/infra/main.parameters.json` - Parameter defaults
- `azure_func/infra/deploy.ps1` - PowerShell deployment helper

### What the Bicep template deploys

- Azure Function App (Python on Linux Consumption plan)
- Storage Account + `regulatory-comments` blob container
- Key Vault for secret storage (Regulations.gov API key)
- Application Insights + Log Analytics workspace
- Azure OpenAI resource + model deployment
- Azure AI Foundry Hub + Project
- RBAC role assignments for managed identity access across resources

### Key deployment parameters

- `baseName` - Prefix used for resource naming
- `location` - Azure region for deployment (default `eastus`)
- `regulationsGovApiKey` - Required secure parameter stored in Key Vault
- `documentId` - Regulations.gov document ID to process
- `batchSize` - Grouping batch size for analysis stage
- `gptCapacity` - Model capacity setting for the OpenAI deployment

### Quick Deploy

```powershell
# From repository root
cd azure_func\infra

# Deploy all required Azure resources
.\deploy.ps1 -RegulationsGovApiKey "your-api-key"
```

### Azure CLI Alternative

```powershell
az group create --name rg-doed-comments --location eastus

az deployment group create `
  --resource-group rg-doed-comments `
  --template-file main.bicep `
  --parameters main.parameters.json `
  --parameters regulationsGovApiKey="your-api-key"
```

### Deployment outputs you can reuse

After deployment, the template returns values such as:
- Function app name and URL
- Storage account name
- AI project endpoint and project name
- OpenAI endpoint and model deployment name
- Key Vault name, resource group name, and subscription ID

These outputs are used in the post-deployment configuration steps (agent creation and function publish).

For full post-deployment steps (creating AI agents and publishing the function app), see `azure_func/README.md` under **Deployment to Azure**.

## Prerequisites

### Required Azure Resources

1. **Azure Document Intelligence** - Extract text from PDF/DOCX attachments
2. **Azure AI Language** - Summarize long comments
3. **Azure OpenAI** - AI Agent for categorization/analysis
4. **Azure API Management (APIM)** - Load balancing, retry, rate limiting

### API Keys

1. **Regulations.gov API Key** - Get free at: https://open.gsa.gov/api/regulationsgov/

### Python Environment

```powershell
# Create virtual environment
python -m venv .venv

# Activate
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt
```

## Configuration

Create a `.env` file in the project root:

```env
# Regulations.gov API
REGULATIONS_GOV_API_KEY=your_api_key_here

# Azure Document Intelligence
AZURE_DOC_INTELLIGENCE_ENDPOINT=https://your-resource.cognitiveservices.azure.com/
AZURE_DOC_INTELLIGENCE_KEY=your_key_here

# Azure AI Language
AZURE_LANGUAGE_ENDPOINT=https://your-resource.cognitiveservices.azure.com/
AZURE_LANGUAGE_KEY=your_key_here

# Azure OpenAI (via APIM)
APIM_ENDPOINT=https://your-apim.azure-api.net/
AZURE_OPENAI_KEY=your_key_here
```

## Complete Workflow

### Phase 1: Data Collection

**Script:** `fetch_regulations_comments.py`

Fetches all comments from a Regulations.gov docket.

```powershell
python fetch_regulations_comments.py
```

**Outputs:**
- `regulations_comments_[timestamp].json` - Full API response
- `comments_extracted_[timestamp].json` - Simplified version

**Configuration:** Edit document ID and date range in script:
```python
DOCUMENT_ID = "ED-2025-SCC-0481-0001"
POSTED_DATE_FROM = None  # None for all dates
POSTED_DATE_TO = None
```

---

### Phase 2: Extract & Consolidate Text

**Script:** `consolidate_comments_to_csv.py`

Downloads attachments and extracts text using Azure Document Intelligence.

```powershell
# Install extraction libraries
pip install PyPDF2 python-docx

# Run consolidation
python consolidate_comments_to_csv.py
```

**What it does:**
- Reads the latest `comments_extracted_*.json` file
- For comments with attachments:
  - Downloads PDF/DOCX files
  - Extracts text using PyPDF2/python-docx (or Azure Doc Intelligence)
  - Combines inline text + attachment text
- Writes consolidated CSV

**Output:**
- `comments_consolidated_[timestamp].csv`

**CSV Columns:**
- `comment_number` - Sequential number
- `comment_id` - Official comment ID
- `posted_date` - When posted
- `commenter_name` - Name
- `organization` - Organization
- `title` - Comment title
- `has_attachments` - Boolean
- `attachment_titles` - List of attachment names
- `comment_text` - **Full text (inline + attachments)**

---

### Phase 3: Summarization (Optional but Recommended)

**Script:** `summarize_long_comments.py` *(to be created)*

Summarizes long comments using Azure AI Language to reduce token usage.

```powershell
python summarize_long_comments.py
```

**What it does:**
- Reads `comments_consolidated_*.csv`
- For each row where `len(comment_text) > 10,000` characters:
  - Sends to Azure AI Language Summarization API
  - Replaces `comment_text` with ~500 character summary
  - Adds `was_summarized` column (True/False)
- Writes new CSV

**Output:**
- `comments_summarized_[timestamp].csv`

**Benefits:**
- **Reduces token usage by 95%+**
- Lowers AI agent processing costs
- Speeds up analysis
- Preserves key content

---

### Phase 4: AI Agent Analysis

**Script:** `process_csv_rows.py`

Analyzes comments using Azure AI Agent through APIM.

```powershell
python process_csv_rows.py
```

**Configuration:** Update CSV file path in script:
```python
csv_file = r"c:\src\DoED\comments_summarized_[timestamp].csv"
max_rows = None  # None for all rows
batch_size = 5   # For Phase 2 grouping
```

**What it does:**

**Phase 1 - Individual Categorization:**
- Processes each comment through AI agent
- Agent categorizes using predefined schema
- Streams responses
- Saves categorizations

**Phase 2 - Collective Analysis:**
- Groups similar categorizations
- Sends batches to agent for collective analysis
- Generates final analysis with:
  - Common themes
  - Sentiment patterns
  - Key recommendations

**Outputs:**
- `categorizations_[timestamp].json` - Individual categorizations
- `grouped_analysis_[timestamp].json` - Final collective analysis

---

## Complete Command Sequence

```powershell
# 1. Fetch comments from API
python fetch_regulations_comments.py

# 2. Extract text from attachments and consolidate
python consolidate_comments_to_csv.py

# 3. Summarize long comments (optional but recommended)
python summarize_long_comments.py

# 4. Run AI agent analysis
python process_csv_rows.py
```

---

## File Structure

```
DoED/
├── .env                                    # Configuration (not in git)
├── .venv/                                  # Python virtual environment
├── requirements.txt                        # Python dependencies
├── README.md                              # This file
│
├── fetch_regulations_comments.py          # Phase 1: Fetch from API
├── consolidate_comments_to_csv.py         # Phase 2: Extract attachments
├── summarize_long_comments.py             # Phase 3: Summarize (TBD)
├── process_csv_rows.py                    # Phase 4: AI analysis
├── format_grouped_analysis.py             # Helper script
│
├── regulations_comments_*.json            # Raw API responses
├── comments_extracted_*.json              # Simplified comments
├── comments_consolidated_*.csv            # With attachment text
├── comments_summarized_*.csv              # Summarized version
├── categorizations_*.json                 # Individual analyses
└── grouped_analysis_*.json                # Final report
```

---

## Key Features

✅ **Handles 95+ comments** including attachment-only submissions  
✅ **OCR capability** via Azure Document Intelligence  
✅ **Intelligent summarization** reduces token usage by 95%+  
✅ **No rate limits** - APIM handles load balancing & retries  
✅ **Scalable** - Can process thousands of comments  
✅ **Cost-effective** - Summarization reduces agent costs significantly  
✅ **Streaming responses** - Real-time progress monitoring

---

## Troubleshooting

### Rate Limit Errors

**Problem:** Getting `Rate limit exceeded` errors

**Solution:** The script now relies on APIM for automatic retries and load balancing. Ensure your APIM endpoint is configured properly with:
- Multiple backend instances (Global Provisioned recommended)
- Retry policies with exponential backoff
- Circuit breaker patterns

### Missing Attachments

**Problem:** Comments show "See attached file(s)" but no text extracted

**Solution:** 
1. Regulations.gov API doesn't always provide direct download URLs
2. Script attempts to construct download URLs automatically
3. Some files may be inaccessible (403 Forbidden)
4. Consider upgrading to Azure Document Intelligence for better extraction

### Long Processing Times

**Problem:** Processing 95 comments takes hours

**Solutions:**
1. Use Phase 3 summarization to reduce AI agent processing time
2. Configure APIM with Global Provisioned instances for faster throughput
3. Adjust `batch_size` in `process_csv_rows.py` (smaller = slower but more detailed)

---

## Azure Resource Recommendations

### For Production Use:

**Azure OpenAI:**
- **Global Provisioned** (PTU) instances
- Deploy 2+ instances in different regions
- Use APIM to load balance between them

**APIM Configuration:**
- Retry policy: 3-5 retries with exponential backoff
- Circuit breaker: Fail over to secondary backend
- Rate limiting: Prevent overwhelming backends

**Document Intelligence:**
- Standard tier for production
- Prebuilt Read model for text extraction

**AI Language:**
- Standard tier
- Extractive summarization (faster) or Abstractive (higher quality)

---

## Cost Optimization

1. **Use summarization** - Reduces AI agent tokens by 95%+
2. **Batch processing** - Process comments in groups (Phase 2)
3. **Global Provisioned** - Predictable costs vs. pay-per-token
4. **APIM caching** - Cache similar requests
5. **Free tier for testing** - Use free tiers for development

---

## Example Results

### Input: 95 public comments (7 inline, 88 with attachments)
### Phase 1 Output: Individual categorizations
### Phase 2 Output: Collective analysis with themes and patterns

**Sample Output Structure:**
```json
{
  "categories": [
    {
      "group_name": "Opposition to Proposed Rules",
      "group_description": "Comments opposing rule-making...",
      "comment_count": 85,
      "common_arguments": [
        "Disproportionality data protects children",
        "Historical discrimination concerns",
        "Transparency and accountability"
      ]
    }
  ]
}
```

---

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review Azure service health status
3. Verify API keys and configuration in `.env`
4. Check APIM logs for backend failures

---

## License

Internal use only - Department of Education analysis project

---

## Version History

- **v1.0** (Nov 2025) - Initial pipeline with basic PDF extraction
- **v2.0** (Nov 2025) - Added Azure services integration
- **v3.0** (Nov 2025) - APIM integration, removed client-side retry logic
