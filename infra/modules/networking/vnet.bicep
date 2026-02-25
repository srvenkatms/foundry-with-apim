/*
Virtual Network Module
This module deploys the core network infrastructure with security controls:

1. Address Space:
   - VNet CIDR: 172.16.0.0/16 OR 192.168.0.0/16
   - Agents Subnet: 172.16.0.0/24 OR 192.168.0.0/24
   - Private Endpoint Subnet: 172.16.101.0/24 OR 192.168.1.0/24

2. Security Features:
   - Network isolation
   - Subnet delegation
   - Private endpoint subnet
*/

@description('Azure region for the deployment')
param location string

param tags object = {}

@description('The name of the virtual network')
param vnetName string = 'agents-vnet-test'

@description('The name of Agents Subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of Private Endpoint subnet')
param peSubnetName string = 'pe-subnet'

@description('The name of App Gateway subnet')
param appGwSubnetName string = 'appgw-subnet'

@description('The name of API Management subnet')
param apimSubnetName string = 'apim-subnet'

@description('The name of API Management v2 subnet')
param apimv2SubnetName string = 'apim-v2-subnet'

@description('The name of API Management v2 Premium subnet')
param apimv2PremiumSubnetName string = 'apim-v2-premium-subnet'

@description('Address space for the VNet')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet')
param agentSubnetPrefix string = ''
param extraAgentSubnets int = 0 // Number of additional agent subnets to create

param customDNS string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''
@description('Address prefix for the application gateway subnet')
param appGwSubnetPrefix string = ''
@description('Address prefix for the APIM subnet')
param apimSubnetPrefix string = ''
@description('Address prefix for the APIM subnet')
param apimv2SubnetPrefix string = ''
@description('Address prefix for the APIM v2 Premium subnet')
param apimv2PremiumSubnetPrefix string = ''

@description('Address prefix for the Azure Bastion subnet')
param bastionSubnetPrefix string = ''

@description('Address prefix for the Jump Box subnet')
param jumpBoxSubnetPrefix string = ''

var is_vnet_address_prefix_valid = int(split(vnetAddress, '/')[1]) <= 21
  ? true
  : fail('VNet address prefix must be /21 or larger (e.g., /16, /20)')

var defaultVnetAddressPrefix = '192.168.0.0/20'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
var agentSubnet = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 0) : agentSubnetPrefix
var peSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 1) : peSubnetPrefix
var appGwSubnet = empty(appGwSubnetPrefix) ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 3) : appGwSubnetPrefix
var apimSubnet = empty(apimSubnetPrefix) ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 4) : apimSubnetPrefix
var apimv2Subnet = empty(apimv2SubnetPrefix) ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 5) : apimv2SubnetPrefix
var apimv2PremiumSubnet = empty(apimv2PremiumSubnetPrefix)
  ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 6)
  : apimv2PremiumSubnetPrefix

var laSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 24, 2) : peSubnetPrefix
var laSubnetName = 'logic-apps-subnet'

var acaSubnet = cidrSubnet(vnetAddress, 24, extraAgentSubnets + 7)
var acaSubnetName = 'aca-subnet'

var bastionSubnet = empty(bastionSubnetPrefix) ? cidrSubnet(vnetAddress, 26, extraAgentSubnets + 8) : bastionSubnetPrefix
var bastionSubnetName = 'AzureBastionSubnet' // Must be this exact name

var jumpBoxSubnet = empty(jumpBoxSubnetPrefix) ? cidrSubnet(vnetAddress, 24, extraAgentSubnets + 9) : jumpBoxSubnetPrefix
var jumpBoxSubnetName = 'jumpbox-subnet'

var extraAgentSubnetNames = [for i in range(0, extraAgentSubnets): '${agentSubnetName}-${i + 1}']
var extraAgentSubnetObjects = [
  for i in range(0, extraAgentSubnets): {
    name: extraAgentSubnetNames[i]
    addressPrefix: cidrSubnet(vnetAddress, 24, i + 3) // Start from 3 to avoid conflicts with agent and PE subnets
    delegation: 'Microsoft.app/environments'
  }
]

module networkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'networkSecurityGroupDeployment'
  params: {
    name: 'agent-nsg'
    location: location
    tags: tags
  }
}

module apimv2SecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'apimv2SecurityGroupDeployment'
  params: {
    name: 'apim-v2-nsg'
    tags: tags
    location: location
    securityRules: [
      {
        name: 'AllowStorageOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
          description: 'Dependency on Azure Storage'
        }
      }
      {
        name: 'AllowKeyVaultOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureKeyVault'
          destinationPortRange: '443'
          description: 'Dependency on Azure Key Vault'
        }
      }
    ]
  }
}

module appGwSecurityGroup 'app-gw-nsg.bicep' = {
  name: 'appGwSecurityGroupDeployment'
  params: {
    tags: tags
    location: location
  }
}

module apimSecurityGroup 'apim-nsg.bicep' = {
  name: 'apimSecurityGroupDeployment'
  params: {
    tags: tags
    location: location
  }
}

module bastionNsg 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'bastionNsgDeployment'
  params: {
    name: 'bastion-nsg'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 140
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionHostCommunication'
        properties: {
          priority: 150
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['22', '3389']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['8080', '5701']
        }
      }
      {
        name: 'AllowGetSessionInformation'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '80'
        }
      }
    ]
  }
}

module jumpBoxNsg 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'jumpBoxNsgDeployment'
  params: {
    name: 'jumpbox-nsg'
    location: location
    tags: tags
    securityRules: [
      {
        name: 'DenyDirectRdpSshInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['22', '3389']
          description: 'Deny direct RDP/SSH from Internet - use Bastion'
        }
      }
    ]
  }
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: '${vnetName}-virtual-network-deployment'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [vnetAddress]
    dnsServers: empty(customDNS) ? null : [customDNS]
    subnets: union(extraAgentSubnetObjects, [
      {
        name: agentSubnetName
        addressPrefix: agentSubnet
        delegation: 'Microsoft.app/environments'
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
      }
      {
        name: peSubnetName
        addressPrefix: peSubnet
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
      }
      {
        name: appGwSubnetName
        addressPrefix: appGwSubnet
        networkSecurityGroupResourceId: appGwSecurityGroup.outputs.networkSecurityGroupResourceId
      }
      {
        name: apimSubnetName
        addressPrefix: apimSubnet
        networkSecurityGroupResourceId: apimSecurityGroup.outputs.networkSecurityGroupResourceId
      }
      {
        name: apimv2SubnetName
        addressPrefix: apimv2Subnet
        networkSecurityGroupResourceId: apimv2SecurityGroup.outputs.resourceId
        delegation: 'Microsoft.Web/serverfarms'
      }
      {
        name: apimv2PremiumSubnetName
        addressPrefix: apimv2PremiumSubnet
        networkSecurityGroupResourceId: apimv2SecurityGroup.outputs.resourceId
        delegation: 'Microsoft.Web/hostingEnvironments'
      }
      {
        name: laSubnetName
        addressPrefix: laSubnet
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
        id: networkSecurityGroup.outputs.resourceId
        delegation: 'Microsoft.Web/serverfarms'
      }
      {
        name: acaSubnetName
        addressPrefix: acaSubnet
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
        delegation: 'Microsoft.app/environments'
      }
      {
        name: bastionSubnetName
        addressPrefix: bastionSubnet
        networkSecurityGroupResourceId: bastionNsg.outputs.resourceId
      }
      {
        name: jumpBoxSubnetName
        addressPrefix: jumpBoxSubnet
        networkSecurityGroupResourceId: jumpBoxNsg.outputs.resourceId
      }
    ])
  }
}

var extraAgentSubnetsArray = filter(
  map(virtualNetwork.outputs.subnetResourceIds, (subnetId, index) => {
    name: virtualNetwork.outputs.subnetNames[index]
    resourceId: subnetId
  }),
  subnet => contains(extraAgentSubnetNames, subnet.name)
)

// Output variables
type SubnetInfoType = {
  name: string
  resourceId: string
}
type SubnetsType = {
  @description('The Agents Subnet information')
  agentSubnet: SubnetInfoType
  @description('The Private Endpoint Subnet information')
  peSubnet: SubnetInfoType
  @description('The Application Gateway Subnet information')
  appGwSubnet: SubnetInfoType
  @description('The API Management V1 SKUs Subnet information (no NSG)')
  apimSubnet: SubnetInfoType
  @description('The API Management V2 SKUs Subnet information')
  apimv2Subnet: SubnetInfoType
  @description('The API Management V2 Premium SKUs Subnet information')
  apimv2PremiumSubnet: SubnetInfoType
  @description('The Logic Apps Subnet information')
  logicAppsSubnet: SubnetInfoType
  @description('The Azure Container Apps Subnet information')
  acaSubnet: SubnetInfoType
  @description('The Azure Bastion Subnet information')
  bastionSubnet: SubnetInfoType
  @description('The Jump Box Subnet information')
  jumpBoxSubnet: SubnetInfoType
  @description('Additional Agent Subnets information')
  extraAgentSubnets: SubnetInfoType[]
}

output VIRTUAL_NETWORK_SUBNETS SubnetsType = {
  agentSubnet: {
    name: agentSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${agentSubnetName}'
  }
  peSubnet: {
    name: peSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${peSubnetName}'
  }
  appGwSubnet: {
    name: appGwSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${appGwSubnetName}'
  }
  apimSubnet: {
    name: apimSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${apimSubnetName}'
  }
  apimv2Subnet: {
    name: apimv2SubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${apimv2SubnetName}'
  }
  apimv2PremiumSubnet: {
    name: apimv2PremiumSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${apimv2PremiumSubnetName}'
  }
  logicAppsSubnet: {
    name: laSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${laSubnetName}'
  }
  acaSubnet: {
    name: acaSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${acaSubnetName}'
  }
  bastionSubnet: {
    name: bastionSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${bastionSubnetName}'
  }
  jumpBoxSubnet: {
    name: jumpBoxSubnetName
    resourceId: '${virtualNetwork.outputs.resourceId}/subnets/${jumpBoxSubnetName}'
  }
  extraAgentSubnets: extraAgentSubnetsArray
}

output VIRTUAL_NETWORK_PREFIX_VALID bool = is_vnet_address_prefix_valid
output VIRTUAL_NETWORK_NAME string = virtualNetwork.name
output VIRTUAL_NETWORK_RESOURCE_ID string = virtualNetwork.outputs.resourceId
output VIRTUAL_NETWORK_RESOURCE_GROUP string = resourceGroup().name
output VIRTUAL_NETWORK_SUBSCRIPTION_ID string = subscription().subscriptionId
