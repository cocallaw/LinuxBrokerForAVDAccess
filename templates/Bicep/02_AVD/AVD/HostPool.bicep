@description('Name of the Existing Host Pool')
param avdHostPoolName string
param baseTime string = utcNow('u')
var tokenExpirationTime = dateTimeAdd(baseTime, 'PT1H')

resource existingHostPool 'Microsoft.DesktopVirtualization/hostPools@2021-07-12' existing = {
  name: avdHostPoolName
}

// TODO: Perform update operation against the host pool to return token for registration
resource updateHostPool 'Microsoft.DesktopVirtualization/hostPools@2021-07-12' = {
  name: existingHostPool.name
  properties: {
    registrationInfo: {
      expirationTime: tokenExpirationTime
    }
  }
}

output hostpoolToken string = updateHostPool.properties.registrationInfo.token
