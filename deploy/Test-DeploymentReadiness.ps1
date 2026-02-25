# Test-DeploymentReadiness.ps1
# Pre-deployment validation for Linux Broker for AVD Access
# Checks tools, Azure access, permissions, config files, and environment variables.
# Usage: .\deploy\Test-DeploymentReadiness.ps1 [-SubscriptionId <id>] [-ConfigPath <path>]

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$SkipAzureChecks
)

$ErrorActionPreference = "Continue"

# --- Results tracking ---
$results = [System.Collections.ArrayList]::new()

function Add-Result {
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,  # PASS, FAIL, WARN
        [string]$Detail = ""
    )
    [void]$results.Add([PSCustomObject]@{
        Category = $Category
        Check    = $Check
        Status   = $Status
        Detail   = $Detail
    })
}

function Write-ResultTable {
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host " DEPLOYMENT READINESS REPORT" -ForegroundColor Cyan
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("{0,-18} {1,-32} {2,-6} {3}" -f "CATEGORY", "CHECK", "STATUS", "DETAIL") -ForegroundColor White
    Write-Host ("{0,-18} {1,-32} {2,-6} {3}" -f ("─" * 18), ("─" * 32), ("─" * 6), ("─" * 30)) -ForegroundColor DarkGray

    foreach ($r in $results) {
        $color = switch ($r.Status) {
            "PASS" { "Green" }
            "FAIL" { "Red" }
            "WARN" { "Yellow" }
            default { "White" }
        }
        $statusIcon = switch ($r.Status) {
            "PASS" { "✅" }
            "FAIL" { "❌" }
            "WARN" { "⚠️ " }
            default { "  " }
        }
        Write-Host ("{0,-18} {1,-32} " -f $r.Category, $r.Check) -NoNewline -ForegroundColor White
        Write-Host ("{0} " -f $statusIcon) -NoNewline -ForegroundColor $color
        Write-Host $r.Detail -ForegroundColor $color
    }

    $passCount = ($results | Where-Object Status -eq "PASS").Count
    $failCount = ($results | Where-Object Status -eq "FAIL").Count
    $warnCount = ($results | Where-Object Status -eq "WARN").Count
    $total = $results.Count

    Write-Host ""
    Write-Host ("=" * 90) -ForegroundColor Cyan
    Write-Host " SUMMARY: $passCount passed, $failCount failed, $warnCount warnings out of $total checks" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
    Write-Host ("=" * 90) -ForegroundColor Cyan

    if ($failCount -gt 0) {
        Write-Host "`n❌ DEPLOYMENT NOT READY — fix the failures above before deploying." -ForegroundColor Red
    } else {
        Write-Host "`n✅ ALL CHECKS PASSED — ready to deploy!" -ForegroundColor Green
    }
}

# ============================================================
# 1. REQUIRED TOOLS
# ============================================================

# Azure CLI
try {
    $azOut = az version --output json 2>$null | ConvertFrom-Json
    if ($azOut -and $azOut.'azure-cli') {
        Add-Result "Tools" "Azure CLI" "PASS" "v$($azOut.'azure-cli')"
    } else {
        Add-Result "Tools" "Azure CLI" "FAIL" "Not found. Install: https://aka.ms/installazurecli"
    }
} catch {
    Add-Result "Tools" "Azure CLI" "FAIL" "Not found. Install: https://aka.ms/installazurecli"
}

# Bicep CLI
try {
    $bicepOut = az bicep version 2>$null
    if ($bicepOut) {
        Add-Result "Tools" "Bicep CLI" "PASS" "$bicepOut"
    } else {
        Add-Result "Tools" "Bicep CLI" "FAIL" "Not found. Install: az bicep install"
    }
} catch {
    Add-Result "Tools" "Bicep CLI" "FAIL" "Not found. Install: az bicep install"
}

# PowerShell version
$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -ge 7) {
    Add-Result "Tools" "PowerShell" "PASS" "v$($psVer.ToString())"
} elseif ($psVer.Major -ge 5) {
    Add-Result "Tools" "PowerShell" "WARN" "v$($psVer.ToString()) — PowerShell 7+ recommended"
} else {
    Add-Result "Tools" "PowerShell" "FAIL" "v$($psVer.ToString()) — PowerShell 5.1+ required"
}

# Git
try {
    $gitVer = git --version 2>$null
    if ($gitVer) {
        Add-Result "Tools" "Git" "PASS" "$gitVer"
    } else {
        Add-Result "Tools" "Git" "WARN" "Not found — needed only for repo management"
    }
} catch {
    Add-Result "Tools" "Git" "WARN" "Not found — needed only for repo management"
}

# SQLCMD
try {
    $sqlcmdCheck = Get-Command sqlcmd -ErrorAction SilentlyContinue
    if ($sqlcmdCheck) {
        Add-Result "Tools" "SQLCMD" "PASS" "Available"
    } else {
        Add-Result "Tools" "SQLCMD" "WARN" "Not found — needed for direct DB operations"
    }
} catch {
    Add-Result "Tools" "SQLCMD" "WARN" "Not found — needed for direct DB operations"
}

# Azure Functions Core Tools
try {
    $funcCheck = Get-Command func -ErrorAction SilentlyContinue
    if ($funcCheck) {
        $funcVer = func --version 2>$null
        Add-Result "Tools" "Functions Core Tools" "PASS" "v$funcVer"
    } else {
        Add-Result "Tools" "Functions Core Tools" "WARN" "Not found — optional for local testing"
    }
} catch {
    Add-Result "Tools" "Functions Core Tools" "WARN" "Not found — optional for local testing"
}

# ============================================================
# 2. AZURE SUBSCRIPTION ACCESS
# ============================================================
if (-not $SkipAzureChecks) {
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        if ($account) {
            Add-Result "Azure" "Logged in" "PASS" "$($account.user.name)"
            Add-Result "Azure" "Subscription" "PASS" "$($account.name) ($($account.id))"

            if ($SubscriptionId -and $account.id -ne $SubscriptionId) {
                Add-Result "Azure" "Target subscription" "WARN" "Active sub differs from target $SubscriptionId"
            }
        } else {
            Add-Result "Azure" "Logged in" "FAIL" "Not logged in. Run: az login"
        }
    } catch {
        Add-Result "Azure" "Logged in" "FAIL" "Not logged in. Run: az login"
    }

    # Required resource providers
    $requiredProviders = @(
        "Microsoft.Web",
        "Microsoft.Sql",
        "Microsoft.KeyVault",
        "Microsoft.Storage",
        "Microsoft.Compute",
        "Microsoft.Network",
        "Microsoft.DesktopVirtualization"
    )

    foreach ($provider in $requiredProviders) {
        try {
            $status = az provider show --namespace $provider --query "registrationState" --output tsv 2>$null
            if ($status -eq "Registered") {
                Add-Result "Providers" $provider "PASS" "Registered"
            } elseif ($status) {
                Add-Result "Providers" $provider "WARN" "Status: $status — register with: az provider register --namespace $provider"
            } else {
                Add-Result "Providers" $provider "WARN" "Could not check"
            }
        } catch {
            Add-Result "Providers" $provider "WARN" "Could not check"
        }
    }
} else {
    Add-Result "Azure" "All Azure checks" "WARN" "Skipped (--SkipAzureChecks)"
}

# ============================================================
# 3. CONFIGURATION FILES — VALID JSON
# ============================================================

$repoRoot = (Get-Location).Path

# App registration config
$appRegConfig = Join-Path $repoRoot "app-registration-config.json"
if (Test-Path $appRegConfig) {
    try {
        $null = Get-Content $appRegConfig -Raw | ConvertFrom-Json
        Add-Result "Config" "app-registration-config" "PASS" "Valid JSON"
    } catch {
        Add-Result "Config" "app-registration-config" "FAIL" "Invalid JSON: $($_.Exception.Message)"
    }
} else {
    Add-Result "Config" "app-registration-config" "WARN" "File not found — may not be created yet"
}

# VM deployment config
$vmConfigFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $repoRoot "vm-deployment-config.example.json" }
if (Test-Path $vmConfigFile) {
    try {
        $null = Get-Content $vmConfigFile -Raw | ConvertFrom-Json
        Add-Result "Config" "vm-deployment-config" "PASS" "Valid JSON ($vmConfigFile)"
    } catch {
        Add-Result "Config" "vm-deployment-config" "FAIL" "Invalid JSON: $($_.Exception.Message)"
    }
} else {
    Add-Result "Config" "vm-deployment-config" "WARN" "Not found at $vmConfigFile"
}

# Deployment profile configs
$configDir = Join-Path $repoRoot "configs"
if (Test-Path $configDir) {
    $configFiles = Get-ChildItem -Path $configDir -Filter "*.json" -File
    foreach ($cf in $configFiles) {
        try {
            $null = Get-Content $cf.FullName -Raw | ConvertFrom-Json
            Add-Result "Config" $cf.Name "PASS" "Valid JSON"
        } catch {
            Add-Result "Config" $cf.Name "FAIL" "Invalid JSON: $($_.Exception.Message)"
        }
    }
} else {
    Add-Result "Config" "configs/ directory" "WARN" "Directory not found"
}

# ============================================================
# 4. REPOSITORY STRUCTURE
# ============================================================

$requiredDirs = @("bicep", "deploy", "api", "sql_queries", "front_end")
foreach ($dir in $requiredDirs) {
    $dirPath = Join-Path $repoRoot $dir
    if (Test-Path $dirPath) {
        Add-Result "Structure" "$dir/" "PASS" "Present"
    } else {
        Add-Result "Structure" "$dir/" "FAIL" "Missing directory"
    }
}

# Critical Bicep templates
$criticalBicep = @(
    "bicep/main.bicep",
    "bicep/infrastructure/main.bicep",
    "bicep/AVD/main.bicep",
    "bicep/Linux/main.bicep"
)

foreach ($bf in $criticalBicep) {
    $fullPath = Join-Path $repoRoot $bf
    if (Test-Path $fullPath) {
        Add-Result "Structure" $bf "PASS" "Present"
    } else {
        Add-Result "Structure" $bf "FAIL" "Missing critical Bicep template"
    }
}

# ============================================================
# 5. ENVIRONMENT VARIABLES (from api/env.example)
# ============================================================

$requiredEnvVars = @(
    "TENANT_ID",
    "CLIENT_ID",
    "VM_SUBSCRIPTION_ID",
    "VM_RESOURCE_GROUP",
    "DB_SERVER",
    "DB_DATABASE",
    "DB_USERNAME",
    "DB_PASSWORD_NAME",
    "VAULT_URL",
    "KEY_NAME",
    "AVD_HOST_GROUP_ID",
    "LINUX_HOST_GROUP_ID",
    "DOMAIN_NAME",
    "GRAPH_API_ENDPOINT",
    "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
)

# We check if these are set in the current shell — they typically
# wouldn't be during a pre-deployment check on a developer machine,
# so we report them as INFO-level warnings, not failures.
$envSetCount = 0
foreach ($var in $requiredEnvVars) {
    $val = [System.Environment]::GetEnvironmentVariable($var)
    if ($val) {
        $envSetCount++
    }
}

if ($envSetCount -eq $requiredEnvVars.Count) {
    Add-Result "Env Vars" "All required vars" "PASS" "$envSetCount/$($requiredEnvVars.Count) set"
} elseif ($envSetCount -gt 0) {
    Add-Result "Env Vars" "Required vars" "WARN" "$envSetCount/$($requiredEnvVars.Count) set — remaining configured at deploy time"
} else {
    Add-Result "Env Vars" "Required vars" "WARN" "0/$($requiredEnvVars.Count) set — will be configured during deployment"
}

# ============================================================
# OUTPUT
# ============================================================

Write-ResultTable

$failCount = ($results | Where-Object Status -eq "FAIL").Count
exit $(if ($failCount -gt 0) { 1 } else { 0 })
