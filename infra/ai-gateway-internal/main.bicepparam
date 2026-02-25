using 'main.bicep'

// Parameters for the main Bicep template
// Set OPENAI_API_BASE and OPENAI_RESOURCE_ID to use an existing Azure OpenAI resource
// (e.g. a "landing zone" OpenAI in a hub subscription).
// Leave both empty to have the deployment create a new Azure OpenAI resource automatically.
param openAiApiBase = readEnvironmentVariable('OPENAI_API_BASE', '')
param openAiResourceId = readEnvironmentVariable('OPENAI_RESOURCE_ID', '')

var openAiLocationValue = readEnvironmentVariable('OPENAI_LOCATION', '')
param openAiLocation = empty(openAiLocationValue) ? null : openAiLocationValue

var existingFoundryNameValue = readEnvironmentVariable('FOUNDRY_NAME', '')
param existingFoundryName = empty(existingFoundryNameValue) ? null : existingFoundryNameValue

// Optional: name for the Azure OpenAI resource created when the OPENAI_* vars are not set.
var openAiNameValue = readEnvironmentVariable('OPENAI_NAME', '')
param openAiName = openAiNameValue
