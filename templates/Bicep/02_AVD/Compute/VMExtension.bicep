param numberOfSessionHosts int
param virtualMachineName string
param avdHostPoolName string
param intune bool = true
param artifactsLocation string = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02698.323.zip'

var aadJoin = true

module HostPoolInfo '../AVD/HostPool.bicep' = {
  name: 'HostPoolInfo'
  params: {
    avdHostPoolName: avdHostPoolName
  }
}

resource virtualMachineName_1_numberOfVMs_existingNumberofVMs_Microsoft_PowerShell_DSC 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = [
  for i in range(0, numberOfSessionHosts): {
    name: '${virtualMachineName}-${i}/Microsoft.PowerShell.DSC'
    location: resourceGroup().location
    properties: {
      publisher: 'Microsoft.Powershell'
      type: 'DSC'
      typeHandlerVersion: '2.73'
      autoUpgradeMinorVersion: true
      settings: {
        modulesUrl: artifactsLocation
        configurationFunction: 'Configuration.ps1\\AddSessionHost'
        properties: {
          hostPoolName: avdHostPoolName
          registrationInfoTokenCredential: {
            UserName: 'PLACEHOLDER_DO_NOT_USE'
            Password: 'PrivateSettingsRef:RegistrationInfoToken'
          }
          aadJoin: aadJoin
          UseAgentDownloadEndpoint: true
          aadJoinPreview: false
          mdmId: (intune ? '0000000a-0000-0000-c000-000000000000' : '')
          sessionHostConfigurationLastUpdateTime: ''
        }
      }
      protectedSettings: {
        Items: {
          RegistrationInfoToken: HostPoolInfo.outputs.hostpoolToken
        }
      }
    }
  }
]

resource virtualMachineName_1_numberOfVMs_existingNumberofVMs_AADLoginForWindows 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = [
  for i in range(0, numberOfSessionHosts): {
    name: '${virtualMachineName}-${i}/AADLoginForWindows'
    location: resourceGroup().location
    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      type: 'AADLoginForWindows'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
      settings: (intune
        ? {
            mdmId: '0000000a-0000-0000-c000-000000000000'
          }
        : json('null'))
    }
    dependsOn: [
      virtualMachineName_1_numberOfVMs_existingNumberofVMs_Microsoft_PowerShell_DSC
    ]
  }
]
