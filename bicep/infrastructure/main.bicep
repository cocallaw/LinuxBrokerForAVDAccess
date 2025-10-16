// Main infrastructure deployment for Linux Broker for AVD Access
param location string = resourceGroup().location
param projectName string = 'linuxbroker'
param environment string = 'dev'
param tags object = {}

// SQL Database Parameters
param sqlAdminUsername string = 'sqladmin'
@secure()
param sqlAdminPassword string
param databaseName string = 'LinuxBrokerDB'

// App Service Parameters
param appServicePlanSku string = 'P1v3'

// Key Vault Parameters
param keyVaultAccessPrincipalId string = ''

var resourcePrefix = '${projectName}-${environment}'
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// SQL Server and Database
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: '${resourcePrefix}-sql-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
  
  resource database 'databases@2023-08-01-preview' = {
    name: databaseName
    location: location
    tags: tags
    sku: {
      name: 'S1'
      tier: 'Standard'
    }
    properties: {
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      maxSizeBytes: 268435456000 // 250 GB
    }
  }

  resource firewallRule 'firewallRules@2023-08-01-preview' = {
    name: 'AllowAzureServices'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${resourcePrefix}-kv-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: false
    accessPolicies: keyVaultAccessPrincipalId != '' ? [
      {
        tenantId: tenant().tenantId
        objectId: keyVaultAccessPrincipalId
        permissions: {
          secrets: ['get', 'list', 'set']
        }
      }
    ] : []
  }
}

// Store SQL connection string in Key Vault
resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SqlConnectionString'
  properties: {
    value: 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database=${databaseName};Authentication=Active Directory Default;'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${resourcePrefix}-asp-${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// API App Service
resource apiApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${resourcePrefix}-api-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: true
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: '1'
        }
        {
          name: 'KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'SQL_SERVER'
          value: sqlServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'SQL_DATABASE'
          value: databaseName
        }
      ]
    }
    httpsOnly: true
  }
}

// Frontend App Service
resource frontendApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${resourcePrefix}-web-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: true
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: '1'
        }
        {
          name: 'API_BASE_URL'
          value: 'https://${apiApp.properties.defaultHostName}/api'
        }
      ]
    }
    httpsOnly: true
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${replace(resourcePrefix, '-', '')}st${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: '${resourcePrefix}-func-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('${resourcePrefix}-func-${uniqueSuffix}')
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'API_URL'
          value: 'https://${apiApp.properties.defaultHostName}'
        }
      ]
    }
    httpsOnly: true
  }
}

// Grant API App and Function App access to Key Vault
resource appKeyVaultAccess 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: apiApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
      {
        tenantId: tenant().tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

// Outputs
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = databaseName
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output apiAppName string = apiApp.name
output apiAppUrl string = 'https://${apiApp.properties.defaultHostName}'
output frontendAppName string = frontendApp.name
output frontendAppUrl string = 'https://${frontendApp.properties.defaultHostName}'
output functionAppName string = functionApp.name
output apiAppPrincipalId string = apiApp.identity.principalId
output functionAppPrincipalId string = functionApp.identity.principalId
