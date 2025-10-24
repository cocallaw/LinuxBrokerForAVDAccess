// Master deployment template that orchestrates all components
param location string = resourceGroup().location
param projectName string = 'linuxbroker'
param environment string = 'dev'
param tags object = {}

// SQL Configuration
param sqlAdminUsername string = 'sqladmin'
@secure()
param sqlAdminPassword string

// AVD Configuration (optional)
param deployAVD bool = false
param avdResourceGroup string = ''
param avdHostPoolName string = ''
param avdSessionHostCount int = 2
param avdVmSize string = 'Standard_DS2_v2'
param avdAdminUsername string = 'avdadmin'
@secure()
param avdAdminPassword string = ''

// Linux VMs Configuration (optional)
param deployLinuxVMs bool = false
param linuxResourceGroup string = ''
param linuxVmCount int = 2
param linuxVmSize string = 'Standard_D2s_v3'
param linuxOSVersion string = '24_04-lts'
@allowed([
  'Password'
  'SSH'
])
param linuxAuthType string = 'Password'
param linuxAdminUsername string = 'linuxadmin'
@secure()
param linuxAdminPassword string = ''
param linuxSshPublicKey string = ''

// Network Configuration (required if deploying VMs)
param vnetName string = ''
param subnetName string = ''
param vnetResourceGroup string = ''

// Deploy core infrastructure (API, Database, Frontend, Function)
module infrastructure 'infrastructure/main.bicep' = {
  name: 'infrastructure-deployment'
  params: {
    location: location
    projectName: projectName
    environment: environment
    tags: tags
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
  }
}

// Deploy AVD hosts (optional)
module avdDeployment 'AVD/main.bicep' = if (deployAVD) {
  name: 'avd-deployment'
  scope: resourceGroup(avdResourceGroup)
  params: {
    location: location
    tags: tags
    hostPoolName: avdHostPoolName
    sessionHostCount: avdSessionHostCount
    maxSessionLimit: 10
    vmNamePrefix: substring(projectName, 0, min(length(projectName), 8))
    vmSize: avdVmSize
    adminUsername: avdAdminUsername
    adminPassword: avdAdminPassword
    vnetName: vnetName
    subnetName: subnetName
    vnetResourceGroup: vnetResourceGroup
    linuxBrokerApiBaseUrl: infrastructure.outputs.apiAppUrl
  }
}

// Deploy Linux VMs (optional)
module linuxVmDeployment 'Linux/main.bicep' = if (deployLinuxVMs) {
  name: 'linux-vm-deployment'
  scope: resourceGroup(linuxResourceGroup)
  params: {
    location: location
    tags: tags
    vmNamePrefix: '${projectName}-linux'
    vmSize: linuxVmSize
    numberOfVMs: linuxVmCount
    OSVersion: linuxOSVersion
    authType: linuxAuthType
    adminUsername: linuxAdminUsername
    adminPassword: linuxAdminPassword
    sshPublicKey: linuxSshPublicKey
    vnetName: vnetName
    subnetName: subnetName
    vnetResourceGroup: vnetResourceGroup
  }
  dependsOn: [
    infrastructure
  ]
}

// Outputs
output infrastructureOutputs object = infrastructure.outputs
output apiUrl string = infrastructure.outputs.apiAppUrl
output frontendUrl string = infrastructure.outputs.frontendAppUrl
output sqlServerName string = infrastructure.outputs.sqlServerName
output keyVaultName string = infrastructure.outputs.keyVaultName
