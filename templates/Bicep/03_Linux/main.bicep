param baseName string = 'vmname'

@minValue(1)
@maxValue(100)
param vmCount int = 1

@allowed([
  'RHEL'
  'Ubuntu'
])
param osType string = 'Ubuntu'

@allowed([
  'Password'
  'SSH'
])
param authType string = 'SSH'

param subnetId string
param adminUsername string = 'azureuser'

@secure()
param adminPassword string

param sshPublicKey string = ''

// Custom script URLs hosted on GitHub
param scriptUriRhel string = 'https://raw.githubusercontent.com/microsoft/LinuxBrokerForAVDAccess/refs/heads/main/custom_script_extensions/rhel-script.sh'
param scriptUriUbuntu string = 'https://raw.githubusercontent.com/microsoft/LinuxBrokerForAVDAccess/refs/heads/main/custom_script_extensions/ubuntu-script.sh'

// VM Size & OS Image
@allowed([
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_DS1_v2'
])
param vmSize string = 'Standard_B2s'

// Allow multiple OS versions for Ubuntu and RHEL
@allowed([
  '8-LVM' // RHEL versions
  '9-LVM'
  '20_04-lts-gen2' // Ubuntu versions
  '22_04-lts-gen2'
])
param osVersion string = '20_04-lts-gen2'

// Corrected OS Image with additional version options
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

// Deploy VMs with Managed Identity
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

// Create NICs for VMs
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

// Custom Script Extension for Each VM
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
        osType == 'RHEL' ? scriptUriRhel : scriptUriUbuntu
      ]
      commandToExecute: 'bash ${osType == "RHEL" ? "rhel-script.sh" : "ubuntu-script.sh"}'
    }
  }
}]
