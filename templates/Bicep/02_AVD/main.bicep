param time string = utcNow('yyyyMMdd-HHmmss') // Timestamp for unique resource names
param vmCount int = 2 // Number of VMs to create
param vmSize string = 'Standard_D4ds_v5' // VM size
param osImage string = 'MicrosoftWindowsDesktop:Windows-11:win11-23h2-avd-m365:latest' // Multisession image
param vmBaseName string = 'avdhost' // Base name for the VMs
param adminUsername string
@secure()
param adminPassword string

// Existing resources
param subnetId string // Existing subnet ID
param location string = resourceGroup().location
param hostPoolResourceId string // Existing host pool resource ID

// VM configuration
var vmNames = [for i in range(1, vmCount + 1): '${vmBaseName}-${padLeft(i, 2, '0')}']
var vmComputerNames = [for i in range(1, vmCount + 1): '${vmBaseName}${padLeft(i, 2, '0')}']

// Call on the existing hotspool
resource hostPoolGet 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' existing = {
  name: last(split(hostPoolResourceId, '/'))
  scope: resourceGroup(split(hostPoolResourceId, '/')[4])
}

// Hostpool update
module hostPool './hostpool.bicep' = {
  scope: resourceGroup(split(hostPoolResourceId, '/')[4])
  name: 'HostPool-${time}'
  params: {
    name: hostPoolGet.name
    friendlyName: hostPoolGet.properties.friendlyName
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
    agentUpdate: hostPoolGet.properties.agentUpdate.type
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

// Entra ID Join Extension (AAD Join)
resource aadJoin 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = [
  for (name, i) in vmNames: {
    name: 'AADJoin'
    parent: vm[i]
    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      type: 'AADLoginForWindows'
      typeHandlerVersion: '1.0'
      autoUpgradeMinorVersion: true
    }
  }
]

// AVD Agent Installation - Custom Script Extension
resource avdAgentInstall 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = [
  for (name, i) in vmNames: {
    name: 'AVDAgentInstall'
    parent: vm[i]
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: [
          'https://raw.githubusercontent.com/Azure/RDS-Templates/master/AVD-windows/avdagentinstall.ps1'
        ]
        commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File avdagentinstall.ps1 -RegistrationToken "${hostPool.outputs.hostPoolRegistrationToken}"'
      }
    }
    dependsOn: [
      hostPool
    ]
  }
]

// Run Custom Script from GitHub
resource customScript 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = [
  for (name, i) in vmNames: {
    name: 'CustomScript'
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
