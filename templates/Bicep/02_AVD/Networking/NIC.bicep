param existingVirtualNetworkName string
param existingSubnetName string
param numberOfSessionHosts int
param virtualMachineName string

// Reference the existing Virtual Network
resource vnetExisting 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: existingVirtualNetworkName
}

// Reference the existing Subnet within the VNet
resource subnetExisting 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  name: existingSubnetName
  parent: vnetExisting
}

resource avdNIC 'Microsoft.Network/networkInterfaces@2022-11-01' = [
  for i in range(0, length(range(1, numberOfSessionHosts))): {
    name: '${virtualMachineName}-nic-${range(0,numberOfSessionHosts)[i]}'
    location: resourceGroup().location
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: subnetExisting.id
            }
            privateIPAllocationMethod: 'Dynamic'
          }
        }
      ]
    }
  }
]
