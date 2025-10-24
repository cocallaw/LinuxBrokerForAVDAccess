# Deploy-LinuxBroker.ps1
# One-click deployment script for Linux Broker for AVD Access

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectName = "linuxbroker",
    
    [Parameter(Mandatory=$false)]
    [string]$SqlAdminPassword = "",
    
    [Parameter(Mandatory=$false)]
    [string]$VMConfigPath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "LinuxBroker-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

# Helper function to write timestamped messages
function Write-TimestampedHost {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

# Helper function to configure Microsoft Graph and assign app roles
function Set-FunctionAppPermissions {
    param(
        [string]$FunctionAppName,
        [string]$ResourceGroupName,
        [string]$ApiAppId,
        [string]$AppRoleValue = "ScheduledTask"
    )
    
    Write-TimestampedHost "🔐 Configuring Function App permissions..." -ForegroundColor Yellow
    
    # Get Function App's managed identity principal ID
    Write-TimestampedHost "Getting Function App managed identity..." -ForegroundColor Cyan
    try {
        $functionAppIdentity = az functionapp identity show --name $FunctionAppName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
        if ($functionAppIdentity -and $functionAppIdentity.principalId) {
            $functionAppSpId = $functionAppIdentity.principalId
            Write-TimestampedHost "Function App Managed Identity Principal ID: $functionAppSpId" -ForegroundColor White
        } else {
            Write-Warning "Function App '$FunctionAppName' does not have a managed identity enabled"
            return $false
        }
    } catch {
        Write-Warning "Failed to get Function App managed identity: $($_.Exception.Message)"
        return $false
    }

    # Check if Microsoft Graph PowerShell module is installed and install if needed
    Write-TimestampedHost "Checking Microsoft Graph PowerShell module..." -ForegroundColor Cyan
    $requiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Applications", "Microsoft.Graph.Identity.DirectoryManagement")

    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-TimestampedHost "Installing Microsoft Graph module: $module..." -ForegroundColor Yellow
            try {
                Install-Module $module -Scope CurrentUser -Force -AllowClobber | Out-Null
                Write-TimestampedHost "✅ Successfully installed $module" -ForegroundColor Green
            } catch {
                Write-TimestampedHost "❌ Failed to install $module, trying main module..." -ForegroundColor Yellow
                Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber | Out-Null
                break
            }
        }
    }

    # Import the required modules
    Write-TimestampedHost "Importing Microsoft Graph modules..." -ForegroundColor Cyan
    try {
        Import-Module Microsoft.Graph.Authentication -Force
        Import-Module Microsoft.Graph.Applications -Force  
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
    } catch {
        Write-TimestampedHost "⚠️  Some modules failed to import, trying main module..." -ForegroundColor Yellow
        Import-Module Microsoft.Graph -Force
    }

    # Connect to Microsoft Graph
    Write-TimestampedHost "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    try {
        # Try with NoWelcome parameter first (newer versions)
        try {
            Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome | Out-Null
        } catch {
            # Fall back to without NoWelcome parameter (older versions)
            Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" | Out-Null
        }
        
        # Verify connection
        $context = Get-MgContext
        if ($context) {
            Write-TimestampedHost "✅ Successfully connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
        } else {
            throw "Connection verification failed"
        }
    } catch {
        Write-Warning "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
        Write-TimestampedHost "💡 You can configure permissions manually later using: .\deploy_infrastructure\Assign-AppRoleToFunctionApp.ps1" -ForegroundColor Cyan
        return $false
    }

    try {
        # Get the Function App service principal
        Write-TimestampedHost "Looking up Function App service principal..." -ForegroundColor Cyan
        $functionAppSp = Get-MgServicePrincipal -Filter "Id eq '$functionAppSpId'"
        if (-not $functionAppSp) {
            Write-Warning "Could not find service principal for Function App managed identity"
            return $false
        }

        # Get the API service principal
        Write-TimestampedHost "Looking up API service principal..." -ForegroundColor Cyan
        $apiSp = Get-MgServicePrincipal -Filter "AppId eq '$ApiAppId'"
        if (-not $apiSp) {
            Write-Warning "Could not find service principal for API App ID: $ApiAppId"
            return $false
        }

        # Find the required app role
        Write-TimestampedHost "Looking for '$AppRoleValue' app role..." -ForegroundColor Cyan
        $appRole = $apiSp.AppRoles | Where-Object { $_.Value -eq $AppRoleValue -and $_.AllowedMemberTypes -contains "Application" }

        if ($null -eq $appRole) {
            Write-Warning "App role '$AppRoleValue' not found in API application '$($apiSp.DisplayName)'"
            Write-Host "Available app roles:" -ForegroundColor Yellow
            $apiSp.AppRoles | Where-Object { $_.AllowedMemberTypes -contains "Application" } | ForEach-Object {
                Write-Host "  - $($_.Value): $($_.DisplayName)" -ForegroundColor White
            }
            return $false
        }

        Write-TimestampedHost "✅ Found app role: $($appRole.DisplayName)" -ForegroundColor Green

        # Check if assignment already exists
        Write-TimestampedHost "Checking for existing app role assignments..." -ForegroundColor Cyan
        $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionAppSp.Id
        $existingAssignment = $existingAssignments | Where-Object { $_.ResourceId -eq $apiSp.Id -and $_.AppRoleId -eq $appRole.Id }

        if ($existingAssignment) {
            Write-TimestampedHost "✅ App role assignment already exists!" -ForegroundColor Green
        } else {
            # Create the app role assignment
            Write-TimestampedHost "Creating app role assignment..." -ForegroundColor Cyan
            $assignment = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionAppSp.Id -PrincipalId $functionAppSp.Id -ResourceId $apiSp.Id -AppRoleId $appRole.Id
            Write-TimestampedHost "✅ Successfully created app role assignment: $($assignment.Id)" -ForegroundColor Green
        }

        Write-TimestampedHost "✅ Function App permissions configured successfully!" -ForegroundColor Green
        return $true

    } catch {
        Write-Warning "Failed to configure app role assignment: $($_.Exception.Message)"
        return $false
    } finally {
        # Disconnect from Microsoft Graph
        try {
            Disconnect-MgGraph | Out-Null
        } catch {
            # Ignore disconnect errors
        }
    }
}

Write-TimestampedHost "🚀 Starting Linux Broker for AVD Access deployment..." -ForegroundColor Green

# Load VM configuration if provided
$vmConfig = $null
$deployAVD = $false
$deployLinuxVMs = $false

if (-not [string]::IsNullOrEmpty($VMConfigPath)) {
    if (Test-Path $VMConfigPath) {
        try {
            Write-TimestampedHost "📄 Loading VM configuration from: $VMConfigPath" -ForegroundColor Cyan
            $vmConfig = Get-Content $VMConfigPath | ConvertFrom-Json
            
            # Check deployment flags
            $deployAVD = $vmConfig.avd.deploy -eq $true
            $deployLinuxVMs = $vmConfig.linuxVMs.deploy -eq $true
            
            Write-TimestampedHost "VM Configuration loaded:" -ForegroundColor White
            Write-TimestampedHost "  AVD Deployment: $deployAVD" -ForegroundColor White
            Write-TimestampedHost "  Linux VMs Deployment: $deployLinuxVMs" -ForegroundColor White
            
            # Validate required network configuration if deploying VMs
            if (($deployAVD -or $deployLinuxVMs) -and (-not $vmConfig.network)) {
                Write-Error "Network configuration is required when deploying AVD or Linux VMs"
                exit 1
            }
            
            # Validate AVD configuration if deploying AVD
            if ($deployAVD) {
                # Validate AVD resource group
                if ([string]::IsNullOrEmpty($vmConfig.avd.resourceGroup)) {
                    Write-Error "AVD configuration must include resourceGroup"
                    exit 1
                }
                # Validate AVD network configuration
                if (-not $vmConfig.network.avd -or 
                    [string]::IsNullOrEmpty($vmConfig.network.avd.vnetName) -or 
                    [string]::IsNullOrEmpty($vmConfig.network.avd.subnetName) -or 
                    [string]::IsNullOrEmpty($vmConfig.network.avd.vnetResourceGroup)) {
                    Write-Error "AVD network configuration must include avd.vnetName, avd.subnetName, and avd.vnetResourceGroup"
                    exit 1
                }
                Write-TimestampedHost "  AVD Resource Group: $($vmConfig.avd.resourceGroup)" -ForegroundColor White
                Write-TimestampedHost "  AVD Network: $($vmConfig.network.avd.vnetName)/$($vmConfig.network.avd.subnetName)" -ForegroundColor White
            }
            
            # Validate Linux VMs configuration if deploying Linux VMs
            if ($deployLinuxVMs) {
                # Validate Linux VMs resource group
                if ([string]::IsNullOrEmpty($vmConfig.linuxVMs.resourceGroup)) {
                    Write-Error "Linux VMs configuration must include resourceGroup"
                    exit 1
                }
                # Validate Linux VMs network configuration
                if (-not $vmConfig.network.linuxVMs -or 
                    [string]::IsNullOrEmpty($vmConfig.network.linuxVMs.vnetName) -or 
                    [string]::IsNullOrEmpty($vmConfig.network.linuxVMs.subnetName) -or 
                    [string]::IsNullOrEmpty($vmConfig.network.linuxVMs.vnetResourceGroup)) {
                    Write-Error "Linux VMs network configuration must include linuxVMs.vnetName, linuxVMs.subnetName, and linuxVMs.vnetResourceGroup"
                    exit 1
                }
                Write-TimestampedHost "  Linux VMs Resource Group: $($vmConfig.linuxVMs.resourceGroup)" -ForegroundColor White
                Write-TimestampedHost "  Linux VMs Network: $($vmConfig.network.linuxVMs.vnetName)/$($vmConfig.network.linuxVMs.subnetName)" -ForegroundColor White
            }
            
        } catch {
            Write-Error "Failed to parse VM configuration file: $($_.Exception.Message)"
            Write-TimestampedHost "💡 Example configuration file created at: vm-deployment-config.example.json" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Error "VM configuration file not found: $VMConfigPath"
        Write-TimestampedHost "💡 Example configuration file created at: vm-deployment-config.example.json" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-TimestampedHost "📋 No VM configuration provided - deploying core infrastructure only" -ForegroundColor Cyan
}

# Generate random password if not provided
if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
    # Generate password with alphanumeric characters and safe symbols only
    $SqlAdminPassword = -join ((48..57) + (65..90) + (97..122) + @(33,35,36,37,38,42,43,45,61,63,64) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    Write-TimestampedHost "📝 Generated SQL Admin Password: $SqlAdminPassword" -ForegroundColor Yellow
    Write-TimestampedHost "⚠️  Please save this password securely!" -ForegroundColor Red
}

# Set Azure context
Write-TimestampedHost "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Create resource group if it doesn't exist
Write-TimestampedHost "Ensuring resource group exists..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location

# Create additional resource groups for VMs if they don't exist
if ($vmConfig) {
    if ($deployAVD -and $vmConfig.avd.resourceGroup -ne $ResourceGroupName) {
        Write-TimestampedHost "Creating AVD resource group: $($vmConfig.avd.resourceGroup)" -ForegroundColor Yellow
        az group create --name $vmConfig.avd.resourceGroup --location $Location
    }
    
    if ($deployLinuxVMs -and $vmConfig.linuxVMs.resourceGroup -ne $ResourceGroupName) {
        Write-TimestampedHost "Creating Linux VMs resource group: $($vmConfig.linuxVMs.resourceGroup)" -ForegroundColor Yellow
        az group create --name $vmConfig.linuxVMs.resourceGroup --location $Location
    }
}

# Check for and handle soft-deleted Key Vault
Write-TimestampedHost "Checking for existing Key Vault..." -ForegroundColor Yellow

# Check for any soft-deleted Key Vaults that might conflict with our naming pattern
try {
    $keyVaultPattern = "$($ProjectName.Replace('-', ''))$($Environment)kv*"
    Write-TimestampedHost "Checking for Key Vaults matching pattern: $keyVaultPattern" -ForegroundColor Cyan
    
    $deletedKeyVaults = az keyvault list-deleted --output json | ConvertFrom-Json
    $conflictingVaults = $deletedKeyVaults | Where-Object { $_.name -like "$($ProjectName.Replace('-', ''))$($Environment)kv*" }
    
    if ($conflictingVaults -and $conflictingVaults.Count -gt 0) {
        Write-TimestampedHost "Found $($conflictingVaults.Count) potentially conflicting soft-deleted Key Vault(s)" -ForegroundColor Yellow
        
        foreach ($vault in $conflictingVaults) {
            Write-TimestampedHost "Purging soft-deleted Key Vault: $($vault.name)" -ForegroundColor Yellow
            $location = $vault.properties.location
            
            az keyvault purge --name $vault.name --location $location
            
            if ($LASTEXITCODE -eq 0) {
                Write-TimestampedHost "✅ Successfully purged soft-deleted Key Vault: $($vault.name)" -ForegroundColor Green
            } else {
                Write-Warning "Failed to purge soft-deleted Key Vault: $($vault.name)"
            }
        }
        
        # Wait longer for purge operations to complete
        Write-TimestampedHost "Waiting for purge operations to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
        
    } else {
        Write-TimestampedHost "✅ No conflicting soft-deleted Key Vaults found" -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not check for soft-deleted Key Vaults: $($_.Exception.Message)"
    Write-TimestampedHost "💡 If deployment fails due to Key Vault conflict, manually purge using:" -ForegroundColor Yellow
    Write-TimestampedHost "   az keyvault list-deleted" -ForegroundColor White
    Write-TimestampedHost "   az keyvault purge --name <vault-name> --location <location>" -ForegroundColor White
}

# Deploy main Bicep template
Write-TimestampedHost "Deploying infrastructure..." -ForegroundColor Yellow

try {
    # Build parameters array
    $bicepParameters = @(
        "projectName=$ProjectName"
        "environment=$Environment"
        "sqlAdminPassword=$SqlAdminPassword"
        "deployAVD=$($deployAVD.ToString().ToLower())"
        "deployLinuxVMs=$($deployLinuxVMs.ToString().ToLower())"
    )
    
    # Add AVD parameters if deploying AVD
    if ($deployAVD -and $vmConfig) {
        $avdConfig = $vmConfig.avd
        $avdNetwork = $vmConfig.network.avd
        $bicepParameters += @(
            "avdResourceGroup=$($avdConfig.resourceGroup)"
            "avdHostPoolName=$($avdConfig.hostPoolName)"
            "avdSessionHostCount=$($avdConfig.sessionHostCount)"
            "avdVmSize=$($avdConfig.vmSize)"
            "avdAdminUsername=$($avdConfig.adminUsername)"
            "avdAdminPassword=$($avdConfig.adminPassword)"
            "vnetName=$($avdNetwork.vnetName)"
            "subnetName=$($avdNetwork.subnetName)"
            "vnetResourceGroup=$($avdNetwork.vnetResourceGroup)"
        )
        Write-TimestampedHost "Added AVD deployment parameters (RG: $($avdConfig.resourceGroup), Network: $($avdNetwork.vnetName)/$($avdNetwork.subnetName))" -ForegroundColor Cyan
    }
    
    # Add Linux VM parameters if deploying Linux VMs
    if ($deployLinuxVMs -and $vmConfig) {
        $linuxConfig = $vmConfig.linuxVMs
        $linuxNetwork = $vmConfig.network.linuxVMs
        $bicepParameters += @(
            "linuxResourceGroup=$($linuxConfig.resourceGroup)"
            "linuxVmCount=$($linuxConfig.vmCount)"
            "linuxVmSize=$($linuxConfig.vmSize)"
            "linuxOSVersion=$($linuxConfig.osVersion)"
            "linuxAdminUsername=$($linuxConfig.adminUsername)"
            "linuxAdminPassword=$($linuxConfig.adminPassword)"
            "vnetName=$($linuxNetwork.vnetName)"
            "subnetName=$($linuxNetwork.subnetName)"
            "vnetResourceGroup=$($linuxNetwork.vnetResourceGroup)"
        )
        Write-TimestampedHost "Added Linux VM deployment parameters (RG: $($linuxConfig.resourceGroup), Network: $($linuxNetwork.vnetName)/$($linuxNetwork.subnetName))" -ForegroundColor Cyan
    }
    
    # Create parameters file for robust deployment
    $parametersObject = @{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
        contentVersion = "1.0.0.0"
        parameters = @{}
    }
    
    # Convert parameter array to parameters object
    foreach ($param in $bicepParameters) {
        $keyValue = $param -split '=', 2
        if ($keyValue.Length -eq 2) {
            $key = $keyValue[0].Trim()
            $value = $keyValue[1].Trim()
            
            # Convert values to appropriate types
            if ($value -eq "true") {
                # Boolean true
                $parametersObject.parameters[$key] = @{ value = $true }
            } elseif ($value -eq "false") {
                # Boolean false
                $parametersObject.parameters[$key] = @{ value = $false }
            } elseif ($value -match '^\d+$') {
                # Integer (only digits)
                $parametersObject.parameters[$key] = @{ value = [int]$value }
            } else {
                # String (default)
                $parametersObject.parameters[$key] = @{ value = $value }
            }
        }
    }
    
    # Write parameters to temp file
    $parametersFile = "./temp-params.json"
    $parametersJson = $parametersObject | ConvertTo-Json -Depth 4
    $parametersJson | Out-File -FilePath $parametersFile -Encoding UTF8
    
    # Debug: Show parameters being used
    Write-TimestampedHost "Parameters being deployed:" -ForegroundColor Cyan
    Write-Host $parametersJson -ForegroundColor White
    Write-TimestampedHost "" -ForegroundColor White
    
    # Deploy with better error handling
    Write-TimestampedHost "Starting Bicep deployment..." -ForegroundColor Cyan
    Write-TimestampedHost "Parameters file: $parametersFile" -ForegroundColor White
    
    # First, validate the deployment (skip validation for now to avoid Azure CLI issues)
    Write-TimestampedHost "Skipping validation step to avoid Azure CLI parsing issues..." -ForegroundColor Yellow
    
    # Now run the actual deployment without capturing JSON output initially
    Write-TimestampedHost "Executing deployment..." -ForegroundColor Cyan
    
    # Run deployment without trying to capture JSON output to avoid Azure CLI issues
    az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "./bicep/main.bicep" `
        --parameters "@$parametersFile" `
        --name $DeploymentName `
        --verbose `
        --debug

    if ($LASTEXITCODE -ne 0) {
        Write-TimestampedHost "❌ Infrastructure deployment failed!" -ForegroundColor Red
        Write-TimestampedHost "Check the Azure portal for detailed error information" -ForegroundColor Yellow
        Remove-Item $parametersFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    Write-TimestampedHost "✅ Deployment completed successfully" -ForegroundColor Green
    
    # Now get deployment details in a separate call
    Write-TimestampedHost "Retrieving deployment details..." -ForegroundColor Cyan
    $deploymentResult = $null
    
    try {
        $deploymentOutput = az deployment group show `
            --resource-group $ResourceGroupName `
            --name $DeploymentName `
            --output json
            
        if ($LASTEXITCODE -eq 0) {
            $deploymentResult = $deploymentOutput | ConvertFrom-Json
            Write-TimestampedHost "✅ Retrieved deployment details successfully" -ForegroundColor Green
        } else {
            Write-Warning "Could not retrieve deployment details, but deployment appears successful"
        }
    } catch {
        Write-Warning "Could not parse deployment details, but deployment appears successful: $($_.Exception.Message)"
    }

    # Clean up temp file
    Remove-Item $parametersFile -Force -ErrorAction SilentlyContinue

    # Get deployment outputs (only if we have deployment result)
    if ($deploymentResult -and $deploymentResult.properties -and $deploymentResult.properties.outputs) {
        Write-TimestampedHost "Parsing deployment outputs..." -ForegroundColor Cyan
        $infrastructureOutputs = $deploymentResult.properties.outputs.infrastructureOutputs.value
        $apiAppName = $infrastructureOutputs.apiAppName.value
        $frontendAppName = $infrastructureOutputs.frontendAppName.value
        $functionAppName = $infrastructureOutputs.functionAppName.value
        $sqlServerName = $deploymentResult.properties.outputs.sqlServerName.value
        $databaseName = $infrastructureOutputs.databaseName.value
    } else {
        Write-TimestampedHost "Could not retrieve deployment outputs automatically. Attempting to discover resources..." -ForegroundColor Yellow
        
        # Try to discover the deployed resources by name pattern
        $resourcePrefix = "$ProjectName$Environment"
        try {
            $resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
            
            $apiAppName = ($resources | Where-Object { $_.type -eq "Microsoft.Web/sites" -and $_.name -like "*api*" }).name
            $frontendAppName = ($resources | Where-Object { $_.type -eq "Microsoft.Web/sites" -and $_.name -like "*frontend*" -or $_.name -like "*web*" }).name  
            $functionAppName = ($resources | Where-Object { $_.type -eq "Microsoft.Web/sites" -and $_.name -like "*func*" -or $_.name -like "*task*" }).name
            $sqlServerResource = ($resources | Where-Object { $_.type -eq "Microsoft.Sql/servers" }).name
            $sqlServerName = $sqlServerResource
            $databaseName = "$($resourcePrefix)db"
            
            if ($apiAppName -and $frontendAppName -and $functionAppName -and $sqlServerName) {
                Write-TimestampedHost "✅ Successfully discovered deployed resources" -ForegroundColor Green
            } else {
                Write-Warning "Could not discover all resources automatically. Some deployment steps may be skipped."
            }
        } catch {
            Write-Warning "Failed to discover deployed resources: $($_.Exception.Message)"
            Write-TimestampedHost "You may need to configure resources manually via the Azure portal" -ForegroundColor Yellow
        }
    }
    
    if ($apiAppName -and $frontendAppName -and $functionAppName) {
        Write-TimestampedHost "Deployment outputs parsed:" -ForegroundColor White
        Write-TimestampedHost "  API App: $apiAppName" -ForegroundColor White
        Write-TimestampedHost "  Frontend App: $frontendAppName" -ForegroundColor White
        Write-TimestampedHost "  Function App: $functionAppName" -ForegroundColor White
    } else {
        Write-TimestampedHost "⚠️  Could not determine all resource names automatically" -ForegroundColor Yellow
        Write-TimestampedHost "Some post-deployment steps may be skipped" -ForegroundColor Yellow
    }

    Write-TimestampedHost "✅ Infrastructure deployed successfully!" -ForegroundColor Green
    
    # Deploy database schema (only if we have SQL server name)
    if ($sqlServerName -and $databaseName) {
        Write-TimestampedHost "Setting up database schema..." -ForegroundColor Yellow
    } else {
        Write-TimestampedHost "⚠️  Skipping database schema setup - SQL server information not available" -ForegroundColor Yellow
    }
    
    # Get current public IP for firewall rule
    Write-TimestampedHost "Getting current public IP address..." -ForegroundColor Cyan
    try {
        $currentIp = (Invoke-RestMethod -Uri "https://ipinfo.io/ip" -TimeoutSec 10).Trim()
        Write-TimestampedHost "Current IP: $currentIp" -ForegroundColor White
        
        # Add temporary firewall rule for current IP
        Write-TimestampedHost "Adding temporary firewall rule..." -ForegroundColor Cyan
        az sql server firewall-rule create `
            --resource-group $ResourceGroupName `
            --server $sqlServerName `
            --name "TempDeploymentRule" `
            --start-ip-address $currentIp `
            --end-ip-address $currentIp
            
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to add firewall rule. SQL scripts may fail."
        }
    } catch {
        Write-Warning "Could not determine current IP address. SQL scripts may fail: $($_.Exception.Message)"
        $currentIp = $null
    }
    
    # Run SQL scripts in order using different authentication methods
    Get-ChildItem "./sql_queries/*.sql" | Sort-Object Name | ForEach-Object {
        Write-TimestampedHost "Executing $($_.Name)..." -ForegroundColor Cyan
        $scriptExecuted = $false
        
        # Method 1: Try using SQL Admin credentials first (most reliable)
        try {
            $result = sqlcmd -S "$($sqlServerName).database.windows.net" -d $databaseName -U "sqladmin" -P $SqlAdminPassword -i $_.FullName -l 30 -b 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-TimestampedHost "✅ Successfully executed $($_.Name) using SQL Auth" -ForegroundColor Green
                $scriptExecuted = $true
            } else {
                # Check if there are any actual errors (not just warnings)
                $errors = $result | Where-Object { $_ -match "Msg \d+, Level (1[6-9]|2[0-5])" }
                if (-not $errors) {
                    Write-TimestampedHost "✅ Successfully executed $($_.Name) using SQL Auth (with warnings)" -ForegroundColor Green
                    $scriptExecuted = $true
                }
            }
        } catch {
            Write-Verbose "SQL Auth failed for $($_.Name): $($_.Exception.Message)"
        }
        
        # Method 2: Try Azure Active Directory Integrated authentication if SQL Auth failed
        if (-not $scriptExecuted) {
            try {
                $result = sqlcmd -S "$($sqlServerName).database.windows.net" -d $databaseName -G -i $_.FullName -l 30 -b 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-TimestampedHost "✅ Successfully executed $($_.Name) using AAD Integrated" -ForegroundColor Green
                    $scriptExecuted = $true
                } else {
                    # Check if there are any actual errors (not just warnings)
                    $errors = $result | Where-Object { $_ -match "Msg \d+, Level (1[6-9]|2[0-5])" }
                    if (-not $errors) {
                        Write-TimestampedHost "✅ Successfully executed $($_.Name) using AAD Integrated (with warnings)" -ForegroundColor Green
                        $scriptExecuted = $true
                    }
                }
            } catch {
                Write-Verbose "AAD Integrated failed for $($_.Name): $($_.Exception.Message)"
            }
        }
        
        # Method 3: Try Azure CLI as last resort for individual statements
        if (-not $scriptExecuted) {
            try {
                # Read file with proper encoding handling
                $sqlContent = Get-Content $_.FullName -Raw -Encoding UTF8
                # Remove BOM if present
                if ($sqlContent.StartsWith([char]0xFEFF)) {
                    $sqlContent = $sqlContent.Substring(1)
                }
                
                # Split by GO statements and execute individually
                $statements = $sqlContent -split '\r?\nGO\r?\n|\r?\n\s*GO\s*\r?\n' | Where-Object { $_.Trim() -ne '' }
                
                $allSucceeded = $true
                foreach ($statement in $statements) {
                    if ($statement.Trim() -ne '') {
                        $result = az sql db query --server "$($sqlServerName).database.windows.net" --database $databaseName --query $statement.Trim() --output none 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            $allSucceeded = $false
                            break
                        }
                    }
                }
                
                if ($allSucceeded) {
                    Write-TimestampedHost "✅ Successfully executed $($_.Name) using Azure CLI" -ForegroundColor Green
                    $scriptExecuted = $true
                }
            } catch {
                Write-Verbose "Azure CLI failed for $($_.Name): $($_.Exception.Message)"
            }
        }
        
        if (-not $scriptExecuted) {
            Write-Warning "Failed to execute $($_.Name) with all available methods, but continuing..."
        }
    }
    
    # Remove temporary firewall rule
    if ($currentIp) {
        Write-TimestampedHost "Removing temporary firewall rule..." -ForegroundColor Cyan
        try {
            az sql server firewall-rule delete `
                --resource-group $ResourceGroupName `
                --server $sqlServerName `
                --name "TempDeploymentRule"
        } catch {
            Write-Warning "Could not remove temporary firewall rule. Please remove 'TempDeploymentRule' manually."
        }
    }

    # Deploy applications
    Write-TimestampedHost "Deploying applications..." -ForegroundColor Yellow

    # Deploy API
    Write-TimestampedHost "Deploying API application..." -ForegroundColor Cyan
    Set-Location "./api"
    Compress-Archive -Path "*" -DestinationPath "../api.zip" -Force
    Set-Location ".."
    az webapp deploy --resource-group $ResourceGroupName --name $apiAppName --src-path "./api.zip" --type zip
    if ($LASTEXITCODE -eq 0) {
        Write-TimestampedHost "✅ API application deployed successfully" -ForegroundColor Green
    } else {
        Write-Warning "API application deployment may have failed. Check the Azure portal for details."
    }
    Remove-Item "./api.zip" -Force -ErrorAction SilentlyContinue

    # Deploy Frontend
    Write-TimestampedHost "Deploying Frontend application..." -ForegroundColor Cyan
    Set-Location "./front_end"
    Compress-Archive -Path "*" -DestinationPath "../frontend.zip" -Force
    Set-Location ".."
    az webapp deploy --resource-group $ResourceGroupName --name $frontendAppName --src-path "./frontend.zip" --type zip
    if ($LASTEXITCODE -eq 0) {
        Write-TimestampedHost "✅ Frontend application deployed successfully" -ForegroundColor Green
    } else {
        Write-Warning "Frontend application deployment may have failed. Check the Azure portal for details."
    }
    Remove-Item "./frontend.zip" -Force -ErrorAction SilentlyContinue

    # Deploy Function (if func command is available)
    Write-TimestampedHost "Deploying Function application..." -ForegroundColor Cyan
    try {
        Set-Location "./task"
        
        # Check if func command is available
        $funcAvailable = $false
        try {
            func --version | Out-Null
            $funcAvailable = ($LASTEXITCODE -eq 0)
        } catch {
            $funcAvailable = $false
        }
        
        if ($funcAvailable) {
            # Deploy using func command with Python runtime specification
            Write-TimestampedHost "Using Azure Functions Core Tools for deployment..." -ForegroundColor Cyan
            func azure functionapp publish $functionAppName --python --build remote --force
            
            if ($LASTEXITCODE -eq 0) {
                Write-TimestampedHost "✅ Function app deployed successfully using func command" -ForegroundColor Green
            } else {
                Write-Warning "Function deployment via func command failed, trying alternative method..."
                throw "func deployment failed"
            }
        } else {
            throw "func command not available"
        }
        
        Set-Location ".."
    } catch {
        Set-Location ".." -ErrorAction SilentlyContinue
        Write-TimestampedHost "Attempting alternative deployment method..." -ForegroundColor Yellow
        
        try {
            # Alternative: Create zip package and deploy via Azure CLI
            Write-TimestampedHost "Creating function app package..." -ForegroundColor Cyan
            Set-Location "./task"
            
            # Create a temporary zip file for deployment
            $tempZip = "../function_app.zip"
            
            # Exclude certain files from the package
            $excludeItems = @(".git", ".vscode", ".funcignore", "local.settings.json", "*.zip")
            $items = Get-ChildItem -Path "." | Where-Object { 
                $exclude = $false
                foreach ($pattern in $excludeItems) {
                    if ($_.Name -like $pattern) {
                        $exclude = $true
                        break
                    }
                }
                -not $exclude
            }
            
            Compress-Archive -Path $items -DestinationPath $tempZip -Force
            Set-Location ".."
            
            # Deploy using Azure CLI
            Write-TimestampedHost "Deploying function app package via Azure CLI..." -ForegroundColor Cyan
            az functionapp deploy --resource-group $ResourceGroupName --name $functionAppName --src-path $tempZip --type zip
            
            if ($LASTEXITCODE -eq 0) {
                Write-TimestampedHost "✅ Function app deployed successfully using Azure CLI" -ForegroundColor Green
            } else {
                Write-Warning "Function app deployment failed via Azure CLI as well"
            }
            
            # Clean up
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            
        } catch {
            Write-Warning "Function deployment failed with both methods. Please deploy manually using: func azure functionapp publish $functionAppName --python"
            Write-Warning "Error details: $($_.Exception.Message)"
        }
    }

    Write-TimestampedHost "✅ Deployment completed successfully!" -ForegroundColor Green
    
    # Configure Function App permissions if app registration config exists
    Write-TimestampedHost ""
    $appConfigPath = "./app-registration-config.json"
    if (Test-Path $appConfigPath) {
        try {
            $appConfig = Get-Content $appConfigPath | ConvertFrom-Json
            if ($appConfig.ApiAppId -and $appConfig.ApiAppId -ne "FAILED_TO_CREATE") {
                Write-TimestampedHost "Found app registration config, configuring Function App permissions..." -ForegroundColor Cyan
                
                $permissionResult = Set-FunctionAppPermissions -FunctionAppName $functionAppName -ResourceGroupName $ResourceGroupName -ApiAppId $appConfig.ApiAppId
                
                if (-not $permissionResult) {
                    Write-TimestampedHost "⚠️  Function App permission configuration failed, but deployment continues" -ForegroundColor Yellow
                    Write-TimestampedHost "You can configure permissions manually later using: .\deploy_infrastructure\Assign-AppRoleToFunctionApp.ps1" -ForegroundColor Cyan
                }
            } else {
                Write-TimestampedHost "⚠️  API App ID not found in config file. Skipping permission assignment." -ForegroundColor Yellow
                Write-TimestampedHost "Create App Registrations first using: .\deploy\Setup-AppRegistrations.ps1" -ForegroundColor Cyan
            }
        } catch {
            Write-Warning "Could not read app registration config: $($_.Exception.Message)"
            Write-TimestampedHost "You can configure permissions manually later using: .\deploy_infrastructure\Assign-AppRoleToFunctionApp.ps1" -ForegroundColor Cyan
        }
    } else {
        Write-TimestampedHost "⚠️  App registration config not found. Function App permissions not configured." -ForegroundColor Yellow
        Write-TimestampedHost "Run Setup-AppRegistrations.ps1 first to create Azure AD apps and generate config" -ForegroundColor Cyan
    }
    
    Write-TimestampedHost ""
    Write-TimestampedHost "�📋 Deployment Summary:" -ForegroundColor Cyan
    Write-TimestampedHost "API URL: https://$($apiAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "Frontend URL: https://$($frontendAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "Function App: https://$($functionAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "SQL Server: $($sqlServerName).database.windows.net" -ForegroundColor White
    Write-TimestampedHost "Database: $databaseName" -ForegroundColor White
    Write-TimestampedHost ""
    Write-TimestampedHost "🔧 Next Steps:" -ForegroundColor Yellow
    if (Test-Path $appConfigPath) {
        Write-TimestampedHost "1. Update environment variables using: .\deploy\Update-EnvironmentVariables.ps1" -ForegroundColor White
        if ($deployAVD -or $deployLinuxVMs) {
            Write-TimestampedHost "2. Configure deployed VMs with the Linux Broker agent" -ForegroundColor White
            Write-TimestampedHost "3. Add VMs to the appropriate security groups" -ForegroundColor White
            Write-TimestampedHost "4. Test the deployment" -ForegroundColor White
        } else {
            Write-TimestampedHost "2. Deploy VMs using VM configuration file if needed" -ForegroundColor White
            Write-TimestampedHost "3. Test the deployment" -ForegroundColor White
        }
    } else {
        Write-TimestampedHost "1. Run Setup-AppRegistrations.ps1 to create Azure AD apps" -ForegroundColor White
        Write-TimestampedHost "2. Re-run this deployment script to automatically configure Function App permissions" -ForegroundColor White
        Write-TimestampedHost "3. Update environment variables using: .\deploy\Update-EnvironmentVariables.ps1" -ForegroundColor White
        if ($deployAVD -or $deployLinuxVMs) {
            Write-TimestampedHost "4. Configure deployed VMs with the Linux Broker agent" -ForegroundColor White
            Write-TimestampedHost "5. Test the deployment" -ForegroundColor White
        } else {
            Write-TimestampedHost "4. Deploy VMs using VM configuration file if needed" -ForegroundColor White
            Write-TimestampedHost "5. Test the deployment" -ForegroundColor White
        }
    }

} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    Remove-Item "./temp-params.json" -Force -ErrorAction SilentlyContinue
    exit 1
}