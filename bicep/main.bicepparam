using './main.bicep'

// Basic Configuration
param projectName = 'linuxbroker'
param environment = 'dev'
param location = 'East US'

// SQL Database Configuration
param sqlAdminUsername = 'sqladmin'
param sqlAdminPassword = 'YourSecurePassword123!'

// Deployment Options
param deployAVD = false
param deployLinuxVMs = false

// AVD Configuration (only used if deployAVD = true)
param avdHostPoolName = 'hp-linuxbroker-dev'
param avdSessionHostCount = 2
param avdVmSize = 'Standard_DS2_v2'
param avdAdminUsername = 'avdadmin'
param avdAdminPassword = 'YourAVDPassword123!'

// Linux VM Configuration (only used if deployLinuxVMs = true)
param linuxVmCount = 2
param linuxVmSize = 'Standard_D2s_v3'
param linuxOSVersion = '24_04-lts'  // Options: '7-LVM', '8-LVM', '9-LVM', '24_04-lts'
param linuxAdminUsername = 'linuxadmin'
param linuxAdminPassword = 'YourLinuxPassword123!'

// Network Configuration (required only if deployAVD or deployLinuxVMs = true)
param vnetName = 'your-vnet-name'
param subnetName = 'your-subnet-name'
param vnetResourceGroup = 'your-vnet-resource-group'

// Tags
param tags = {
  Environment: 'Development'
  Project: 'LinuxBrokerForAVD'
  Owner: 'Platform Team'
  CostCenter: 'IT'
}
