param name string
param friendlyName string
param location string
param tags object = {}
param hostPoolType string = 'Pooled'
param publicNetworkAccess string = 'Enabled'
param customRdpProperty string = ''
param personalDesktopAssignmentType string = 'Automatic'
param preferredAppGroupType string = 'Desktop'
param maxSessionLimit int = 2
param loadBalancerType string = 'BreadthFirst'
param startVMOnConnect bool = false
param validationEnvironment bool = false
param registrationTokenOperation string = 'Update' // Ensure token is updated
param baseTime string = utcNow()
param tokenValidityLength string = 'PT3H' // ISO8601 duration for 3 hours
param vmTemplate string = ''
param agentUpdate object
param ring int = -1
param ssoadfsAuthority string = ''
param ssoClientId string = ''
@secure()
param ssoClientSecretKeyVaultPath string = ''
@secure()
param ssoSecretType string = '' // Default to an empty string if not required
param description string = ''

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: name
  location: location
  tags: tags
  properties: {
    friendlyName: friendlyName
    description: description
    hostPoolType: hostPoolType
    publicNetworkAccess: publicNetworkAccess
    customRdpProperty: customRdpProperty
    personalDesktopAssignmentType: any(personalDesktopAssignmentType)
    preferredAppGroupType: preferredAppGroupType
    maxSessionLimit: maxSessionLimit
    loadBalancerType: loadBalancerType
    startVMOnConnect: startVMOnConnect
    validationEnvironment: validationEnvironment
    registrationInfo: {
      expirationTime: dateTimeAdd(baseTime, tokenValidityLength)
      token: null // Token will be generated during deployment
      registrationTokenOperation: registrationTokenOperation
    }
    vmTemplate: ((!empty(vmTemplate)) ? null : string(vmTemplate))
    agentUpdate: agentUpdate
    ring: ring != -1 ? ring : null
    ssoadfsAuthority: ssoadfsAuthority
    ssoClientId: ssoClientId
    ssoClientSecretKeyVaultPath: ssoClientSecretKeyVaultPath
    ssoSecretType: (empty(ssoSecretType)) ? null : ssoSecretType // Set to null if empty
  }
}

// Safely output the registration token if it exists
output hostPoolRegistrationToken string = hostPool.properties.registrationInfo != null && contains(hostPool.properties.registrationInfo, 'token') && !empty(hostPool.properties.registrationInfo.token)
  ? hostPool.properties.registrationInfo.token
  : 'No token available'
