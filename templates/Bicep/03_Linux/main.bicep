// Base VM Name
param baseName string = 'vmname'

// Number of VMs to deploy
@minValue(1)
@maxValue(100)
param vmCount int = 1

// OS Type (RHEL or Ubuntu)
@allowed([
  'RHEL'
  'Ubuntu'
])
param osType string = 'Ubuntu'

// Authentication Type (Password or SSH)
@allowed([
  'Password'
  'SSH'
])
param authType string = 'SSH'

// Existing Subnet ID
param subnetId string

// Admin username
param adminUsername string = 'azureuser'

// Admin password (only used if authType == Password)
@secure()
param adminPassword string

// SSH public key (only used if authType == SSH)
param sshPublicKey string = ''

// VM Size Options
@allowed([
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_DS1_v2'
])
param vmSize string = 'Standard_B2s'

// Allowed OS Versions (Ubuntu and RHEL)
@allowed([
  '7-LVM'   // RHEL 7
  '8-LVM'   // RHEL 8
  '20_04-lts-gen2'  // Ubuntu 20.04
  '22_04-lts-gen2'  // Ubuntu 22.04
])
param osVersion string = '20_04-lts-gen2'

// Custom script URLs hosted on GitHub
param scriptUriRhel7 string = 'https://raw.githubusercontent.com/example/repo/main/rhel7-script.sh'
param scriptUriRhel8 string = 'https://raw.githubusercontent.com/example/repo/main/rhel8-script.sh'
param scriptUriUbuntu string = 'https://raw.githubusercontent.com/example/repo/main/ubuntu-script.sh'

// Determine OS image based on user selection
var osImage = osType == 'RHEL'
  ? {
      publisher: 'RedHat'
      offer: 'RHEL'
      sku: osVersion
      version: 'latest'
    }
  : {
      publisher: 'Canonical'
      offer: 'UbuntuServer'
      sku: osVersion
      version: 'latest'
    }

// Select correct script URL based on OS and version
var scriptUri = osType == 'RHEL' ? (osVersion == '7-LVM' ? scriptUriRhel7 : scriptUriRhel8) : scriptUriUbuntu

// Determine the correct command to execute based on OS type
var commandToExecute = osType == 'RHEL' ? 'bash rhel-script.sh' : 'bash ubuntu-script.sh'

// Create VMs with managed identities
resource vms 'Microsoft.Compute/virtualMachines@2022-03-01' = [
  for i in range(0, vmCount): {
    name: '${baseName}-${format('{0:00}', i + 1)}'
    location: resourceGroup().location
    identity: {
      type: 'SystemAssigned'
    }
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      osProfile: {
        computerName: '${baseName}-${format('{0:00}', i + 1)}'
        adminUsername: adminUsername
        adminPassword: authType == 'Password' ? adminPassword : null
        linuxConfiguration: authType == 'SSH'
          ? {
              disablePasswordAuthentication: true
              ssh: {
                publicKeys: [
                  {
                    path: '/home/${adminUsername}/.ssh/authorized_keys'
                    keyData: sshPublicKey
                  }
                ]
              }
            }
          : {
              disablePasswordAuthentication: false
            }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: resourceId('Microsoft.Network/networkInterfaces', '${baseName}-nic-${format('{0:00}', i + 1)}')
          }
        ]
      }
      storageProfile: {
        imageReference: osImage
        osDisk: {
          createOption: 'FromImage'
        }
      }
    }
  }
]

// Create NICs for each VM
resource nics 'Microsoft.Network/networkInterfaces@2021-05-01' = [
  for i in range(0, vmCount): {
    name: '${baseName}-nic-${format('{0:00}', i + 1)}'
    location: resourceGroup().location
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

// Deploy Custom Script Extension to Each VM
resource vmExtensions 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = [for i in range(0, vmCount): {
  name: '${baseName}-${format('{0:00}', i + 1)}/customScript'
  location: resourceGroup().location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        scriptUri
      ]
      commandToExecute: commandToExecute
    }
  }
}]
