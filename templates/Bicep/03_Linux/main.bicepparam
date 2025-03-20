using './main.bicep'

param baseName = 'vmname'
param vmCount = 1
param osType = 'Ubuntu'
param authType = 'SSH'
param subnetId = ''
param adminUsername = 'azureuser'
param adminPassword = ''
param sshPublicKey = ''
param vmSize = 'Standard_D8s_v3'
param osVersion = '20_04-lts-gen2'
param scriptUriRhel7 = 'https://raw.githubusercontent.com/example/repo/main/rhel7-script.sh'
param scriptUriRhel8 = 'https://raw.githubusercontent.com/example/repo/main/rhel8-script.sh'
param scriptUriUbuntu = 'https://raw.githubusercontent.com/example/repo/main/ubuntu-script.sh'

