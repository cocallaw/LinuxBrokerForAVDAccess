@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the App Service Plan')
param appSvcPlanName string

@description('Name of the App Insights resource')
param applicationInsightsName string

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appSvcPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

output instrumentationKey string = appInsights.properties.InstrumentationKey
output hostingPlanId string = hostingPlan.id
