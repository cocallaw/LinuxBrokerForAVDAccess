extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:0.1.8-preview'

@secure()
param APIwebappPrinID string
param PortalwebappPrinID string

// Reference to the Ms Graph Service Principal in the tenant
resource msgraphSP 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: '00000003-0000-0000-c000-000000000000'
}

resource API_MI_oauth2PermissionGrant 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: APIwebappPrinID
  consentType: 'AllPrincipals'
  resourceId: msgraphSP.id
  scope: 'User.Read.All GroupMember.Read.All Application.Read.All'
}

resource Portal_MI_oauth2PermissionGrant 'Microsoft.Graph/oauth2PermissionGrants@v1.0' = {
  clientId: PortalwebappPrinID
  consentType: 'AllPrincipals'
  resourceId: msgraphSP.id
  scope: 'User.Read.All GroupMember.Read.All Application.Read.All'
}
