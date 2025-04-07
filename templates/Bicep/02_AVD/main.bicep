param time string = utcNow('yyyyMMdd-HHmmss') // Timestamp for unique resource names
param vmCount int = 2 // Number of VMs to create
param vmSize string = 'Standard_D4ds_v5' // VM size
param osImage string = 'microsoftwindowsdesktop:Windows-11:win11-24h2-avd:latest' // Multisession image without Office
param vmBaseName string = 'avdhost' // Base name for the VMs
param adminUsername string
@secure()
param adminPassword string
param subnetId string // Existing subnet ID
param location string = resourceGroup().location
param hostPoolResourceId string // Existing host pool resource ID
param AVDartifactsLocation string = 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02698.323.zip'// URL to the AVD artifacts location
// VM configuration
var vmNames = [for i in range(1, vmCount + 1): '${vmBaseName}-${padLeft(i, 2, '0')}']
var vmComputerNames = [for i in range(1, vmCount + 1): '${vmBaseName}${padLeft(i, 2, '0')}']
var aadJoin = true
var aadJoinPreview = false
var intune = false

// Call on the existing host pool
resource hostPoolGet 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' existing = {
  name: last(split(hostPoolResourceId, '/'))
  scope: resourceGroup(split(hostPoolResourceId, '/')[4])
}

// Provide a default value for agentUpdate if it is not set
var defaultAgentUpdate = {
  type: 'Scheduled'
  useSessionHostLocalTime: true
  maintenanceWindowTimeZone: 'UTC'
  maintenanceWindows: [
    {
      dayOfWeek: 'Saturday'
      hour: 2 // Set the hour for the maintenance window
      duration: '02:00'
    }
  ]
}

var agentUpdateValue = contains(hostPoolGet.properties, 'agentUpdate') && !empty(hostPoolGet.properties.agentUpdate)
  ? hostPoolGet.properties.agentUpdate
  : defaultAgentUpdate

// Host pool update
module hostPool './hostpool.bicep' = {
  scope: resourceGroup(split(hostPoolResourceId, '/')[4])
  name: 'HostPool-${time}'
  params: {
    name: hostPoolGet.name
    friendlyName: (empty(hostPoolGet.properties.friendlyName)) ? '' : hostPoolGet.properties.friendlyName
    location: hostPoolGet.location
    hostPoolType: (hostPoolGet.properties.hostPoolType == 'Personal')
      ? 'Personal'
      : (hostPoolGet.properties.hostPoolType == 'Pooled') ? 'Pooled' : null
    startVMOnConnect: hostPoolGet.properties.startVMOnConnect
    customRdpProperty: hostPoolGet.properties.customRdpProperty
    loadBalancerType: (hostPoolGet.properties.loadBalancerType == 'BreadthFirst')
      ? 'BreadthFirst'
      : (hostPoolGet.properties.loadBalancerType == 'DepthFirst')
          ? 'DepthFirst'
          : (hostPoolGet.properties.loadBalancerType == 'Persistent') ? 'Persistent' : null
    maxSessionLimit: hostPoolGet.properties.maxSessionLimit
    preferredAppGroupType: (hostPoolGet.properties.preferredAppGroupType == 'Desktop')
      ? 'Desktop'
      : (hostPoolGet.properties.preferredAppGroupType == 'RailApplications') ? 'RailApplications' : null
    personalDesktopAssignmentType: (hostPoolGet.properties.personalDesktopAssignmentType == 'Automatic')
      ? 'Automatic'
      : (hostPoolGet.properties.personalDesktopAssignmentType == 'Direct') ? 'Direct' : null
    description: hostPoolGet.properties.description
    ssoadfsAuthority: hostPoolGet.properties.ssoadfsAuthority
    ssoClientId: hostPoolGet.properties.ssoClientId
    ssoClientSecretKeyVaultPath: hostPoolGet.properties.ssoClientSecretKeyVaultPath
    validationEnvironment: hostPoolGet.properties.validationEnvironment
    ring: hostPoolGet.properties.ring
    tags: hostPoolGet.tags
    agentUpdate: agentUpdateValue
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = [
  for (name, i) in vmNames: {
    name: '${name}-nic'
    location: location
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: subnetId
            }
            privateIPAllocationMethod: 'Dynamic'
          }
        }
      ]
    }
  }
]

resource vm 'Microsoft.Compute/virtualMachines@2023-07-01' = [
  for (name, i) in vmNames: {
    name: name
    location: location
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      osProfile: {
        computerName: vmComputerNames[i]
        adminUsername: adminUsername
        adminPassword: adminPassword
      }
      storageProfile: {
        imageReference: {
          publisher: split(osImage, ':')[0]
          offer: split(osImage, ':')[1]
          sku: split(osImage, ':')[2]
          version: split(osImage, ':')[3]
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: nic[i].id
          }
        ]
      }
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
          storageUri: ''
        }
      }
    }
  }
]

// PowerShell DSC Extension to onboard the VM to the host pool
// Entra ID Join Extension (AAD Join)
// Enrollment for Intune
resource avdPowerShellDSC 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = [
  for (name, i) in vmNames: {
    name: '${name}/Microsoft.PowerShell.DSC'
    location: resourceGroup().location
    properties: {
      publisher: 'Microsoft.Powershell'
      type: 'DSC'
      typeHandlerVersion: '2.73'
      autoUpgradeMinorVersion: true
      settings: {
        modulesUrl: AVDartifactsLocation
        configurationFunction: 'Configuration.ps1\\AddSessionHost'
        properties: {
          hostPoolName: last(split(hostPoolResourceId, '/'))
          registrationInfoTokenCredential: {
            UserName: 'PLACEHOLDER_DO_NOT_USE'
            Password: 'PrivateSettingsRef:RegistrationInfoToken'
          }
          aadJoin: aadJoin
          UseAgentDownloadEndpoint: true
          aadJoinPreview: aadJoinPreview
          mdmId: (intune ? '0000000a-0000-0000-c000-000000000000' : '')
          sessionHostConfigurationLastUpdateTime: ''
        }
      }
      protectedSettings: {
        Items: {
          RegistrationInfoToken: hostPool.outputs.hostPoolRegistrationToken
        }
      }
    }
    dependsOn: [
    ]
  }
]

// AADLoginForWindows Extension
resource entraloginExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = [
  for (name, i) in vmNames: {
    name: '${name}/AADLoginForWindows'
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
        : null)
    }
    dependsOn: [
      avdPowerShellDSC
    ]
  }
]

/*

// Run Custom Script from GitHub
resource customScript 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = [
  for (name, i) in vmNames: {
    name: 'CustomScript'
    location: location
    parent: vm[i]
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: [
          'https://raw.githubusercontent.com/<GitHubRepo>/<branch>/path-to-script/script.ps1'
        ]
        commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File script.ps1'
      }
    }
  }
]
*/
