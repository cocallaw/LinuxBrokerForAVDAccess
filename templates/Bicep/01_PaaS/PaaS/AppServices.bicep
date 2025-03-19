@description('Location for all resources, defaults to Resource Group location.')
param location string = resourceGroup().location

@description('The instrumentation keu of the App Insights instance the Web Apps will use.')
param instrumentationKey string

@description('The ID of the hosting plan that the Web Apps will use.')
param hostingPlanId string

param PortalwebAppName01 string = uniqueString(resourceGroup().id) // TODO Generate unique String for web app name
param APIwebAppName string = uniqueString(resourceGroup().id) // TODO Generate unique String for web app name
param linuxFxVersion string = 'node|14-lts' // TODO Verify runtime stack of web app
var PortalwebSiteName = toLower('wapp-${PortalwebAppName01}')
var APIwebSiteName = toLower('wapp-${APIwebAppName}')
var zipPackageUrlPortal= ''
var zipPackageUrlAPI = ''

resource appService01 'Microsoft.Web/sites@2020-06-01' = {
  name: PortalwebSiteName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlanId
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: instrumentationKey
        }
      ]
    }
  }
}

resource zipDeployWeb 'Microsoft.Web/sites/extensions@2018-02-01' = {
  name: '${PortalwebSiteName}/zipdeploy'
  properties: {
    packageUri: zipPackageUrlPortal
  }
  dependsOn: [
    appService01
  ]
}

resource appService02 'Microsoft.Web/sites@2020-06-01' = {
  name: APIwebSiteName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlanId
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: instrumentationKey
          // TODO: Remove App Insights instrumentation key from API app
        }
      ]
    }
  }
}

resource zipDeployAPI 'Microsoft.Web/sites/extensions@2018-02-01' = {
  name: '${PortalwebSiteName}/zipdeploy'
  properties: {
    packageUri: zipPackageUrlAPI
  }
  dependsOn: [
    appService01
  ]
}

// Output the web app names for use in the Graph API permissions
output PortalwebAppName string = appService01.name
output APIwebAppName string = appService02.name
// Output the principalId of the web apps for use in Graph API permissions
output PortalwebAppPrinId string = appService01.identity.principalId
output APIwebAppPrinId string = appService02.identity.principalId
