@description('The number of AVD Session Hosts to deploy')
@minValue(1)
@maxValue(10)
param numberOfSessionHosts int

@allowed([
  'Standard_D4s_v5'
  'Standard_D8s_v5'
  'Standard_D4s_v4'
  'Standard_D8s_v4'
  'Standard_F4s_v2'
  'Standard_F8s_v2'
])
param virtualMachineSize string = 'Standard_D4s_v4'

@description('The base name of the AVD Session Hosts to be created.')
param virtualMachineName string

@description('The name of the administrator account of the new AVD Session Host')
param adminUsername string

@description('Password of the AVD Session Host.')
@secure()
param adminPassword string

@description('OS Image for VMs to use')
@allowed([
  'Windows 11 Enterprise 22H2 Gen 2'
  'Windows 11 Enterprise 23H2 Gen 2'
])
param osImageName string = 'Windows 11 Enterprise 23H2 Gen 2'

@description('Enroll AVD Session Host in InTune')
param enrollIntune bool

@description('The name of the existing AVD Host Pool')
param existingAVDHostPoolName string

@description('The name of the existing Virtual Network to be used.')
param existingVirtualNetworkName string

@description('The name of the existing Subnet to be used.')
param existingSubnetName string

module NIC 'Networking/NIC.bicep' = {
  name: 'NIC'
  params: {
    existingVirtualNetworkName: existingVirtualNetworkName
    existingSubnetName: existingSubnetName
    numberOfSessionHosts: numberOfSessionHosts
    virtualMachineName: virtualMachineName
  }
}

module Compute 'Compute/VirtualMachines.bicep' = {
  name: 'Compute'
  params: {
    numberOfSessionHosts: numberOfSessionHosts
    virtualMachineName: virtualMachineName
    osImageName: osImageName
    adminUsername: adminUsername
    adminPassword: adminPassword
    virtualMachineSize: virtualMachineSize
  }
}

module VMExtension 'Compute/VMExtension.bicep' = {
  name: 'VMExtension'
  params: {
    numberOfSessionHosts: numberOfSessionHosts
    virtualMachineName: virtualMachineName
    intune: enrollIntune
    avdHostPoolName: existingAVDHostPoolName
  }
}
