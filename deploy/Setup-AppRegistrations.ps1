# Setup-AppRegistrations.ps1
# Creates Azure AD App Registrations for the Linux Broker solution

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiAppName = "LinuxBroker-API",
    
    [Parameter(Mandatory=$false)]
    [string]$FrontendAppName = "LinuxBroker-Frontend",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentId = ""
)

Write-Host "🔐 Setting up Azure AD App Registrations..." -ForegroundColor Green

# Generate deployment ID if not provided
if ([string]::IsNullOrEmpty($DeploymentId)) {
    $DeploymentId = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    Write-Host "📝 Generated Deployment ID: $DeploymentId" -ForegroundColor Yellow
    Write-Host "   This will be appended to app registration names for easy identification" -ForegroundColor Cyan
} else {
    Write-Host "📝 Using provided Deployment ID: $DeploymentId" -ForegroundColor Yellow
}

# Update app names with deployment ID
$ApiAppName = "$ApiAppName-$DeploymentId"
$FrontendAppName = "$FrontendAppName-$DeploymentId"

Write-Host "App Registration Names:" -ForegroundColor Cyan
Write-Host "   API App: $ApiAppName" -ForegroundColor White
Write-Host "   Frontend App: $FrontendAppName" -ForegroundColor White

# Check if Microsoft Graph PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft Graph PowerShell module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
Write-Host "A device code will be displayed. Please follow the instructions to authenticate." -ForegroundColor Cyan
try {
    Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All", "Directory.Read.All", "Group.ReadWrite.All" -UseDeviceAuthentication
    Write-Host "✅ Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    Write-Host "💡 Try running the script as administrator or check your network connection" -ForegroundColor Yellow
    exit 1
}

# Create API App Registration
Write-Host "Creating API App Registration..." -ForegroundColor Cyan
$apiApp = New-MgApplication -DisplayName $ApiAppName -Description "Linux Broker for AVD - API Application"

# Create API App Service Principal
$apiServicePrincipal = New-MgServicePrincipal -AppId $apiApp.AppId

# Create API App Roles
$apiAppRoles = @(
    @{
        AllowedMemberTypes = @("Application")
        Description = "Allows access to AVD Host endpoints"
        DisplayName = "AVD Host"
        Id = [System.Guid]::NewGuid()
        IsEnabled = $true
        Value = "AVDHost"
    },
    @{
        AllowedMemberTypes = @("Application")
        Description = "Allows access to Linux Host endpoints"
        DisplayName = "Linux Host"
        Id = [System.Guid]::NewGuid()
        IsEnabled = $true
        Value = "LinuxHost"
    },
    @{
        AllowedMemberTypes = @("Application")
        Description = "Allows access to scheduled task endpoints"
        DisplayName = "Scheduled Task"
        Id = [System.Guid]::NewGuid()
        IsEnabled = $true
        Value = "ScheduledTask"
    },
    @{
        AllowedMemberTypes = @("User")
        Description = "Allows full access to the management portal"
        DisplayName = "Full Access"
        Id = [System.Guid]::NewGuid()
        IsEnabled = $true
        Value = "FullAccess"
    },
    @{
        AllowedMemberTypes = @("User")
        Description = "Allows user access to the management portal"
        DisplayName = "User"
        Id = [System.Guid]::NewGuid()
        IsEnabled = $true
        Value = "User"
    }
)

# Update API App with App Roles
Update-MgApplication -ApplicationId $apiApp.Id -AppRoles $apiAppRoles

Write-Host "✅ API App Registration created successfully!" -ForegroundColor Green
Write-Host "   App ID: $($apiApp.AppId)" -ForegroundColor White
Write-Host "   Object ID: $($apiApp.Id)" -ForegroundColor White

# Create Frontend App Registration
Write-Host "Creating Frontend App Registration..." -ForegroundColor Cyan
$frontendApp = New-MgApplication -DisplayName $FrontendAppName -Description "Linux Broker for AVD - Frontend Application"

# Create Frontend App Service Principal
$frontendServicePrincipal = New-MgServicePrincipal -AppId $frontendApp.AppId

# Generate client secret for frontend app
$clientSecret = Add-MgApplicationPassword -ApplicationId $frontendApp.Id -PasswordCredential @{
    DisplayName = "Default Secret"
    EndDateTime = (Get-Date).AddYears(2)
}

Write-Host "✅ Frontend App Registration created successfully!" -ForegroundColor Green
Write-Host "   App ID: $($frontendApp.AppId)" -ForegroundColor White
Write-Host "   Client Secret: $($clientSecret.SecretText)" -ForegroundColor Yellow
Write-Host "   ⚠️  Please save the client secret securely - it won't be shown again!" -ForegroundColor Red

# Create Security Groups
Write-Host "Creating Security Groups..." -ForegroundColor Cyan

$avdHostGroup = $null
$linuxHostGroup = $null

$avdHostGroupName = "LinuxBroker-AVDHost-VMs-$DeploymentId"
$linuxHostGroupName = "LinuxBroker-LinuxHost-VMs-$DeploymentId"

try {
    $avdHostGroup = New-MgGroup -DisplayName $avdHostGroupName -Description "Security group for AVD host managed identities (Deployment: $DeploymentId)" -MailEnabled:$false -SecurityEnabled:$true -MailNickname $avdHostGroupName
    Write-Host "✅ AVD Host security group created successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create AVD Host security group: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   This requires Group.ReadWrite.All permissions or Global Administrator role" -ForegroundColor Yellow
}

try {
    $linuxHostGroup = New-MgGroup -DisplayName $linuxHostGroupName -Description "Security group for Linux host managed identities (Deployment: $DeploymentId)" -MailEnabled:$false -SecurityEnabled:$true -MailNickname $linuxHostGroupName
    Write-Host "✅ Linux Host security group created successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create Linux Host security group: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   This requires Group.ReadWrite.All permissions or Global Administrator role" -ForegroundColor Yellow
}

if ($avdHostGroup -or $linuxHostGroup) {
    Write-Host "✅ Some security groups created successfully!" -ForegroundColor Green
    if ($avdHostGroup) { Write-Host "   AVD Host Group ID: $($avdHostGroup.Id)" -ForegroundColor White }
    if ($linuxHostGroup) { Write-Host "   Linux Host Group ID: $($linuxHostGroup.Id)" -ForegroundColor White }
} else {
    Write-Host "⚠️  No security groups were created due to insufficient permissions" -ForegroundColor Yellow
    Write-Host "   You can create these manually in the Azure portal or ask an administrator to run this script" -ForegroundColor Cyan
}

# Output summary
Write-Host ""
Write-Host "📋 App Registration Summary:" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Deployment ID: $DeploymentId" -ForegroundColor Magenta
Write-Host ""
Write-Host "API App Registration:" -ForegroundColor Yellow
Write-Host "   Name: $ApiAppName" -ForegroundColor White
Write-Host "   App ID: $($apiApp.AppId)" -ForegroundColor White
Write-Host "   Service Principal ID: $($apiServicePrincipal.Id)" -ForegroundColor White
Write-Host ""
Write-Host "Frontend App Registration:" -ForegroundColor Yellow
Write-Host "   Name: $FrontendAppName" -ForegroundColor White
Write-Host "   App ID: $($frontendApp.AppId)" -ForegroundColor White
Write-Host "   Client Secret: $($clientSecret.SecretText)" -ForegroundColor White
Write-Host "   Service Principal ID: $($frontendServicePrincipal.Id)" -ForegroundColor White
Write-Host ""
Write-Host "Security Groups:" -ForegroundColor Yellow
if ($avdHostGroup) {
    Write-Host "   AVD Host Group: $($avdHostGroup.Id) ($avdHostGroupName)" -ForegroundColor White
} else {
    Write-Host "   AVD Host Group: Not created (insufficient permissions)" -ForegroundColor Red
}
if ($linuxHostGroup) {
    Write-Host "   Linux Host Group: $($linuxHostGroup.Id) ($linuxHostGroupName)" -ForegroundColor White
} else {
    Write-Host "   Linux Host Group: Not created (insufficient permissions)" -ForegroundColor Red
}
Write-Host ""
Write-Host "🔧 Next Steps:" -ForegroundColor Green
Write-Host "1. Update your App Service environment variables with these values" -ForegroundColor White
if (-not $avdHostGroup -or -not $linuxHostGroup) {
    Write-Host "2. Create the missing security groups manually in Azure portal:" -ForegroundColor Yellow
    if (-not $avdHostGroup) {
        Write-Host "   - LinuxBroker-AVDHost-VMs (for AVD host managed identities)" -ForegroundColor White
    }
    if (-not $linuxHostGroup) {
        Write-Host "   - LinuxBroker-LinuxHost-VMs (for Linux host managed identities)" -ForegroundColor White
    }
    Write-Host "3. Assign managed identities to the appropriate security groups" -ForegroundColor White
    Write-Host "4. Grant API permissions to the applications" -ForegroundColor White
    Write-Host "5. Test the configuration" -ForegroundColor White
} else {
    Write-Host "2. Assign managed identities to the appropriate security groups" -ForegroundColor White
    Write-Host "3. Grant API permissions to the applications" -ForegroundColor White
    Write-Host "4. Test the configuration" -ForegroundColor White
}

# Save configuration to file
$config = @{
    DeploymentId = $DeploymentId
    TenantId = $TenantId
    ApiAppId = $apiApp.AppId
    ApiAppName = $ApiAppName
    ApiServicePrincipalId = $apiServicePrincipal.Id
    FrontendAppId = $frontendApp.AppId
    FrontendAppName = $FrontendAppName
    FrontendClientSecret = $clientSecret.SecretText
    FrontendServicePrincipalId = $frontendServicePrincipal.Id
    AVDHostGroupId = if ($avdHostGroup) { $avdHostGroup.Id } else { "NOT_CREATED" }
    AVDHostGroupName = $avdHostGroupName
    LinuxHostGroupId = if ($linuxHostGroup) { $linuxHostGroup.Id } else { "NOT_CREATED" }
    LinuxHostGroupName = $linuxHostGroupName
}

$config | ConvertTo-Json -Depth 3 | Out-File -FilePath "./app-registration-config.json" -Encoding UTF8
Write-Host "💾 Configuration saved to: ./app-registration-config.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "🧹 For easy cleanup, search for resources with deployment ID: $DeploymentId" -ForegroundColor Magenta

Disconnect-MgGraph