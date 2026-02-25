// This bicep file provisions the prerequisite Azure OpenAI resource
// needed before running main.bicep for the ai-gateway-internal deployment.
//
// This represents the "landing zone" Azure OpenAI that the APIM AI Gateway
// will connect to via a private endpoint.
//
// Option A – run this prerequisite standalone, then set environment variables
// from the outputs before running main.bicep:
//
//   export OPENAI_API_BASE=<OPENAI_API_BASE output>
//   export OPENAI_RESOURCE_ID=<OPENAI_RESOURCE_ID output>
//
// Option B – leave OPENAI_API_BASE and OPENAI_RESOURCE_ID unset when running
// main.bicep.  main.bicep will detect the missing values and create an Azure
// OpenAI account automatically in the same resource group.
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Optional: name for the Azure OpenAI resource. A unique name is generated if omitted.')
param openAiName string = ''

var tags = {
  'created-by': 'option-ai-gateway-internal-prereq'
  'hidden-title': 'Foundry - AI Gateway Internal Prerequisites'
}

var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var resolvedOpenAiName = empty(openAiName) ? 'openai-${resourceToken}' : openAiName

module openai '../modules/ai/openai-account.bicep' = {
  name: 'openai-account-deployment'
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

// --------------------------------------------------------------------------------------------------------------
// Outputs – use these to populate OPENAI_API_BASE and OPENAI_RESOURCE_ID
// for the main.bicep deployment.
// --------------------------------------------------------------------------------------------------------------
@description('The endpoint URL for the Azure OpenAI resource. Set as OPENAI_API_BASE.')
output OPENAI_API_BASE string = openai.outputs.OPENAI_ENDPOINT

@description('The resource ID of the Azure OpenAI resource. Set as OPENAI_RESOURCE_ID.')
output OPENAI_RESOURCE_ID string = openai.outputs.OPENAI_RESOURCE_ID

@description('The name of the Azure OpenAI resource.')
output OPENAI_NAME string = openai.outputs.OPENAI_NAME

@description('The location of the Azure OpenAI resource.')
output OPENAI_LOCATION string = openai.outputs.OPENAI_LOCATION
