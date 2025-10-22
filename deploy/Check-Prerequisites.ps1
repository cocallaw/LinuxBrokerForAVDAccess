# Check-Prerequisites.ps1
# Validates that all required tools and permissions are available for Linux Broker for AVD Access deployment

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipPermissionCheck
)

Write-Host "🔍 Checking deployment prerequisites for Linux Broker for AVD Access..." -ForegroundColor Green

$errors = @()
$warnings = @()
$info = @()

# Check Azure CLI
try {
    $azVersionJson = az version --output json 2>$null | ConvertFrom-Json
    if ($azVersionJson -and $azVersionJson.'azure-cli') {
        $azVersion = $azVersionJson.'azure-cli'
        Write-Host "✅ Azure CLI: $azVersion" -ForegroundColor Green
    } else {
        $errors += "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    }
} catch {
    $errors += "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
}

# Check Bicep CLI
try {
    $bicepVersion = az bicep version 2>$null
    if ($bicepVersion) {
        Write-Host "✅ Bicep CLI: $bicepVersion" -ForegroundColor Green
    } else {
        $errors += "Bicep CLI not found. Install with: az bicep install"
    }
} catch {
    $errors += "Bicep CLI not found. Install with: az bicep install"
}

# Check Azure Functions Core Tools
try {
    $funcVersion = $null
    $funcCommand = Get-Command func -ErrorAction SilentlyContinue
    if ($funcCommand) {
        $funcVersion = func --version 2>$null
        if ($funcVersion) {
            Write-Host "✅ Azure Functions Core Tools: $funcVersion" -ForegroundColor Green
        } else {
            $warnings += "Azure Functions Core Tools found but version check failed"
        }
    } else {
        $warnings += "Azure Functions Core Tools not found. Install from: https://docs.microsoft.com/azure/azure-functions/functions-run-local"
    }
} catch {
    $warnings += "Azure Functions Core Tools not found. Install from: https://docs.microsoft.com/azure/azure-functions/functions-run-local"
}

# Check SQL Command Line Tools
try {
    $sqlcmdVersion = sqlcmd -? 2>$null
    if ($sqlcmdVersion) {
        Write-Host "✅ SQL Command Line Tools available" -ForegroundColor Green
    } else {
        $warnings += "SQLCMD not found. Install from: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install"
    }
} catch {
    $warnings += "SQLCMD not found. Install from: https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-download-install"
}

# Check Azure login status
try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
    if ($account) {
        Write-Host "✅ Logged into Azure as: $($account.user.name)" -ForegroundColor Green
        Write-Host "   Subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan
        
        # If specific subscription provided, check if it matches
        if ($SubscriptionId -and $account.id -ne $SubscriptionId) {
            $warnings += "Currently logged into subscription '$($account.id)' but target is '$SubscriptionId'. Run: az account set --subscription $SubscriptionId"
        }
    } else {
        $errors += "Not logged into Azure. Run: az login"
    }
} catch {
    $errors += "Not logged into Azure. Run: az login"
}

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Write-Host "✅ PowerShell: $($psVersion.ToString())" -ForegroundColor Green
} elseif ($psVersion.Major -eq 5) {
    Write-Host "⚠️  PowerShell: $($psVersion.ToString()) (PowerShell 7+ recommended)" -ForegroundColor Yellow
    $warnings += "PowerShell 7+ is recommended for better performance and compatibility"
} else {
    $errors += "PowerShell 5.1 or later is required"
}

# Check if running in compatible environment
if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Host "✅ Running on Windows" -ForegroundColor Green
} elseif ($IsLinux) {
    Write-Host "✅ Running on Linux" -ForegroundColor Green
    $info += "Linux environment detected - some commands may behave differently"
} elseif ($IsMacOS) {
    Write-Host "✅ Running on macOS" -ForegroundColor Green
    $info += "macOS environment detected - some commands may behave differently"
}

# Check Git (for cloning repository)
try {
    $gitVersion = git --version 2>$null
    if ($gitVersion) {
        Write-Host "✅ Git: $gitVersion" -ForegroundColor Green
    } else {
        $warnings += "Git not found. Required for cloning the repository if not already done"
    }
} catch {
    $warnings += "Git not found. Required for cloning the repository if not already done"
}

# Check required Azure permissions
if ($account -and -not $SkipPermissionCheck) {
    Write-Host "🔐 Checking Azure permissions..." -ForegroundColor Yellow
    
    # Check if user can create resource groups
    try {
        $permissions = az provider list --query "[?namespace=='Microsoft.Resources'].resourceTypes[?resourceType=='resourceGroups'].apiVersions" --output json 2>$null
        if ($permissions) {
            Write-Host "✅ Can access resource providers" -ForegroundColor Green
        } else {
            $warnings += "May not have permissions to view resource providers"
        }
    } catch {
        $warnings += "Could not check resource provider permissions"
    }
    
    # Check required resource providers
    $requiredProviders = @(
        "Microsoft.Web",
        "Microsoft.Sql", 
        "Microsoft.KeyVault",
        "Microsoft.Storage",
        "Microsoft.Compute",
        "Microsoft.Network"
    )
    
    Write-Host "Checking required resource providers..." -ForegroundColor Yellow
    foreach ($provider in $requiredProviders) {
        try {
            $providerStatus = az provider show --namespace $provider --query "registrationState" --output tsv 2>$null
            if ($providerStatus -eq "Registered") {
                Write-Host "✅ ${provider}: Registered" -ForegroundColor Green
            } elseif ($providerStatus -eq "NotRegistered") {
                $warnings += "Resource provider '$provider' is not registered. Register with: az provider register --namespace $provider"
            } else {
                $info += "Resource provider '$provider' status: $providerStatus"
            }
        } catch {
            $warnings += "Could not check registration status for provider '$provider'"
        }
    }
}

# Check if we're in the correct repository directory
$currentPath = Get-Location
$bicepPath = Join-Path $currentPath "bicep"
$deployPath = Join-Path $currentPath "deploy"

if (Test-Path $bicepPath) {
    Write-Host "✅ Repository structure: Found bicep directory" -ForegroundColor Green
} else {
    $errors += "Not in the correct repository directory. Ensure you're in the LinuxBrokerForAVDAccess root directory"
}

if (Test-Path $deployPath) {
    Write-Host "✅ Repository structure: Found deploy directory" -ForegroundColor Green
} else {
    $warnings += "Deploy directory not found in current location"
}

# Check for critical bicep files and validate syntax
Write-Host "🔍 Validating Bicep templates..." -ForegroundColor Yellow

$criticalFiles = @(
    "bicep/main.bicep",
    "bicep/infrastructure/main.bicep", 
    "bicep/AVD/main.bicep",
    "bicep/Linux/main.bicep"
)

foreach ($file in $criticalFiles) {
    $fullPath = Join-Path $currentPath $file
    if (Test-Path $fullPath) {
        Write-Host "✅ Found: $file" -ForegroundColor Green
        
        # Validate bicep syntax if bicep CLI is available
        if ($bicepVersion) {
            try {
                az bicep build --file $fullPath --stdout 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   ✅ Syntax valid" -ForegroundColor Green
                } else {
                    $warnings += "Bicep file '$file' has syntax issues. Run: az bicep build --file $fullPath"
                }
            } catch {
                $warnings += "Could not validate syntax for '$file'"
            }
        }
    } else {
        $errors += "Missing critical file: $file"
    }
}

# Check parameter files
$paramFiles = @(
    "bicep/main.bicepparam",
    "bicep/infrastructure/main.bicepparam"
)

foreach ($paramFile in $paramFiles) {
    $fullPath = Join-Path $currentPath $paramFile
    if (Test-Path $fullPath) {
        Write-Host "✅ Found parameter file: $paramFile" -ForegroundColor Green
    } else {
        $warnings += "Parameter file not found: $paramFile (will use default values)"
    }
}

# Display results
Write-Host "`n📊 Prerequisites Check Results:" -ForegroundColor Cyan

if ($errors.Count -eq 0) {
    Write-Host "✅ ALL PREREQUISITES MET!" -ForegroundColor Green
    Write-Host "   Ready for deployment! 🚀" -ForegroundColor Green
} else {
    Write-Host "❌ CRITICAL ISSUES FOUND:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   • $_" -ForegroundColor Red }
}

if ($warnings.Count -gt 0) {
    Write-Host "`n⚠️  WARNINGS:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "   • $_" -ForegroundColor Yellow }
}

if ($info.Count -gt 0) {
    Write-Host "`nℹ️  INFORMATION:" -ForegroundColor Cyan
    $info | ForEach-Object { Write-Host "   • $_" -ForegroundColor Cyan }
}

Write-Host "`n📋 RECOMMENDED NEXT STEPS:" -ForegroundColor Cyan
if ($errors.Count -gt 0) {
    Write-Host "1. 🔧 Fix the critical issues listed above" -ForegroundColor White
    Write-Host "2. 🔄 Run this script again to verify fixes" -ForegroundColor White
    Write-Host "3. 📖 Check the deployment documentation if needed" -ForegroundColor White
} else {
    Write-Host "1. 🔧 (Optional) Address any warnings above" -ForegroundColor White
    Write-Host "2. 🔐 Run Setup-AppRegistrations.ps1 to create Azure AD apps" -ForegroundColor White
    Write-Host "3. 🚀 Run Deploy-LinuxBroker.ps1 to start deployment" -ForegroundColor White
    Write-Host "4. ⚙️  Configure environment variables after deployment" -ForegroundColor White
}

Write-Host "`n💡 QUICK START COMMANDS:" -ForegroundColor Magenta
Write-Host "   Full Workflow:" -ForegroundColor Yellow
Write-Host "   1. Setup Azure AD:      .\deploy\Setup-AppRegistrations.ps1 -TenantId <your-tenant-id>" -ForegroundColor White
Write-Host "   2. Deploy Everything:   .\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg-name> -Location <location>" -ForegroundColor White
Write-Host "   " -ForegroundColor White
Write-Host "   Manual Workflow:" -ForegroundColor Yellow
Write-Host "   1. Deploy Infrastructure: .\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg-name> -Location <location> -ConfigurePermissions `$false" -ForegroundColor White
Write-Host "   2. Setup Azure AD:        .\deploy\Setup-AppRegistrations.ps1 -TenantId <your-tenant-id>" -ForegroundColor White
Write-Host "   3. Configure Permissions: .\deploy_infrastructure\Assign-AppRoleToFunctionApp.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg-name>" -ForegroundColor White

if ($errors.Count -gt 0) {
    exit 1
} else {
    exit 0
}