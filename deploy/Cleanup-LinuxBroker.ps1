# Cleanup-LinuxBroker.ps1
# Deletes all resources to allow for a fresh deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "🧹 Linux Broker Cleanup Script" -ForegroundColor Red
Write-Host "==============================" -ForegroundColor Red

# Set Azure context
Write-Host "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Check if resource group exists
$resourceGroupExists = az group exists --name $ResourceGroupName --output tsv
if ($resourceGroupExists -eq "false") {
    Write-Host "✅ Resource group '$ResourceGroupName' does not exist. Nothing to clean up!" -ForegroundColor Green
    exit 0
}

# Get resources in the resource group
Write-Host "🔍 Checking resources in resource group '$ResourceGroupName'..." -ForegroundColor Yellow
try {
    $resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    
    if ($resources.Count -eq 0) {
        Write-Host "✅ Resource group '$ResourceGroupName' is empty. Nothing to clean up!" -ForegroundColor Green
        if (-not $WhatIf) {
            Write-Host "Deleting empty resource group..." -ForegroundColor Yellow
            az group delete --name $ResourceGroupName --yes --no-wait
        }
        exit 0
    }
    
    Write-Host "📋 Found $($resources.Count) resources:" -ForegroundColor Cyan
    $resources | ForEach-Object {
        Write-Host "   • $($_.name) ($($_.type))" -ForegroundColor White
    }
} catch {
    Write-Error "Failed to list resources: $($_.Exception.Message)"
    exit 1
}

# Show what will be deleted
Write-Host ""
Write-Host "⚠️  WARNING: This will DELETE the following:" -ForegroundColor Red
Write-Host "   • Resource Group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "   • All $($resources.Count) resources listed above" -ForegroundColor Yellow
Write-Host "   • All data, configurations, and deployments" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "🔍 WHAT-IF MODE: No actual deletion will occur" -ForegroundColor Magenta
    Write-Host "To perform actual deletion, run without -WhatIf parameter" -ForegroundColor Magenta
    exit 0
}

# Confirmation prompt (unless Force is used)
if (-not $Force) {
    Write-Host ""
    $confirmation = Read-Host "Are you sure you want to delete everything? Type 'DELETE' to confirm"
    
    if ($confirmation -ne "DELETE") {
        Write-Host "❌ Cleanup cancelled by user" -ForegroundColor Yellow
        exit 0
    }
}

# Perform cleanup
Write-Host ""
Write-Host "🗑️  Starting cleanup process..." -ForegroundColor Red

# Delete resource group (this will delete all resources within it)
Write-Host "Deleting resource group '$ResourceGroupName' and all its resources..." -ForegroundColor Yellow
try {
    az group delete --name $ResourceGroupName --yes --no-wait
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Deletion initiated successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "📋 Status:" -ForegroundColor Cyan
        Write-Host "   • Resource group deletion has been started" -ForegroundColor White
        Write-Host "   • This process will continue in the background" -ForegroundColor White
        Write-Host "   • It may take several minutes to complete" -ForegroundColor White
        Write-Host ""
        Write-Host "🔍 To check deletion status:" -ForegroundColor Yellow
        Write-Host "   az group show --name $ResourceGroupName" -ForegroundColor White
        Write-Host ""
        Write-Host "✨ You can now run a fresh deployment!" -ForegroundColor Green
    } else {
        Write-Error "Failed to delete resource group"
        exit 1
    }
} catch {
    Write-Error "Error during cleanup: $($_.Exception.Message)"
    exit 1
}

# Cleanup temporary files
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow
$tempFiles = @(
    "./temp-params.json",
    "./api.zip",
    "./frontend.zip",
    "./app-registration-config.json"
)

foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        Write-Host "   Removed: $file" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "🎉 Cleanup completed!" -ForegroundColor Green
Write-Host "Ready for fresh deployment with:" -ForegroundColor Cyan
Write-Host "   .\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Location <location>" -ForegroundColor White