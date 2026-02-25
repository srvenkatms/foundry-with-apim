// This bicep file deploys one resource group with the following resources:
// 1. Foundry dependencies, such as VNet and
//    private endpoints for AI Search, Azure Storage and Cosmos DB
// 2. Foundry account and projects
// 3. APIM as AI Gateway to allow Foundry Agent Service to use models from APIM
// 4. Projects with capability hosts - in Foundry Standard mode
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Endpoint URL of an existing Azure OpenAI resource (e.g. the landing-zone OpenAI). Leave empty to provision a new Azure OpenAI resource automatically.')
param openAiApiBase string = ''

@description('Full resource ID of an existing Azure OpenAI resource. Leave empty to provision a new Azure OpenAI resource automatically.')
param openAiResourceId string = ''

param openAiLocation string = location
param existingFoundryName string?
param projectsCount int = 3

@description('Optional name for the Azure OpenAI resource created when openAiApiBase / openAiResourceId are not supplied. A unique name is generated if omitted.')
param openAiName string = ''

// When both OpenAI params are provided use them; when both are absent create a
// new resource inline.  Any other combination is a configuration error.
var hasExistingOpenAi = !empty(openAiApiBase) && !empty(openAiResourceId)
var createNewOpenAi = empty(openAiApiBase) && empty(openAiResourceId)
var valid_config = hasExistingOpenAi || createNewOpenAi
  ? true
  : fail('Either provide both OPENAI_API_BASE and OPENAI_RESOURCE_ID, or leave both empty to create a new Azure OpenAI resource automatically.')

var tags = {
  'created-by': 'option-ai-gateway-internal'
  'hidden-title': 'Foundry - APIM Developer SKU Internal'
  // this is same as APIM Premium SKU - just without the SLA
  // SecurityControl: 'Ignore'
}

var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var resolvedOpenAiName = empty(openAiName) ? 'openai-${resourceToken}' : openAiName

module foundry_identity '../modules/iam/identity.bicep' = {
  name: 'foundry-identity-deployment'
  params: {
    tags: tags
    location: location
    identityName: 'foundry-${resourceToken}-identity'
  }
}

// When no external OpenAI resource is provided, provision one in this resource group.
module openai_prereq '../modules/ai/openai-account.bicep' = if (createNewOpenAi) {
  name: 'openai-prereq-deployment'
  params: {
    tags: tags
    location: location
    name: resolvedOpenAiName
    deployments: [
      {
        name: 'gpt-4.1-mini'
        properties: {
          model: {
            name: 'gpt-4.1-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'gpt-4o'
        properties: {
          model: {
            name: 'gpt-4o'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'o3-mini'
        properties: {
          model: {
            name: 'o3-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
    ]
  }
}

// Resolve the OpenAI values – from the inline-created resource or from params.
var resolvedOpenAiResourceId = createNewOpenAi ? openai_prereq.outputs.OPENAI_RESOURCE_ID : openAiResourceId
var resolvedOpenAiApiBase = createNewOpenAi ? openai_prereq.outputs.OPENAI_ENDPOINT : openAiApiBase
var resolvedOpenAiLocation = createNewOpenAi ? openai_prereq.outputs.OPENAI_LOCATION : openAiLocation

// These variables are derived purely from the input params (not from module outputs)
// so they are safe to use in module scopes and for the private endpoint.
var existingOpenAiParts = split(openAiResourceId, '/')
var existingOpenAiAccountName = empty(openAiResourceId) ? '' : last(existingOpenAiParts)
var existingOpenAiSubscriptionId = empty(openAiResourceId) ? subscription().subscriptionId : existingOpenAiParts[2]
var existingOpenAiResourceGroupName = empty(openAiResourceId) ? resourceGroup().name : existingOpenAiParts[4]

// Resolved account name used in module params (can reference module output when inline)
var openAiAccountName = createNewOpenAi ? resolvedOpenAiName : existingOpenAiAccountName
var openAiSubscriptionId = existingOpenAiSubscriptionId
var openAiResourceGroupName = existingOpenAiResourceGroupName

// vnet doesn't have to be in the same RG as the AI Services
// each foundry needs it's own delegated subnet, projects inside of one Foundry share the subnet for the Agents Service
module vnet '../modules/networking/vnet.bicep' = {
  name: 'vnet'
  params: {
    tags: tags
    location: location
    vnetName: 'project-vnet-${resourceToken}'
    extraAgentSubnets: 1
  }
}

module ai_dependencies '../modules/ai/ai-dependencies-with-dns.bicep' = {
  name: 'ai-dependencies-with-dns'
  params: {
    tags: tags
    location: location
    peSubnetName: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.peSubnet.name
    vnetResourceId: vnet.outputs.VIRTUAL_NETWORK_RESOURCE_ID
    resourceToken: resourceToken
    aiServicesName: '' // create AI services PE later
    aiAccountNameResourceGroupName: ''
  }
}

// Private endpoint for external OpenAI
module openai_private_endpoint '../modules/networking/ai-pe-dns.bicep' = {
  name: 'openai-private-endpoint-and-dns-deployment'
  params: {
    tags: tags
    location: location
    aiAccountName: openAiAccountName
    aiAccountNameResourceGroup: openAiResourceGroupName
    aiAccountSubscriptionId: openAiSubscriptionId
    peSubnetId: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.peSubnet.resourceId
    resourceToken: resourceToken
    existingDnsZones: ai_dependencies.outputs.DNS_ZONES
  }
  dependsOn: [openai_prereq]
}

// --------------------------------------------------------------------------------------------------------------
// -- Log Analytics Workspace and App Insights ------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------
module logAnalytics '../modules/monitor/loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    tags: tags
    location: location
    newLogAnalyticsName: 'log-analytics'
    newApplicationInsightsName: 'app-insights'
  }
}

module keyVault '../modules/kv/key-vault.bicep' = {
  name: 'key-vault-deployment-for-foundry'
  params: {
    tags: tags
    location: location
    name: take('kv-foundry-${resourceToken}', 24)
    logAnalyticsWorkspaceId: logAnalytics.outputs.LOG_ANALYTICS_WORKSPACE_RESOURCE_ID
    doRoleAssignments: true
    secrets: []

    publicAccessEnabled: false
    privateEndpointSubnetId: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.peSubnet.resourceId
    privateEndpointName: 'pe-kv-foundry-${resourceToken}'
    privateDnsZoneResourceId: ai_dependencies.outputs.DNS_ZONES['privatelink.vaultcore.azure.net']!.resourceId
  }
}

var foundryName = existingFoundryName ?? 'ai-foundry-${resourceToken}'

module foundry '../modules/ai/ai-foundry.bicep' = if (empty(existingFoundryName)) {
  name: 'foundry-deployment-${resourceToken}'
  params: {
    tags: tags
    location: location
    managedIdentityResourceId: foundry_identity.outputs.MANAGED_IDENTITY_RESOURCE_ID
    name: foundryName
    publicNetworkAccess: 'Enabled'
    agentSubnetResourceId: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.agentSubnet.resourceId // Use the first agent subnet
    deployments: [] // no models
    keyVaultResourceId: keyVault.outputs.KEY_VAULT_RESOURCE_ID
    keyVaultConnectionEnabled: true
    existing_Foundry_Name: existingFoundryName
  }
}

// This is required due to KeyVault issue resulting in Foundry deployment timeout
// https://portal.microsofticm.com/imp/v5/incidents/details/21000000774829/summary - AKV Detach Bug
// https://msdata.visualstudio.com/Vienna/_workitems/edit/4814146/
module fake_foundry '../modules/ai/ai-foundry-fake.bicep' = if (!empty(existingFoundryName)) {
  name: 'fake-foundry-deployment-${resourceToken}'
  params: {
    tags: tags
    location: location
    managedIdentityId: foundry_identity.outputs.MANAGED_IDENTITY_RESOURCE_ID
    name: foundryName
    publicNetworkAccess: 'Enabled'
    agentSubnetResourceId: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.agentSubnet.resourceId // Use the first agent subnet
    deployments: [] // no models
    keyVaultResourceId: keyVault.outputs.KEY_VAULT_RESOURCE_ID
    keyVaultConnectionEnabled: true
    existing_Foundry_Name: existingFoundryName
  }
}

module identities '../modules/iam/identity.bicep' = [
  for i in range(1, projectsCount): {
    name: 'ai-project-${i}-identity-${resourceToken}'
    params: {
      tags: tags
      location: location
      identityName: 'ai-project-${i}-identity-${resourceToken}'
    }
  }
]

@batchSize(1)
module projects '../modules/ai/ai-project-with-caphost.bicep' = [
  for i in range(1, projectsCount): {
    name: 'ai-project-${i}-with-caphost-${resourceToken}'
    params: {
      tags: tags
      location: location
      foundryName: foundryName
      project_description: 'AI Project ${i} ${resourceToken}'
      display_name: 'AI Project ${i} ${resourceToken}'
      projectId: i
      aiDependencies: ai_dependencies.outputs.AI_DEPENDECIES
      existingAiResourceId: null
      managedIdentityResourceId: identities[i - 1].outputs.MANAGED_IDENTITY_RESOURCE_ID
      appInsightsResourceId: logAnalytics.outputs.APPLICATION_INSIGHTS_RESOURCE_ID
    }
    dependsOn: [foundry ?? fake_foundry]
  }
]

module ai_gateway '../modules/apim/ai-gateway-internal.bicep' = {
  name: 'ai-gateway-deployment-${resourceToken}'
  params: {
    tags: tags
    location: location
    resourceToken: resourceToken
    aiFoundryName: foundryName
    subnetResourceId: vnet.outputs.VIRTUAL_NETWORK_SUBNETS.apimSubnet.resourceId
    logAnalyticsWorkspaceId: logAnalytics.outputs.LOG_ANALYTICS_WORKSPACE_RESOURCE_ID
    appInsightsId: logAnalytics.outputs.APPLICATION_INSIGHTS_RESOURCE_ID
    appInsightsInstrumentationKey: logAnalytics.outputs.APPLICATION_INSIGHTS_INSTRUMENTATION_KEY
    aiFoundryProjectNames: [for i in range(1, projectsCount): projects[i - 1].outputs.FOUNDRY_PROJECT_NAME]
    staticModels: [
      {
        name: 'gpt-4.1-mini'
        properties: {
          model: {
            name: 'gpt-4.1-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'gpt-4o'
        properties: {
          model: {
            name: 'gpt-4o'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'gpt-5-mini'
        properties: {
          model: {
            name: 'gpt-5-mini'
            version: '2025-04-01-preview'
            format: 'OpenAI'
          }
        }
      }
      {
        name: 'o3-mini'
        properties: {
          model: {
            name: 'o3-mini'
            version: '2025-01-01-preview'
            format: 'OpenAI'
          }
        }
      }
    ]
    aiServicesConfig: [
      {
        name: openAiAccountName
        resourceId: resolvedOpenAiResourceId
        endpoint: resolvedOpenAiApiBase
        location: resolvedOpenAiLocation
      }
    ]
  }
  dependsOn: [foundry ?? fake_foundry]
}

// Role assignment for an inline-created OpenAI resource (same resource group – no scope override).
module apim_role_assignment_inline '../modules/iam/role-assignment-cognitiveServices.bicep' = if (createNewOpenAi) {
  name: 'apim-role-assignment-inline-deployment-${resourceToken}'
  params: {
    accountName: resolvedOpenAiName
    projectPrincipalId: ai_gateway.outputs.apimPrincipalId
    roleName: 'Cognitive Services User'
  }
}

// Role assignment for an existing / landing-zone OpenAI resource (potentially different subscription/RG).
module apim_role_assignment_existing '../modules/iam/role-assignment-cognitiveServices.bicep' = if (!createNewOpenAi) {
  name: 'apim-role-assignment-existing-deployment-${resourceToken}'
  scope: resourceGroup(existingOpenAiSubscriptionId, existingOpenAiResourceGroupName)
  params: {
    accountName: existingOpenAiAccountName
    projectPrincipalId: ai_gateway.outputs.apimPrincipalId
    roleName: 'Cognitive Services User'
  }
}

module dashboard_setup '../modules/dashboard/dashboard-setup.bicep' = {
  name: 'dashboard-setup-deployment-${resourceToken}'
  params: {
    location: location
    applicationInsightsName: logAnalytics.outputs.APPLICATION_INSIGHTS_NAME
    logAnalyticsWorkspaceName: logAnalytics.outputs.LOG_ANALYTICS_WORKSPACE_NAME
    dashboardDisplayName: 'APIM Token Usage Dashboard for ${resourceToken}'
  }
}

module models_policy '../modules/policy/models-policy.bicep' = {
  scope: subscription()
  name: 'policy-definition-deployment-${resourceToken}'
}

module models_policy_assignment '../modules/policy/models-policy-assignment.bicep' = {
  name: 'policy-assignment-deployment-${resourceToken}'
  params: {
    cognitiveServicesPolicyDefinitionId: models_policy.outputs.cognitiveServicesPolicyDefinitionId
    allowedCognitiveServicesModels: []
  }
}

output project_connection_strings string[] = [
  for i in range(1, projectsCount): projects[i - 1].outputs.FOUNDRY_PROJECT_CONNECTION_STRING
]
output project_names string[] = [for i in range(1, projectsCount): projects[i - 1].outputs.FOUNDRY_PROJECT_NAME]
output config_validation_result bool = valid_config
output FOUNDRY_NAME string = foundryName
