using './main.bicep'

// Basic Configuration
param projectName = 'linuxbroker'
param environment = 'dev'
param location = 'East US'

// SQL Database Configuration
param sqlAdminUsername = 'sqladmin'
param sqlAdminPassword = 'YourSecurePassword123!'
param databaseName = 'LinuxBrokerDB'

// App Service Plan Configuration
param appServicePlanSku = 'P1v3'

// Tags
param tags = {
  Environment: 'Development'
  Project: 'LinuxBrokerForAVD'
  Owner: 'Platform Team'
}

// Key Vault Access (optional - set to your user object ID for initial setup)
// param keyVaultAccessPrincipalId = 'your-user-object-id-here'
