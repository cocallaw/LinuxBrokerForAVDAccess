param numberOfSessionHosts int
param virtualMachineName string
param virtualMachineSize string
param osImageName string
param adminUsername string
@secure()
param adminPassword string

var imageReference = imageList[osImageName]
var imageList = {
  'Windows 11 Enterprise 22H2 Gen 2': {
    publisher: 'microsoftwindowsdesktop'
    offer: 'windows-11'
    sku: 'win11-22h2-ent'
    version: 'latest'
  }
  'Windows 11 Enterprise 23H2 Gen 2': {
    publisher: 'microsoftwindowsdesktop'
    offer: 'windows-11'
    sku: 'win11-23h2-ent'
    version: 'latest'
  }
}

resource avdSessionHost 'Microsoft.Compute/virtualMachines@2021-11-01' = [
  for i in range(0, numberOfSessionHosts): {
    name: '${virtualMachineName}-${i}'
    location: resourceGroup().location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      licenseType: 'Windows_Client'
      hardwareProfile: {
        vmSize: virtualMachineSize
      }
      storageProfile: {
        imageReference: imageReference
        osDisk: {
          name: '${virtualMachineName}-${i}-osdisk'
          caching: 'ReadWrite'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
        dataDisks: []
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: resourceId('Microsoft.Network/networkInterfaces', '${virtualMachineName}-nic-${i}')
          }
        ]
      }
      osProfile: {
        computerName: '${virtualMachineName}-${i}'
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent: true
        }
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: {
          secureBootEnabled: true
          vTpmEnabled: true
        }
      }
    }
  }
]
