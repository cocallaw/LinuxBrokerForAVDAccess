using './main.bicep'

param time = ? /* TODO : please fix the value assigned to this parameter `utcNow()` */
param vmCount = 2 // Number of VMs to create
param vmSize = 'Standard_D4ds_v5' // VM size
param osImage = 'MicrosoftWindowsDesktop:Windows-11:win11-23h2-avd-m365:latest' // Multisession image
param vmBaseName = 'avdhost' // Base name for the VMs
param adminUsername = ''
param adminPassword = ''
param subnetId = ''
param location = resourceGroup().location
param hostPoolResourceId = ''

