# Add-VMsToSecurityGroups.ps1
# Adds existing VM managed identities to their appropriate security groups

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$AppConfigPath = "./app-registration-config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$AVDResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$LinuxResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Helper function to write timestamped messages
function Write-TimestampedHost {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $ForegroundColor
}

Write-TimestampedHost "👥 Adding VMs to security groups..." -ForegroundColor Green

# Set Azure context
Write-TimestampedHost "Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SubscriptionId

# Check if app registration config exists
if (-not (Test-Path $AppConfigPath)) {
    Write-Error "App registration config file not found: $AppConfigPath"
    Write-Host "💡 Run Setup-AppRegistrations.ps1 first to create security groups" -ForegroundColor Yellow
    exit 1
}

# Load app registration config
try {
    $appConfig = Get-Content $AppConfigPath | ConvertFrom-Json
    Write-TimestampedHost "✅ Loaded app registration config" -ForegroundColor Green
    Write-Host "   AVD Host Group ID: $($appConfig.AVDHostGroupId)" -ForegroundColor White
    Write-Host "   Linux Host Group ID: $($appConfig.LinuxHostGroupId)" -ForegroundColor White
} catch {
    Write-Error "Failed to load app registration config: $($_.Exception.Message)"
    exit 1
}

$successCount = 0
$errorCount = 0

# Process AVD VMs
if (-not [string]::IsNullOrEmpty($AVDResourceGroupName) -and $appConfig.AVDHostGroupId) {
    Write-TimestampedHost ""
    Write-TimestampedHost "Processing AVD VMs in resource group: $AVDResourceGroupName" -ForegroundColor Cyan
    
    try {
        # Get all VMs with managed identities in the resource group
        $avdVMs = az vm list --resource-group $AVDResourceGroupName --query "[?identity.type=='SystemAssigned'].{name:name, principalId:identity.principalId}" -o json | ConvertFrom-Json
        
        if ($avdVMs -and $avdVMs.Count -gt 0) {
            Write-TimestampedHost "Found $($avdVMs.Count) AVD VM(s) with managed identities" -ForegroundColor White
            
            foreach ($vm in $avdVMs) {
                if ($vm.principalId) {
                    if ($WhatIf) {
                        Write-TimestampedHost "  [WHAT-IF] Would add $($vm.name) (Principal ID: $($vm.principalId)) to AVD security group" -ForegroundColor Yellow
                        $successCount++
                    } else {
                        Write-TimestampedHost "  Adding $($vm.name) to AVD security group..." -ForegroundColor White
                        
                        # Check if already a member
                        $isMember = az ad group member check --group $appConfig.AVDHostGroupId --member-id $vm.principalId --query "value" -o tsv
                        
                        if ($isMember -eq "true") {
                            Write-TimestampedHost "    ✅ $($vm.name) is already a member" -ForegroundColor Green
                            $successCount++
                        } else {
                            az ad group member add --group $appConfig.AVDHostGroupId --member-id $vm.principalId --output none
                            if ($LASTEXITCODE -eq 0) {
                                Write-TimestampedHost "    ✅ Successfully added $($vm.name)" -ForegroundColor Green
                                $successCount++
                            } else {
                                Write-Warning "Failed to add $($vm.name) to AVD security group"
                                $errorCount++
                            }
                        }
                    }
                } else {
                    Write-Warning "$($vm.name) does not have a managed identity principal ID"
                    $errorCount++
                }
            }
        } else {
            Write-TimestampedHost "No AVD VMs with managed identities found in resource group" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to process AVD VMs: $($_.Exception.Message)"
        $errorCount++
    }
} else {
    if ([string]::IsNullOrEmpty($AVDResourceGroupName)) {
        Write-TimestampedHost "Skipping AVD VMs (no resource group specified)" -ForegroundColor Gray
    } else {
        Write-TimestampedHost "Skipping AVD VMs (no security group ID found)" -ForegroundColor Yellow
    }
}

# Process Linux VMs
if (-not [string]::IsNullOrEmpty($LinuxResourceGroupName) -and $appConfig.LinuxHostGroupId) {
    Write-TimestampedHost ""
    Write-TimestampedHost "Processing Linux VMs in resource group: $LinuxResourceGroupName" -ForegroundColor Cyan
    
    try {
        # Get all VMs with managed identities in the resource group
        $linuxVMs = az vm list --resource-group $LinuxResourceGroupName --query "[?identity.type=='SystemAssigned'].{name:name, principalId:identity.principalId}" -o json | ConvertFrom-Json
        
        if ($linuxVMs -and $linuxVMs.Count -gt 0) {
            Write-TimestampedHost "Found $($linuxVMs.Count) Linux VM(s) with managed identities" -ForegroundColor White
            
            foreach ($vm in $linuxVMs) {
                if ($vm.principalId) {
                    if ($WhatIf) {
                        Write-TimestampedHost "  [WHAT-IF] Would add $($vm.name) (Principal ID: $($vm.principalId)) to Linux security group" -ForegroundColor Yellow
                        $successCount++
                    } else {
                        Write-TimestampedHost "  Adding $($vm.name) to Linux security group..." -ForegroundColor White
                        
                        # Check if already a member
                        $isMember = az ad group member check --group $appConfig.LinuxHostGroupId --member-id $vm.principalId --query "value" -o tsv
                        
                        if ($isMember -eq "true") {
                            Write-TimestampedHost "    ✅ $($vm.name) is already a member" -ForegroundColor Green
                            $successCount++
                        } else {
                            az ad group member add --group $appConfig.LinuxHostGroupId --member-id $vm.principalId --output none
                            if ($LASTEXITCODE -eq 0) {
                                Write-TimestampedHost "    ✅ Successfully added $($vm.name)" -ForegroundColor Green
                                $successCount++
                            } else {
                                Write-Warning "Failed to add $($vm.name) to Linux security group"
                                $errorCount++
                            }
                        }
                    }
                } else {
                    Write-Warning "$($vm.name) does not have a managed identity principal ID"
                    $errorCount++
                }
            }
        } else {
            Write-TimestampedHost "No Linux VMs with managed identities found in resource group" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Failed to process Linux VMs: $($_.Exception.Message)"
        $errorCount++
    }
} else {
    if ([string]::IsNullOrEmpty($LinuxResourceGroupName)) {
        Write-TimestampedHost "Skipping Linux VMs (no resource group specified)" -ForegroundColor Gray
    } else {
        Write-TimestampedHost "Skipping Linux VMs (no security group ID found)" -ForegroundColor Yellow
    }
}

# Summary
Write-TimestampedHost ""
Write-TimestampedHost "📋 Summary:" -ForegroundColor Cyan
if ($WhatIf) {
    Write-TimestampedHost "   Would process: $successCount VMs" -ForegroundColor Green
    Write-TimestampedHost "   Potential errors: $errorCount" -ForegroundColor Red
    Write-TimestampedHost ""
    Write-TimestampedHost "💡 Run without -WhatIf to actually add VMs to security groups" -ForegroundColor Yellow
} else {
    Write-TimestampedHost "   Successfully processed: $successCount VMs" -ForegroundColor Green
    Write-TimestampedHost "   Errors: $errorCount" -ForegroundColor Red
    
    if ($errorCount -eq 0 -and $successCount -gt 0) {
        Write-TimestampedHost "✅ All VMs successfully added to security groups!" -ForegroundColor Green
    } elseif ($successCount -gt 0) {
        Write-TimestampedHost "⚠️  Some VMs added successfully, but there were errors" -ForegroundColor Yellow
    } else {
        Write-TimestampedHost "❌ No VMs were processed successfully" -ForegroundColor Red
    }
}

Write-TimestampedHost ""
Write-TimestampedHost "🔧 Usage Examples:" -ForegroundColor Cyan
Write-Host "   # Preview what would be done:" -ForegroundColor White
Write-Host "   .\Add-VMsToSecurityGroups.ps1 -SubscriptionId 'your-sub-id' -AVDResourceGroupName 'rg-avd' -LinuxResourceGroupName 'rg-linux' -WhatIf" -ForegroundColor Gray
Write-Host ""
Write-Host "   # Actually add VMs to groups:" -ForegroundColor White
Write-Host "   .\Add-VMsToSecurityGroups.ps1 -SubscriptionId 'your-sub-id' -AVDResourceGroupName 'rg-avd' -LinuxResourceGroupName 'rg-linux'" -ForegroundColor Gray