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

Write-Host "🚀 Starting Linux Broker for AVD Access deployment..." -ForegroundColor Green

# Generate random password if not provided
if ([string]::IsNullOrEmpty($SqlAdminPassword)) {
    $SqlAdminPassword = -join ((33..126) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
    Write-Host "📝 Generated SQL Admin Password: $SqlAdminPassword" -ForegroundColor Yellow
    Write-Host "⚠️  Please save this password securely!" -ForegroundColor Red
}

# Set Azure context
Write-Host "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Create resource group if it doesn't exist
Write-Host "Ensuring resource group exists..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location

# Deploy main Bicep template
Write-Host "Deploying infrastructure..." -ForegroundColor Yellow
$deploymentParams = @{
    projectName = $ProjectName
    environment = $Environment
    sqlAdminPassword = $SqlAdminPassword
    deployAVD = $DeployAVD
    deployLinuxVMs = $DeployLinuxVMs
}

# Convert to JSON for Azure CLI
$paramsJson = $deploymentParams | ConvertTo-Json -Compress
$paramsJson | Out-File -FilePath "./temp-params.json" -Encoding UTF8

try {
    $deploymentResult = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file "./bicep/main.bicep" `
        --parameters "@./temp-params.json" `
        --name $DeploymentName `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed!"
        exit 1
    }

    # Clean up temp file
    Remove-Item "./temp-params.json" -Force -ErrorAction SilentlyContinue

    # Get deployment outputs
    $apiAppName = $deploymentResult.properties.outputs.infrastructureOutputs.value.apiAppName
    $frontendAppName = $deploymentResult.properties.outputs.infrastructureOutputs.value.frontendAppName
    $functionAppName = $deploymentResult.properties.outputs.infrastructureOutputs.value.functionAppName
    $sqlServerName = $deploymentResult.properties.outputs.sqlServerName.value
    $databaseName = $deploymentResult.properties.outputs.infrastructureOutputs.value.databaseName

    Write-Host "✅ Infrastructure deployed successfully!" -ForegroundColor Green
    
    # Deploy database schema
    Write-Host "Setting up database schema..." -ForegroundColor Yellow
    
    # Get current public IP for firewall rule
    Write-Host "Getting current public IP address..." -ForegroundColor Cyan
    try {
        $currentIp = (Invoke-RestMethod -Uri "https://ipinfo.io/ip" -TimeoutSec 10).Trim()
        Write-Host "Current IP: $currentIp" -ForegroundColor White
        
        # Add temporary firewall rule for current IP
        Write-Host "Adding temporary firewall rule..." -ForegroundColor Cyan
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
    
    # Run SQL scripts in order
    Get-ChildItem "./sql_queries/*.sql" | Sort-Object Name | ForEach-Object {
        Write-Host "Executing $($_.Name)..." -ForegroundColor Cyan
        try {
            sqlcmd -S "$($sqlServerName).database.windows.net" -d $databaseName -G -i $_.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to execute $($_.Name), but continuing..."
            }
        } catch {
            Write-Warning "Error executing $($_.Name): $($_.Exception.Message)"
        }
    }
    
    # Remove temporary firewall rule
    if ($currentIp) {
        Write-Host "Removing temporary firewall rule..." -ForegroundColor Cyan
        try {
            az sql server firewall-rule delete `
                --resource-group $ResourceGroupName `
                --server $sqlServerName `
                --name "TempDeploymentRule" `
                --yes
        } catch {
            Write-Warning "Could not remove temporary firewall rule. Please remove 'TempDeploymentRule' manually."
        }
    }

    # Deploy applications
    Write-Host "Deploying applications..." -ForegroundColor Yellow

    # Deploy API
    Write-Host "Deploying API application..." -ForegroundColor Cyan
    Set-Location "./api"
    Compress-Archive -Path "*" -DestinationPath "../api.zip" -Force
    Set-Location ".."
    az webapp deployment source config-zip --resource-group $ResourceGroupName --name $apiAppName --src "./api.zip"
    Remove-Item "./api.zip" -Force -ErrorAction SilentlyContinue

    # Deploy Frontend
    Write-Host "Deploying Frontend application..." -ForegroundColor Cyan
    Set-Location "./front_end"
    Compress-Archive -Path "*" -DestinationPath "../frontend.zip" -Force
    Set-Location ".."
    az webapp deployment source config-zip --resource-group $ResourceGroupName --name $frontendAppName --src "./frontend.zip"
    Remove-Item "./frontend.zip" -Force -ErrorAction SilentlyContinue

    # Deploy Function (if func command is available)
    Write-Host "Deploying Function application..." -ForegroundColor Cyan
    try {
        Set-Location "./task"
        func azure functionapp publish $functionAppName
        Set-Location ".."
    } catch {
        Write-Warning "Function deployment failed. Please deploy manually using: func azure functionapp publish $functionAppName"
    }

    Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Deployment Summary:" -ForegroundColor Cyan
    Write-Host "API URL: https://$($apiAppName).azurewebsites.net" -ForegroundColor White
    Write-Host "Frontend URL: https://$frontendAppName).azurewebsites.net" -ForegroundColor White
    Write-Host "SQL Server: $($sqlServerName).database.windows.net" -ForegroundColor White
    Write-Host "Database: $databaseName" -ForegroundColor White
    Write-Host ""
    Write-Host "🔧 Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Configure App Registrations in Azure AD" -ForegroundColor White
    Write-Host "2. Update environment variables with client IDs" -ForegroundColor White
    Write-Host "3. Create security groups and assign managed identities" -ForegroundColor White
    Write-Host "4. Test the deployment" -ForegroundColor White

} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    Remove-Item "./temp-params.json" -Force -ErrorAction SilentlyContinue
    exit 1
}