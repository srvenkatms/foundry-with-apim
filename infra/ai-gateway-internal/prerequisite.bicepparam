using 'prerequisite.bicep'

// Optional: provide a name for the Azure OpenAI resource.
// If not set, a unique name will be generated automatically.
var openAiNameValue = readEnvironmentVariable('OPENAI_NAME', '')
param openAiName = openAiNameValue
