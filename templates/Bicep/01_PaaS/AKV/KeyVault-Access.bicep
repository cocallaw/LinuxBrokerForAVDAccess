@description('The name of the key vault to be created.')
param vaultName string

param APIwebappName string

var apiRBACRoleName = 'Key Vault Secrets User'
var roleIdMapping = {
  'Key Vault Secrets User': '4633458b-17de-408a-b874-0445c86b69e6'
}

resource vault 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  name: vaultName
}

//refrence existing web app
resource APIwebapp 'Microsoft.Web/sites@2020-06-01' existing = {
  name: APIwebappName
}

resource vault_accesspolicy01 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: vault
  name: guid(roleIdMapping[apiRBACRoleName], vault.id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIdMapping[apiRBACRoleName])
    principalId: reference(APIwebapp.id, '2024-03-02', 'Full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}
