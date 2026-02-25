# Option: AI Gateway (Internal APIM) with Foundry

This deployment creates a Foundry environment with an **internal Azure API Management (APIM)** instance acting as an AI Gateway. The goal is to allow **Foundry Agent Service** to use models from APIM, which proxies requests to an Azure OpenAI resource.

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────────────────────┐
│                                    This Deployment                                        │
│                                                                                           │
│  ┌──────────────────────────────────────────────────────────────┐                     │
│  │                      AI Foundry                                  │                     │
│  │  ┌─────────────────────────────────────────────────────────────┐ │                     │
│  │  │  Project(s) with Capability Hosts                           │ │                     │
│  │  │                                                             │ │                     │
│  │  │  Agent Service ─── Vnet injection ──────────────────────────┼─┼──┐                  │
│  │  └─────────────────────────────────────────────────────────────┘ │  │                  │
│  └──────────────────────────────────────────────────────────────────┘  │                  │
│                                                                        │                  │
│                                                                        ▼                  │
│                                              ┌─────────────────────────────────────────┐  │
│                                              │   Azure API Management (Internal)       │  │
│                                              │   - Vnet injected                       │  │
│                                              │   - AI Gateway                          │  │
│                                              │   - Static Model Definitions            │  │
│                                              │   - Load Balancing (future)             │  │
│                                              │   - Rate Limiting / Policies            │  │
│                                              └──────────────────┬──────────────────────┘  │
│                                                                 │                         │
│  ┌──────────────────────────────────────────────────────────────┼───────────────────────┐ │
│  │                    Supporting Services                       │                       │ │
│  │  VNet │ Key Vault │ Log Analytics │ App Insights │ Private DNS │ Private Endpoints   │ │
│  └──────────────────────────────────────────────────────────────┼───────────────────────┘ │
└─────────────────────────────────────────────────────────────────┼─────────────────────────┘
                                                                  │
                                           (Private Endpoint)     │
                                                                  ▼
                                ┌──────────────────────────────────────────────┐
                                │    Azure OpenAI (Landing Zone or Inline)     │
                                │                                              │
                                │    Models:                                   │
                                │    - gpt-4.1-mini                            │
                                │    - gpt-4o                                  │
                                │    - o3-mini                                 │
                                └──────────────────────────────────────────────┘
```

**Flow:**
1. Foundry Agent Service calls the internal APIM AI Gateway
2. APIM proxies requests via private endpoint to Azure OpenAI
3. All traffic stays within private network (no public internet)

## Deployed Resources

### Networking
- **Virtual Network** with subnets for:
  - Private Endpoints
  - APIM (internal mode)
  - Agent services
- **Private DNS Zones** for:
  - Azure OpenAI (`privatelink.openai.azure.com`)
  - Key Vault, Storage, Cosmos DB, AI Search
- **Private Endpoint** to Azure OpenAI resource

### Foundry
- **Foundry account** with managed identity
- **Foundry project(s)** with Capability Hosts (configurable count)
- **AI Dependencies**: Storage, Cosmos DB, AI Search with private endpoints

### AI Gateway (APIM)
- **Azure API Management** in internal (VNet-injected) mode
- Pre-configured static model definitions:
  - `gpt-4.1-mini`
  - `gpt-4o`
  - `gpt-5-mini`
  - `o3-mini`
- Managed identity with Cognitive Services User role on Azure OpenAI

### Monitoring
- **Log Analytics Workspace**
- **Application Insights** for APIM and Foundry telemetry

## Deployment Options

### Option A – Fully self-contained deployment (no prerequisites)

If you do **not** set `OPENAI_API_BASE` and `OPENAI_RESOURCE_ID`, the deployment
creates an Azure OpenAI resource automatically in the same resource group.

```bash
cd infra/ai-gateway-internal
azd up
```

An optional resource name can be provided:

```bash
export OPENAI_NAME="my-openai-resource"   # optional
azd up
```

### Option B – Connect to an existing "landing zone" Azure OpenAI

Use this approach when you already have a shared Azure OpenAI resource (e.g. in
a hub subscription) that you want to connect to.

```bash
export OPENAI_API_BASE="https://your-landing-zone-openai.openai.azure.com"
export OPENAI_RESOURCE_ID="/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<openai-name>"

cd infra/ai-gateway-internal
azd up
```

### Option C – Run the prerequisite deployment first (landing zone pattern)

Use `prerequisite.bicep` to provision an Azure OpenAI resource in a dedicated
(optionally separate) resource group, then deploy the main infrastructure.

**Step 1 – Provision the prerequisites:**

```bash
# Optional: customise the resource name
export OPENAI_NAME="my-openai-prereq"

cd infra/ai-gateway-internal
az deployment group create \
  --resource-group <prereq-rg> \
  --template-file prerequisite.bicep \
  --parameters prerequisite.bicepparam
```

**Step 2 – Capture the outputs:**

```bash
export OPENAI_API_BASE=$(az deployment group show \
  --resource-group <prereq-rg> --name prerequisite \
  --query properties.outputs.OPENAI_API_BASE.value -o tsv)

export OPENAI_RESOURCE_ID=$(az deployment group show \
  --resource-group <prereq-rg> --name prerequisite \
  --query properties.outputs.OPENAI_RESOURCE_ID.value -o tsv)
```

**Step 3 – Deploy the main infrastructure:**

```bash
azd up
```

## Optional Parameters

| Environment Variable | Description | Default |
|---|---|---|
| `OPENAI_API_BASE` | Endpoint URL of an existing Azure OpenAI resource | *(creates new)* |
| `OPENAI_RESOURCE_ID` | Resource ID of an existing Azure OpenAI resource | *(creates new)* |
| `OPENAI_NAME` | Name for the Azure OpenAI resource (new or prerequisite) | auto-generated |
| `OPENAI_LOCATION` | Location of the OpenAI resource | deployment location |
| `FOUNDRY_NAME` | Use an existing Foundry account | *(creates new)* |
| `PROJECTS_COUNT` | Number of Foundry projects to create | 3 |

## Outputs

| Output | Description |
|--------|-------------|
| `project_connection_strings` | Connection strings for Foundry projects |
| `project_names` | Names of the deployed Foundry projects |
| `FOUNDRY_NAME` | Name of the Foundry account |
| `config_validation_result` | Validation status of the configuration |

## Key Differences from `option_ai-gateway`

| Feature | `option_ai-gateway` | `option_ai-gateway-internal` |
|---------|---------------------|------------------------------|
| APIM Mode | External (public IP) | Internal (VNet only) |
| OpenAI Access | Via public endpoint | Via private endpoint |
| Network Security | Public accessible | Fully private |

## Use Cases

- **Enterprise/Regulated environments**: All AI traffic stays within private network
- **Centralized AI Gateway**: Single point of control for AI model access
- **Landing Zone integration**: Connect to shared Azure OpenAI in a hub subscription
- **Policy enforcement**: Rate limiting, logging, and access control via APIM policies
