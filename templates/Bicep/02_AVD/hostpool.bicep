param name string
param friendlyName string
param location string = resourceGroup().location
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
param registrationTokenOperation string = 'Update'
param baseTime string = utcNow()
param tokenValidityLength string = '90'
param vmTemplate string = ''
param agentUpdate string = 'Auto'
param ring int = -1
param ssoadfsAuthority string = ''
param ssoClientId string = ''
param ssoClientSecretKeyVaultPath string = ''
param ssoSecretType string = 'KeyVaultSecret'
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
      token: null
      registrationTokenOperation: registrationTokenOperation
    }
    vmTemplate: ((!empty(vmTemplate)) ? null : string(vmTemplate))
    agentUpdate: agentUpdate
    ring: ring != -1 ? ring : null
    ssoadfsAuthority: ssoadfsAuthority
    ssoClientId: ssoClientId
    ssoClientSecretKeyVaultPath: ssoClientSecretKeyVaultPath
    ssoSecretType: ssoSecretType
  }
}

output hostPoolRegistrationToken string = hostPool.properties.registrationInfo.token
