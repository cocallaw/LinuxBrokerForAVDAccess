using './main.bicep'

/*Network Config*/
param subnetName =  'sn00'
param vnetName =  'vnet-avd-lab-01'
param vnetResourceGroup =  'rg-avd-linux-01'

/*VM Config - General*/
param vmNamePrefix = 'linux-vm'
param numberOfVMs = 2
param OSVersion = '24_04-lts'

/*VM Config - Auth*/
param authType = 'Password'
param adminUsername = 'cocallaw'
param adminPassword = 'JustASecret!'
