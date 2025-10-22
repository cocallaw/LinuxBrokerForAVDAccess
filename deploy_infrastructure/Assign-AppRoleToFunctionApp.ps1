# Assign-AppRoleToFunctionApp.ps1
# Assigns API app role to Function App's managed identity for authentication

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$FunctionAppName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ApiAppId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "./app-registration-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$AppRoleValue = "ScheduledTask"
)

Write-Host "🔐 Assigning App Role to Function App Managed Identity..." -ForegroundColor Green

# Helper function to write timestamped messages
function Write-TimestampedHost {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

# Try to load configuration from file if it exists
$config = $null
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        Write-TimestampedHost "✅ Loaded configuration from $ConfigFile" -ForegroundColor Green
    } catch {
        Write-Warning "Could not read configuration file: $($_.Exception.Message)"
    }
}

# Use parameters or fall back to config file values
if ([string]::IsNullOrEmpty($ApiAppId) -and $config -and $config.ApiAppId -and $config.ApiAppId -ne "FAILED_TO_CREATE") {
    $ApiAppId = $config.ApiAppId
    Write-TimestampedHost "Using API App ID from config: $ApiAppId" -ForegroundColor Cyan
}

# If we still don't have required values, prompt or error
if ([string]::IsNullOrEmpty($SubscriptionId)) {
    try {
        $account = az account show --output json | ConvertFrom-Json
        $SubscriptionId = $account.id
        Write-TimestampedHost "Using current subscription: $SubscriptionId" -ForegroundColor Cyan
    } catch {
        Write-Error "Could not determine subscription. Please provide -SubscriptionId parameter or login with az login"
        exit 1
    }
}

if ([string]::IsNullOrEmpty($ApiAppId)) {
    Write-Error "API App ID is required. Provide -ApiAppId parameter or ensure app-registration-config.json exists with valid ApiAppId"
    exit 1
}

# Set Azure context
Write-TimestampedHost "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Get Function App managed identity if not provided
if ([string]::IsNullOrEmpty($FunctionAppName)) {
    if ([string]::IsNullOrEmpty($ResourceGroupName)) {
        Write-Error "Either FunctionAppName or ResourceGroupName is required to discover Function App"
        exit 1
    }
    
    Write-TimestampedHost "Discovering Function Apps in resource group..." -ForegroundColor Yellow
    try {
        $functionApps = az functionapp list --resource-group $ResourceGroupName --query "[].name" --output tsv
        if ($functionApps -and $functionApps.Count -gt 0) {
            $FunctionAppName = $functionApps[0]  # Take the first one
            Write-TimestampedHost "Found Function App: $FunctionAppName" -ForegroundColor Cyan
        } else {
            Write-Error "No Function Apps found in resource group $ResourceGroupName"
            exit 1
        }
    } catch {
        Write-Error "Failed to discover Function Apps: $($_.Exception.Message)"
        exit 1
    }
}

# Get Function App's managed identity principal ID
Write-TimestampedHost "Getting Function App managed identity..." -ForegroundColor Yellow
try {
    $functionAppIdentity = az functionapp identity show --name $FunctionAppName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    if ($functionAppIdentity -and $functionAppIdentity.principalId) {
        $functionAppSpId = $functionAppIdentity.principalId
        Write-TimestampedHost "Function App Managed Identity Principal ID: $functionAppSpId" -ForegroundColor Cyan
    } else {
        Write-Error "Function App '$FunctionAppName' does not have a managed identity enabled"
        exit 1
    }
} catch {
    Write-Error "Failed to get Function App managed identity: $($_.Exception.Message)"
    exit 1
}

# Check if Microsoft Graph PowerShell module is installed
Write-TimestampedHost "Checking Microsoft Graph PowerShell module..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-TimestampedHost "Installing Microsoft Graph PowerShell module..." -ForegroundColor Cyan
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph -Force

# Connect to Microsoft Graph
Write-TimestampedHost "Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome
    Write-TimestampedHost "✅ Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# Get the Function App service principal
Write-TimestampedHost "Looking up Function App service principal..." -ForegroundColor Yellow
try {
    $functionAppSp = Get-MgServicePrincipal -Filter "Id eq '$functionAppSpId'"
    if ($functionAppSp) {
        Write-TimestampedHost "✅ Found Function App service principal: $($functionAppSp.DisplayName)" -ForegroundColor Green
    } else {
        Write-Error "Could not find service principal for Function App managed identity"
        exit 1
    }
} catch {
    Write-Error "Failed to get Function App service principal: $($_.Exception.Message)"
    exit 1
}

# Get the API service principal
Write-TimestampedHost "Looking up API service principal..." -ForegroundColor Yellow
try {
    $apiSp = Get-MgServicePrincipal -Filter "AppId eq '$ApiAppId'"
    if ($apiSp) {
        Write-TimestampedHost "✅ Found API service principal: $($apiSp.DisplayName)" -ForegroundColor Green
    } else {
        Write-Error "Could not find service principal for API App ID: $ApiAppId"
        exit 1
    }
} catch {
    Write-Error "Failed to get API service principal: $($_.Exception.Message)"
    exit 1
}

# Find the required app role
Write-TimestampedHost "Looking for '$AppRoleValue' app role..." -ForegroundColor Yellow
$appRole = $apiSp.AppRoles | Where-Object { $_.Value -eq $AppRoleValue -and $_.AllowedMemberTypes -contains "Application" }

if ($null -eq $appRole) {
    Write-Error "App role '$AppRoleValue' not found in API application '$($apiSp.DisplayName)'"
    Write-Host "Available app roles:" -ForegroundColor Yellow
    $apiSp.AppRoles | Where-Object { $_.AllowedMemberTypes -contains "Application" } | ForEach-Object {
        Write-Host "  - $($_.Value): $($_.DisplayName)" -ForegroundColor White
    }
    exit 1
}

Write-TimestampedHost "✅ Found app role: $($appRole.DisplayName)" -ForegroundColor Green

# Check if assignment already exists
Write-TimestampedHost "Checking for existing app role assignments..." -ForegroundColor Yellow
$existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionAppSp.Id
$existingAssignment = $existingAssignments | Where-Object { $_.ResourceId -eq $apiSp.Id -and $_.AppRoleId -eq $appRole.Id }

if ($existingAssignment) {
    Write-TimestampedHost "✅ App role assignment already exists!" -ForegroundColor Green
    Write-TimestampedHost "Assignment ID: $($existingAssignment.Id)" -ForegroundColor Cyan
} else {
    # Create the app role assignment
    Write-TimestampedHost "Creating app role assignment..." -ForegroundColor Yellow
    try {
        $assignment = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionAppSp.Id -PrincipalId $functionAppSp.Id -ResourceId $apiSp.Id -AppRoleId $appRole.Id
        Write-TimestampedHost "✅ Successfully created app role assignment!" -ForegroundColor Green
        Write-TimestampedHost "Assignment ID: $($assignment.Id)" -ForegroundColor Cyan
    } catch {
        Write-Error "Failed to create app role assignment: $($_.Exception.Message)"
        exit 1
    }
}

# Display current assignments
Write-TimestampedHost "Current app role assignments for Function App:" -ForegroundColor Cyan
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $functionAppSp.Id | ForEach-Object {
    $appRoleAssignment = $_
    $resourceSp = Get-MgServicePrincipal -ServicePrincipalId $appRoleAssignment.ResourceId
    $assignedRole = $resourceSp.AppRoles | Where-Object { $_.Id -eq $appRoleAssignment.AppRoleId }
    
    Write-Host "  ✅ $($assignedRole.DisplayName) ($($assignedRole.Value)) on $($resourceSp.DisplayName)" -ForegroundColor Green
}

Write-TimestampedHost "✅ App role assignment completed successfully!" -ForegroundColor Green

Disconnect-MgGraph
