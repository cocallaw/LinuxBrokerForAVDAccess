<#
.SYNOPSIS
    Deploys the Linux Broker database schema to Azure SQL Database.

.DESCRIPTION
    Executes all SQL scripts in the correct order against the target Azure SQL
    Database. All scripts are idempotent and safe to run multiple times.

.PARAMETER ServerName
    Azure SQL Server FQDN (e.g., "myserver.database.windows.net").

.PARAMETER DatabaseName
    Target database name (default: "linuxbroker").

.PARAMETER Username
    SQL authentication username. If omitted, uses Azure AD integrated auth.

.PARAMETER Password
    SQL authentication password. Required if Username is provided.

.PARAMETER UseAzureAD
    Use Azure AD authentication (requires Az.Accounts module and active login).

.EXAMPLE
    # SQL Authentication
    .\Deploy-Database.ps1 -ServerName "myserver.database.windows.net" -DatabaseName "linuxbroker" -Username "sqladmin" -Password "MyP@ssw0rd"

.EXAMPLE
    # Azure AD Authentication
    .\Deploy-Database.ps1 -ServerName "myserver.database.windows.net" -DatabaseName "linuxbroker" -UseAzureAD
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName,

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "linuxbroker",

    [Parameter(Mandatory = $false)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [switch]$UseAzureAD
)

$ErrorActionPreference = "Stop"

# Define execution order — tables first, then procedures, then indexes
$scriptOrder = @(
    # Step 1: Tables
    "001_create_table-vm_scaling_rules.sql",
    "002_create_table-vm_scaling_activity_log.sql",
    "003_create_table-virtual_machines.sql",
    "024_create_table-vmusers.sql",

    # Step 2: Stored Procedures
    "005_create_procedure-CheckoutVm.sql",
    "006_create_procedure-DeleteVm.sql",
    "007_create_procedure-AddVm.sql",
    "008_create_procedure-GetVmDetails.sql",
    "009_create_procedure-ReturnVm.sql",
    "010_create_procedure-GetScalingRules.sql",
    "011_create_procedure-UpdateScalingRule.sql",
    "012_create_procedure-TriggerScalingLogic.sql",
    "013_create_procedure-GetScalingActivityLog.sql",
    "014_create_procedure-GetVms.sql",
    "015_create_procedure-CreateScalingRule.sql",
    "016_create_procedure-ReleaseVm.sql",
    "017_create_procedure-UpdateVmAttributes.sql",
    "018_create_procedure-ReturnReleasedVms.sql",
    "019_create_procedure-DeleteScalingRule.sql",
    "020_create_procedure-GetVmHistory.sql",
    "021_create_procedure-GetVmScalingRulesHistory.sql",
    "022_create_procedure-GetScalingRuleDetails.sql",
    "023_create_procedure-GetDeletedVirtualMachines.sql",

    # Step 3: Indexes
    "025_add_indexes.sql"
)

$scriptDir = $PSScriptRoot

# Build connection arguments
function Get-SqlCmdArgs {
    $args = @("-S", $ServerName, "-d", $DatabaseName, "-I")

    if ($UseAzureAD) {
        $args += @("-G")
        Write-Host "Using Azure AD authentication." -ForegroundColor Cyan
    }
    elseif ($Username -and $Password) {
        $args += @("-U", $Username, "-P", $Password)
        Write-Host "Using SQL authentication." -ForegroundColor Cyan
    }
    else {
        Write-Error "Provide either -Username/-Password for SQL auth or -UseAzureAD for Azure AD auth."
        exit 1
    }

    return $args
}

# Test connectivity
function Test-Connection {
    param([string[]]$BaseArgs)

    Write-Host "`nTesting database connectivity..." -ForegroundColor Yellow
    try {
        $result = & sqlcmd @BaseArgs -Q "SELECT 1 AS ConnectionTest" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Database connection failed: $result"
            exit 1
        }
        Write-Host "Connection successful.`n" -ForegroundColor Green
    }
    catch {
        Write-Error "Cannot connect to $ServerName/$DatabaseName. Verify server name, credentials, and firewall rules."
        exit 1
    }
}

# Execute a single SQL file
function Invoke-SqlFile {
    param(
        [string]$FilePath,
        [string[]]$BaseArgs
    )

    $fileName = Split-Path $FilePath -Leaf
    Write-Host "  Executing: $fileName" -ForegroundColor White -NoNewline

    try {
        $output = & sqlcmd @BaseArgs -i $FilePath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            Write-Host "    Error: $output" -ForegroundColor Red
            return $false
        }
        Write-Host " OK" -ForegroundColor Green

        # Print any PRINT messages from the script
        $printLines = $output | Where-Object { $_ -and $_.ToString().Trim() -ne "" }
        foreach ($line in $printLines) {
            Write-Host "    $line" -ForegroundColor DarkGray
        }
        return $true
    }
    catch {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "    Exception: $_" -ForegroundColor Red
        return $false
    }
}

# Main deployment
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Linux Broker — Database Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Server:   $ServerName"
Write-Host "Database: $DatabaseName"
Write-Host "Scripts:  $($scriptOrder.Count) files"
Write-Host ""

$baseArgs = Get-SqlCmdArgs
Test-Connection -BaseArgs $baseArgs

$succeeded = 0
$failed = 0
$startTime = Get-Date

Write-Host "Deploying schema..." -ForegroundColor Yellow

foreach ($script in $scriptOrder) {
    $filePath = Join-Path $scriptDir $script

    if (-not (Test-Path $filePath)) {
        Write-Host "  MISSING: $script" -ForegroundColor Red
        $failed++
        continue
    }

    $result = Invoke-SqlFile -FilePath $filePath -BaseArgs $baseArgs
    if ($result) {
        $succeeded++
    }
    else {
        $failed++
    }
}

$elapsed = (Get-Date) - $startTime

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Deployment Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Succeeded: $succeeded" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Failed:    $failed" -ForegroundColor Red
}
else {
    Write-Host "  Failed:    $failed" -ForegroundColor Green
}
Write-Host "  Duration:  $($elapsed.TotalSeconds.ToString('F1'))s"
Write-Host ""

if ($failed -gt 0) {
    Write-Error "Deployment completed with $failed error(s). Review output above."
    exit 1
}

Write-Host "Deployment completed successfully." -ForegroundColor Green
exit 0
