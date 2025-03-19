@description('Location for all resources, defaults to Resource Group location.')
param location string = resourceGroup().location

@description('Name of the App Service Plan for Function and Web Apps')
param appSvcPlanName string = 'AppSvcPlan'

@description('Name of the App Insights resource')
param applicationInsightsName string = 'AppInsights'

@description('Name of the Key Vault')
param keyVaultName string = 'KeyVault'

module KeyVault 'AKV/KeyVault.bicep' = {
  name: 'KeyVault'
  params: {
    location: location
    vaultName: keyVaultName
  }
}

module AppSvcPlan 'PaaS/AppSvcPlan.bicep' = {
  name: 'AppSvcPlan'
  params: {
    location: location
    applicationInsightsName: applicationInsightsName
    appSvcPlanName: appSvcPlanName
  }
}

module AppServices 'PaaS/AppServices.bicep' = {
  name: 'AppServices'
  params: {
    hostingPlanId: AppSvcPlan.outputs.hostingPlanId
    instrumentationKey: AppSvcPlan.outputs.instrumentationKey
  }
}

module KeyVaultAccess 'AKV/KeyVault-Access.bicep' = {
  name: 'KeyVaultAccess'
  params: {
    vaultName: keyVaultName
    APIwebappName: AppServices.outputs.APIwebAppName
  }
}

module Function 'PaaS/Function.bicep' = {
  name: 'Function'
  params: {
    location: location
    hostingPlanId: AppSvcPlan.outputs.hostingPlanId
    instrumentationKey: AppSvcPlan.outputs.instrumentationKey
  }
}

module GraphPermissions 'Permissions/Graph.bicep' = {
  name: 'Graph'
  params: {
    APIwebappPrinID: AppServices.outputs.APIwebAppPrinId
    PortalwebappPrinID: AppServices.outputs.PortalwebAppPrinId
  }
}
