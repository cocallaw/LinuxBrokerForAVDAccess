using 'main.bicep'

/*AVD Config*/
param hostPoolName = 'hp-test-01'
param sessionHostCount =  2
param maxSessionLimit =  5

/*VM Config*/
param vmNamePrefix =  'hptest'
param adminUsername =  'avdadmin'
param adminPassword =  'NotaPassword!'

/*Network Config*/
param subnetName =  'sn00'
param vnetName =  'vnet-avd-01'
param vnetResourceGroup =  'rg-avd-bicep-01'
