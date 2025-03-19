extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:0.1.8-preview'

resource appregWeb 'Microsoft.Graph/applications@v1.0' = {
  displayName: 'AVDLinuxBroker-Web'
  uniqueName: 'my-uniquename'
  appRoles: [
    {
      id: guid('my-uniquename', 'Persons.Read') // need unique guid with same value for each deployment
      isEnabled: true
      displayName: 'Person Reader'
      description: 'Person Reader can search and read persons'
      value: 'Persons.Read'
      allowedMemberTypes: [
        'Application'
      ]
    }
  ]
}

resource appregAPI 'Microsoft.Graph/applications@v1.0' = {
  displayName: 'AVDLinuxBroker-API'
  uniqueName: 'my-uniquename'
  appRoles: [
    {
      id: guid('my-uniquename', 'Persons.Read') // need unique guid with same value for each deployment
      isEnabled: true
      displayName: 'Person Reader'
      description: 'Person Reader can search and read persons'
      value: 'Persons.Read'
      allowedMemberTypes: [
        'Application'
      ]
    }
  ]
}

// Output the ID and Secret of the application for use in Key Vault access policies
output applicationId string = application.id
output applicationSecret string = application.passwordCredentials[0].secretText
