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
    [bool]$DeployAVD = $false,
    
    [Parameter(Mandatory=$false)]
    [bool]$DeployLinuxVMs = $false,
    
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

Write-TimestampedHost "🚀 Starting Linux Broker for AVD Access deployment..." -ForegroundColor Green

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
    $deploymentResult = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "./bicep/main.bicep" `
        --parameters projectName=$ProjectName environment=$Environment sqlAdminPassword=$SqlAdminPassword deployAVD=$($DeployAVD.ToString().ToLower()) deployLinuxVMs=$($DeployLinuxVMs.ToString().ToLower()) `
        --name $DeploymentName `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed!"
        exit 1
    }

    # Clean up temp file
    Remove-Item "./temp-params.json" -Force -ErrorAction SilentlyContinue

    # Get deployment outputs
    Write-TimestampedHost "Parsing deployment outputs..." -ForegroundColor Cyan
    $infrastructureOutputs = $deploymentResult.properties.outputs.infrastructureOutputs.value
    $apiAppName = $infrastructureOutputs.apiAppName.value
    $frontendAppName = $infrastructureOutputs.frontendAppName.value
    $functionAppName = $infrastructureOutputs.functionAppName.value
    $sqlServerName = $deploymentResult.properties.outputs.sqlServerName.value
    $databaseName = $infrastructureOutputs.databaseName.value
    
    Write-TimestampedHost "Deployment outputs parsed:" -ForegroundColor White
    Write-TimestampedHost "  API App: $apiAppName" -ForegroundColor White
    Write-TimestampedHost "  Frontend App: $frontendAppName" -ForegroundColor White
    Write-TimestampedHost "  Function App: $functionAppName" -ForegroundColor White

    Write-TimestampedHost "✅ Infrastructure deployed successfully!" -ForegroundColor Green
    
    # Deploy database schema
    Write-TimestampedHost "Setting up database schema..." -ForegroundColor Yellow
    
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
    az webapp deployment source config-zip --resource-group $ResourceGroupName --name $apiAppName --src "./api.zip"
    Remove-Item "./api.zip" -Force -ErrorAction SilentlyContinue

    # Deploy Frontend
    Write-TimestampedHost "Deploying Frontend application..." -ForegroundColor Cyan
    Set-Location "./front_end"
    Compress-Archive -Path "*" -DestinationPath "../frontend.zip" -Force
    Set-Location ".."
    az webapp deployment source config-zip --resource-group $ResourceGroupName --name $frontendAppName --src "./frontend.zip"
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
            az functionapp deployment source config-zip --resource-group $ResourceGroupName --name $functionAppName --src $tempZip
            
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
    Write-TimestampedHost ""
    Write-TimestampedHost "📋 Deployment Summary:" -ForegroundColor Cyan
    Write-TimestampedHost "API URL: https://$($apiAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "Frontend URL: https://$($frontendAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "Function App: https://$($functionAppName).azurewebsites.net" -ForegroundColor White
    Write-TimestampedHost "SQL Server: $($sqlServerName).database.windows.net" -ForegroundColor White
    Write-TimestampedHost "Database: $databaseName" -ForegroundColor White
    Write-TimestampedHost ""
    Write-TimestampedHost "🔧 Next Steps:" -ForegroundColor Yellow
    Write-TimestampedHost "1. Configure App Registrations in Azure AD" -ForegroundColor White
    Write-TimestampedHost "2. Update environment variables with client IDs" -ForegroundColor White
    Write-TimestampedHost "3. Create security groups and assign managed identities" -ForegroundColor White
    Write-TimestampedHost "4. Test the deployment" -ForegroundColor White

} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    Remove-Item "./temp-params.json" -Force -ErrorAction SilentlyContinue
    exit 1
}