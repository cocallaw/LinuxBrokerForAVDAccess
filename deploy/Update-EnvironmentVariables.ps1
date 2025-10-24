# Update-EnvironmentVariables.ps1
# Updates environment variables for Linux Broker App Services using app-registration-config.json
# Optionally restarts the App Services to load the new environment variables

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFilePath = "./app-registration-config.json",
    
    [Parameter(Mandatory = $false)]
    [string]$VMSubscriptionId = "",
    
    [Parameter(Mandatory = $false)]
    [string]$VMResourceGroup = "",
    
    [Parameter(Mandatory = $false)]
    [string]$LinuxHostAdminLoginName = "azureuser",
    
    [Parameter(Mandatory = $false)]
    [string]$DomainName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$NFSShare = "",
    
    [Parameter(Mandatory = $false)]
    [string]$GraphAPIEndpoint = "https://graph.microsoft.com/.default",
    
    [Parameter(Mandatory = $false)]
    [string]$DBUsername = "sqladmin",
    
    [Parameter(Mandatory = $false)]
    [string]$DBPasswordKeyName = "SqlAdminPassword",
    
    [Parameter(Mandatory = $false)]
    [string]$SSHKeyName = "LinuxHostSSHKey",
    
    [Parameter(Mandatory = $false)]
    [string]$FlaskSecretKey = "",
    
    [Parameter(Mandatory = $false)]
    [bool]$RestartServices = $true  # Set to $false to skip restarting App Services
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

Write-TimestampedHost "🔧 Starting environment variable update process..." -ForegroundColor Green

# Set default values if not provided
if ([string]::IsNullOrEmpty($VMSubscriptionId)) {
    $VMSubscriptionId = $SubscriptionId
    Write-TimestampedHost "Using same subscription for VMs: $VMSubscriptionId" -ForegroundColor Cyan
}

if ([string]::IsNullOrEmpty($VMResourceGroup)) {
    $VMResourceGroup = $ResourceGroupName
    Write-TimestampedHost "Using same resource group for VMs: $VMResourceGroup" -ForegroundColor Cyan
}

# Generate Flask secret key if not provided
if ([string]::IsNullOrEmpty($FlaskSecretKey)) {
    $FlaskSecretKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    Write-TimestampedHost "Generated Flask secret key" -ForegroundColor Yellow
}

# Check if config file exists
if (-not (Test-Path $ConfigFilePath)) {
    Write-Error "App registration config file not found: $ConfigFilePath"
    Write-Host "💡 Run Setup-AppRegistrations.ps1 first to create the configuration file" -ForegroundColor Yellow
    exit 1
}

# Load configuration
try {
    $config = Get-Content $ConfigFilePath | ConvertFrom-Json
    Write-TimestampedHost "✅ Loaded configuration from: $ConfigFilePath" -ForegroundColor Green
} catch {
    Write-Error "Failed to parse configuration file: $($_.Exception.Message)"
    exit 1
}

# Validate required configuration values
$requiredFields = @("ApiAppId", "FrontendAppId", "FrontendClientSecret", "TenantId", "AVDHostGroupId", "LinuxHostGroupId")
$missingFields = @()

foreach ($field in $requiredFields) {
    if (-not $config.$field -or $config.$field -eq "FAILED_TO_CREATE" -or $config.$field -eq "NOT_CREATED") {
        $missingFields += $field
    }
}

if ($missingFields.Count -gt 0) {
    Write-Error "Missing or invalid configuration values: $($missingFields -join ', ')"
    Write-Host "💡 Re-run Setup-AppRegistrations.ps1 to fix missing values" -ForegroundColor Yellow
    exit 1
}

# Set Azure context
Write-TimestampedHost "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set Azure subscription context"
    exit 1
}

# Find App Services in the resource group
Write-TimestampedHost "Discovering App Services in resource group..." -ForegroundColor Yellow
$appServices = az webapp list --resource-group $ResourceGroupName --query "[].{name:name, kind:kind}" -o json | ConvertFrom-Json

if (-not $appServices -or $appServices.Count -eq 0) {
    Write-Error "No App Services found in resource group: $ResourceGroupName"
    exit 1
}

# Identify each app service type
$apiApp = $appServices | Where-Object { $_.name -like "*-api-*" }
$frontendApp = $appServices | Where-Object { $_.name -like "*-web-*" }
$functionApp = $appServices | Where-Object { $_.name -like "*-func-*" -or $_.kind -eq "functionapp" }

if (-not $apiApp) {
    Write-Warning "API App Service not found (expected pattern: *-api-*)"
}
if (-not $frontendApp) {
    Write-Warning "Frontend App Service not found (expected pattern: *-web-*)"
}
if (-not $functionApp) {
    Write-Warning "Function App not found (expected pattern: *-func-* or kind: functionapp)"
}

# Update API App Environment Variables
if ($apiApp) {
    Write-TimestampedHost "🔄 Updating API App environment variables: $($apiApp.name)" -ForegroundColor Cyan
    
    $apiSettings = @{
        "CLIENT_ID" = $config.ApiAppId
        "TENANT_ID" = $config.TenantId
        "API_CLIENT_ID" = $config.ApiAppId
        "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET" = $config.FrontendClientSecret
        "AVD_HOST_GROUP_ID" = $config.AVDHostGroupId
        "LINUX_HOST_GROUP_ID" = $config.LinuxHostGroupId
        "VM_SUBSCRIPTION_ID" = $VMSubscriptionId
        "VM_RESOURCE_GROUP" = $VMResourceGroup
        "LINUX_HOST_ADMIN_LOGIN_NAME" = $LinuxHostAdminLoginName
        "GRAPH_API_ENDPOINT" = $GraphAPIEndpoint
        "DB_USERNAME" = $DBUsername
        "DB_PASSWORD_NAME" = $DBPasswordKeyName
        "KEY_NAME" = $SSHKeyName
    }
    
    # Add optional settings if provided
    if (-not [string]::IsNullOrEmpty($DomainName)) {
        $apiSettings["DOMAIN_NAME"] = $DomainName
    }
    if (-not [string]::IsNullOrEmpty($NFSShare)) {
        $apiSettings["NFS_SHARE"] = $NFSShare
    }
    
    # Convert to Azure CLI format
    $apiSettingsArray = @()
    foreach ($key in $apiSettings.Keys) {
        $apiSettingsArray += "$key=$($apiSettings[$key])"
    }
    
    try {
        az webapp config appsettings set --name $apiApp.name --resource-group $ResourceGroupName --settings $apiSettingsArray --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ API App environment variables updated successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to update API App environment variables"
        }
    } catch {
        Write-Warning "Error updating API App environment variables: $($_.Exception.Message)"
    }
}

# Update Frontend App Environment Variables
if ($frontendApp) {
    Write-TimestampedHost "🔄 Updating Frontend App environment variables: $($frontendApp.name)" -ForegroundColor Cyan
    
    $frontendSettings = @{
        "CLIENT_ID" = $config.FrontendAppId
        "TENANT_ID" = $config.TenantId
        "API_CLIENT_ID" = $config.ApiAppId
        "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET" = $config.FrontendClientSecret
        "WEBSITE_AUTH_AAD_ALLOWED_TENANTS" = $config.TenantId
        "FLASK_KEY" = $FlaskSecretKey
    }
    
    # Convert to Azure CLI format
    $frontendSettingsArray = @()
    foreach ($key in $frontendSettings.Keys) {
        $frontendSettingsArray += "$key=$($frontendSettings[$key])"
    }
    
    try {
        az webapp config appsettings set --name $frontendApp.name --resource-group $ResourceGroupName --settings $frontendSettingsArray --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ Frontend App environment variables updated successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to update Frontend App environment variables"
        }
    } catch {
        Write-Warning "Error updating Frontend App environment variables: $($_.Exception.Message)"
    }
}

# Update Function App Environment Variables
if ($functionApp) {
    Write-TimestampedHost "🔄 Updating Function App environment variables: $($functionApp.name)" -ForegroundColor Cyan
    
    $functionSettings = @{
        "API_CLIENT_ID" = $config.ApiAppId
    }
    
    # Convert to Azure CLI format
    $functionSettingsArray = @()
    foreach ($key in $functionSettings.Keys) {
        $functionSettingsArray += "$key=$($functionSettings[$key])"
    }
    
    try {
        az functionapp config appsettings set --name $functionApp.name --resource-group $ResourceGroupName --settings $functionSettingsArray --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ Function App environment variables updated successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to update Function App environment variables"
        }
    } catch {
        Write-Warning "Error updating Function App environment variables: $($_.Exception.Message)"
    }
}

Write-TimestampedHost ""
Write-TimestampedHost "📋 Environment Variable Update Summary:" -ForegroundColor Cyan
Write-TimestampedHost "Configuration Source: $ConfigFilePath" -ForegroundColor White
Write-TimestampedHost "Tenant ID: $($config.TenantId)" -ForegroundColor White
Write-TimestampedHost "API App ID: $($config.ApiAppId)" -ForegroundColor White
Write-TimestampedHost "Frontend App ID: $($config.FrontendAppId)" -ForegroundColor White
Write-TimestampedHost "AVD Host Group: $($config.AVDHostGroupId)" -ForegroundColor White
Write-TimestampedHost "Linux Host Group: $($config.LinuxHostGroupId)" -ForegroundColor White

if ($apiApp) {
    Write-TimestampedHost "✅ API App: $($apiApp.name)" -ForegroundColor Green
}
if ($frontendApp) {
    Write-TimestampedHost "✅ Frontend App: $($frontendApp.name)" -ForegroundColor Green
}
if ($functionApp) {
    Write-TimestampedHost "✅ Function App: $($functionApp.name)" -ForegroundColor Green
}

# Restart App Services if requested
if ($RestartServices) {
    Write-TimestampedHost ""
    Write-TimestampedHost "� Restarting App Services to load new environment variables..." -ForegroundColor Yellow
    
    # Restart API App
    if ($apiApp) {
        Write-TimestampedHost "Restarting API App: $($apiApp.name)" -ForegroundColor Cyan
        az webapp restart --name $apiApp.name --resource-group $ResourceGroupName --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ API App restarted successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to restart API App"
        }
    }

    # Restart Frontend App
    if ($frontendApp) {
        Write-TimestampedHost "Restarting Frontend App: $($frontendApp.name)" -ForegroundColor Cyan
        az webapp restart --name $frontendApp.name --resource-group $ResourceGroupName --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ Frontend App restarted successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to restart Frontend App"
        }
    }

    # Restart Function App
    if ($functionApp) {
        Write-TimestampedHost "Restarting Function App: $($functionApp.name)" -ForegroundColor Cyan
        az functionapp restart --name $functionApp.name --resource-group $ResourceGroupName --output none
        if ($LASTEXITCODE -eq 0) {
            Write-TimestampedHost "✅ Function App restarted successfully" -ForegroundColor Green
        } else {
            Write-Warning "Failed to restart Function App"
        }
    }
    
    Write-TimestampedHost "✅ All App Services restarted successfully!" -ForegroundColor Green
} else {
    Write-TimestampedHost ""
    Write-TimestampedHost "⏭️  App Services restart skipped (RestartServices = false)" -ForegroundColor Yellow
    Write-TimestampedHost "💡 To restart services manually, run:" -ForegroundColor Cyan
    if ($apiApp) {
        Write-TimestampedHost "   az webapp restart --name $($apiApp.name) --resource-group $ResourceGroupName" -ForegroundColor Gray
    }
    if ($frontendApp) {
        Write-TimestampedHost "   az webapp restart --name $($frontendApp.name) --resource-group $ResourceGroupName" -ForegroundColor Gray
    }
    if ($functionApp) {
        Write-TimestampedHost "   az functionapp restart --name $($functionApp.name) --resource-group $ResourceGroupName" -ForegroundColor Gray
    }
}

Write-TimestampedHost ""
Write-TimestampedHost "🔧 Next Steps:" -ForegroundColor Yellow
Write-TimestampedHost "1. Verify the environment variables in Azure Portal" -ForegroundColor White
if ($RestartServices) {
    Write-TimestampedHost "2. Test the applications to ensure they're working correctly" -ForegroundColor White
} else {
    Write-TimestampedHost "2. Restart the App Services to load new environment variables" -ForegroundColor White
    Write-TimestampedHost "3. Test the applications to ensure they're working correctly" -ForegroundColor White
}

Write-TimestampedHost ""
Write-TimestampedHost "✅ Environment variable update process completed!" -ForegroundColor Green