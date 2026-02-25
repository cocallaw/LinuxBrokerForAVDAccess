using './main.bicep'

/*Network Config*/
param subnetName =  'mySubnet'
param vnetName =  'myVnet'
param vnetResourceGroup =  'myResourceGroup'

/*VM Config - General*/
param vmNamePrefix = 'myLinuxVM'
param vmSize = 'Standard_D2s_v3'
param numberOfVMs = 2
param OSVersion = '24_04-lts'

/*VM Config - Auth*/
param authType = 'Password'
param adminUsername = 'myAdminUser'
param adminPassword = 'JustASecret!'

/*Linux Broker Config*/
param linuxBrokerApiClientId = 'your-api-app-registration-client-id'
param linuxBrokerApiUrl = 'https://your-broker.domain.com/api'

/*RHEL Config (only needed for RHEL hosts)*/
// param rhelOrgId = 'your-rhel-org-id'
// param rhelActivationKey = 'your-rhel-activation-key'
