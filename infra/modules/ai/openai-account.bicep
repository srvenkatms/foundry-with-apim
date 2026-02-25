import { aiModelTDeploymentType } from './ai-foundry.bicep'

param location string = resourceGroup().location
param tags object = {}

@description('The name of the Azure OpenAI account to create.')
param name string

@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'

param sku object = {
  name: 'S0'
}

@description('Model deployments to create in the Azure OpenAI account.')
param deployments aiModelTDeploymentType[] = []

// --------------------------------------------------------------------------------------------------------------
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: sku
  properties: {
    publicNetworkAccess: publicNetworkAccess
    customSubDomainName: toLower(name)
  }
}

@batchSize(1)
resource modelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [
  for deployment in deployments: {
    parent: account
    name: deployment.name
    properties: deployment.properties
    sku: deployment.?sku ?? { name: 'Standard', capacity: 20 }
  }
]

// --------------------------------------------------------------------------------------------------------------
// Outputs
// --------------------------------------------------------------------------------------------------------------
@description('The endpoint URL of the Azure OpenAI account.')
output OPENAI_ENDPOINT string = account.properties.endpoint

@description('The resource ID of the Azure OpenAI account.')
output OPENAI_RESOURCE_ID string = account.id

@description('The name of the Azure OpenAI account.')
output OPENAI_NAME string = account.name

@description('The location of the Azure OpenAI account.')
output OPENAI_LOCATION string = account.location
