# Test-PostDeployment.ps1
# Post-deployment validation for Linux Broker for AVD Access
# Checks that deployed resources are healthy and responding.
# Usage: .\deploy\Test-PostDeployment.ps1 -ApiBaseUrl <url> [-ResourceGroupName <rg>] [-SubscriptionId <sub>]

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiBaseUrl,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",

    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "",

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Continue"

# --- Results tracking ---
$results = [System.Collections.ArrayList]::new()

function Add-Result {
    param(
        [string]$Category,
        [string]$Check,
        [string]$Status,
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
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host " POST-DEPLOYMENT VALIDATION REPORT" -ForegroundColor Cyan
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("{0,-18} {1,-32} {2,-6} {3}" -f "CATEGORY", "CHECK", "STATUS", "DETAIL") -ForegroundColor White
    Write-Host ("{0,-18} {1,-32} {2,-6} {3}" -f ("─" * 18), ("─" * 32), ("─" * 6), ("─" * 40)) -ForegroundColor DarkGray

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
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host " SUMMARY: $passCount passed, $failCount failed, $warnCount warnings out of $total checks" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
    Write-Host ("=" * 100) -ForegroundColor Cyan

    if ($failCount -gt 0) {
        Write-Host "`n❌ POST-DEPLOYMENT VALIDATION FAILED — see details above." -ForegroundColor Red
        Write-Host "   Troubleshoot using Azure Portal > Resource Group > Activity Log" -ForegroundColor Yellow
    } else {
        Write-Host "`n✅ ALL POST-DEPLOYMENT CHECKS PASSED — deployment is healthy!" -ForegroundColor Green
    }
}

# Normalize base URL
$ApiBaseUrl = $ApiBaseUrl.TrimEnd('/')

# ============================================================
# 1. API ENDPOINT HEALTH
# ============================================================

# Version endpoint (unauthenticated)
try {
    $versionResponse = Invoke-WebRequest -Uri "$ApiBaseUrl/api/version" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
    if ($versionResponse.StatusCode -eq 200) {
        $versionBody = $versionResponse.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        $verStr = if ($versionBody -and $versionBody.version) { "v$($versionBody.version)" } else { "responded OK" }
        Add-Result "API" "Version endpoint" "PASS" "$verStr (HTTP 200)"
    } else {
        Add-Result "API" "Version endpoint" "WARN" "HTTP $($versionResponse.StatusCode)"
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "401|403") {
        Add-Result "API" "Version endpoint" "WARN" "Auth required — endpoint reachable but returned 401/403"
    } else {
        Add-Result "API" "Version endpoint" "FAIL" "Unreachable: $errMsg. Check App Service is running."
    }
}

# VMs endpoint (may require auth)
try {
    $vmsResponse = Invoke-WebRequest -Uri "$ApiBaseUrl/api/vms" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
    if ($vmsResponse.StatusCode -eq 200) {
        Add-Result "API" "VMs endpoint" "PASS" "HTTP 200"
    } else {
        Add-Result "API" "VMs endpoint" "WARN" "HTTP $($vmsResponse.StatusCode)"
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "401|403") {
        Add-Result "API" "VMs endpoint" "PASS" "Auth enforced (401/403) — endpoint reachable"
    } else {
        Add-Result "API" "VMs endpoint" "FAIL" "Unreachable: $errMsg"
    }
}

# Scaling rules endpoint (may require auth)
try {
    $scalingResponse = Invoke-WebRequest -Uri "$ApiBaseUrl/api/scaling/rules" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
    if ($scalingResponse.StatusCode -eq 200) {
        Add-Result "API" "Scaling rules endpoint" "PASS" "HTTP 200"
    } else {
        Add-Result "API" "Scaling rules endpoint" "WARN" "HTTP $($scalingResponse.StatusCode)"
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "401|403") {
        Add-Result "API" "Scaling rules endpoint" "PASS" "Auth enforced (401/403) — endpoint reachable"
    } else {
        Add-Result "API" "Scaling rules endpoint" "FAIL" "Unreachable: $errMsg"
    }
}

# ============================================================
# 2. DATABASE CONNECTIVITY (via API)
# ============================================================

# If the VMs endpoint returned data, the DB is working.
# We also try an endpoint that exercises the DB more directly.
try {
    $dbTestResponse = Invoke-WebRequest -Uri "$ApiBaseUrl/api/scaling/rules" -Method GET -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
    if ($dbTestResponse.StatusCode -eq 200) {
        Add-Result "Database" "DB connectivity (via API)" "PASS" "API can query database"
    } else {
        Add-Result "Database" "DB connectivity (via API)" "WARN" "HTTP $($dbTestResponse.StatusCode) — may indicate DB issue"
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "401|403") {
        Add-Result "Database" "DB connectivity (via API)" "WARN" "Cannot verify — auth required on endpoint"
    } elseif ($errMsg -match "500") {
        Add-Result "Database" "DB connectivity (via API)" "FAIL" "HTTP 500 — likely database connection issue. Check DB_SERVER, DB_DATABASE, and Key Vault password."
    } else {
        Add-Result "Database" "DB connectivity (via API)" "FAIL" "Cannot reach API: $errMsg"
    }
}

# ============================================================
# 3. AZURE RESOURCE CHECKS (require az CLI + resource group)
# ============================================================
if ($ResourceGroupName) {
    # Set subscription if provided
    if ($SubscriptionId) {
        az account set --subscription $SubscriptionId 2>$null
    }

    # Key Vault
    try {
        $vaults = az keyvault list --resource-group $ResourceGroupName --query "[].name" --output tsv 2>$null
        if ($vaults) {
            $vaultNames = $vaults -split "`n" | Where-Object { $_ -ne "" }
            Add-Result "Key Vault" "Exists in RG" "PASS" "Found: $($vaultNames -join ', ')"

            # Check if we can list secrets (tests access policy)
            foreach ($vault in $vaultNames) {
                try {
                    $null = az keyvault secret list --vault-name $vault --query "[].name" --output tsv 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Add-Result "Key Vault" "Access ($vault)" "PASS" "Can list secrets"
                    } else {
                        Add-Result "Key Vault" "Access ($vault)" "WARN" "Cannot list secrets — check access policies"
                    }
                } catch {
                    Add-Result "Key Vault" "Access ($vault)" "WARN" "Cannot verify secret access"
                }
            }
        } else {
            Add-Result "Key Vault" "Exists in RG" "FAIL" "No Key Vault found in $ResourceGroupName. Deploy infrastructure first."
        }
    } catch {
        Add-Result "Key Vault" "Exists in RG" "FAIL" "Could not query: $($_.Exception.Message)"
    }

    # AVD Host Pool
    try {
        $hostPools = az desktopvirtualization hostpool list --resource-group $ResourceGroupName --query "[].name" --output tsv 2>$null
        if ($hostPools) {
            $poolNames = $hostPools -split "`n" | Where-Object { $_ -ne "" }
            Add-Result "AVD" "Host pool exists" "PASS" "Found: $($poolNames -join ', ')"

            # Check session hosts in each pool
            foreach ($pool in $poolNames) {
                try {
                    $sessionHosts = az desktopvirtualization sessionhost list --resource-group $ResourceGroupName --host-pool-name $pool --query "[].name" --output tsv 2>$null
                    if ($sessionHosts) {
                        $hostCount = ($sessionHosts -split "`n" | Where-Object { $_ -ne "" }).Count
                        Add-Result "AVD" "Session hosts ($pool)" "PASS" "$hostCount session host(s) registered"
                    } else {
                        Add-Result "AVD" "Session hosts ($pool)" "WARN" "No session hosts found — VMs may not be joined yet"
                    }
                } catch {
                    Add-Result "AVD" "Session hosts ($pool)" "WARN" "Could not list session hosts"
                }
            }
        } else {
            Add-Result "AVD" "Host pool exists" "FAIL" "No host pool in $ResourceGroupName. Deploy AVD infrastructure."
        }
    } catch {
        Add-Result "AVD" "Host pool exists" "FAIL" "Could not query: $($_.Exception.Message). Ensure Microsoft.DesktopVirtualization provider is registered."
    }

    # Linux VMs
    try {
        $vms = az vm list --resource-group $ResourceGroupName --query "[?storageProfile.osDisk.osType=='Linux'].{name:name, state:powerState}" --output json 2>$null | ConvertFrom-Json
        if ($vms -and $vms.Count -gt 0) {
            Add-Result "Linux VMs" "Registered in RG" "PASS" "$($vms.Count) Linux VM(s) found"

            $runningCount = ($vms | Where-Object { $_.state -match "running" }).Count
            if ($runningCount -gt 0) {
                Add-Result "Linux VMs" "Running VMs" "PASS" "$runningCount VM(s) running"
            } else {
                Add-Result "Linux VMs" "Running VMs" "WARN" "No VMs currently running — check power state"
            }
        } else {
            Add-Result "Linux VMs" "Registered in RG" "WARN" "No Linux VMs found in $ResourceGroupName"
        }
    } catch {
        Add-Result "Linux VMs" "Registered in RG" "WARN" "Could not query VMs: $($_.Exception.Message)"
    }

    # SQL Server
    try {
        $sqlServers = az sql server list --resource-group $ResourceGroupName --query "[].name" --output tsv 2>$null
        if ($sqlServers) {
            $serverNames = $sqlServers -split "`n" | Where-Object { $_ -ne "" }
            Add-Result "SQL" "Server exists" "PASS" "Found: $($serverNames -join ', ')"

            # Check databases on each server
            foreach ($server in $serverNames) {
                try {
                    $dbs = az sql db list --resource-group $ResourceGroupName --server $server --query "[?name!='master'].name" --output tsv 2>$null
                    if ($dbs) {
                        $dbNames = $dbs -split "`n" | Where-Object { $_ -ne "" }
                        Add-Result "SQL" "Databases ($server)" "PASS" "Found: $($dbNames -join ', ')"
                    } else {
                        Add-Result "SQL" "Databases ($server)" "FAIL" "No user databases — deploy schema with sql_queries/"
                    }
                } catch {
                    Add-Result "SQL" "Databases ($server)" "WARN" "Could not list databases"
                }
            }
        } else {
            Add-Result "SQL" "Server exists" "FAIL" "No SQL Server in $ResourceGroupName"
        }
    } catch {
        Add-Result "SQL" "Server exists" "FAIL" "Could not query: $($_.Exception.Message)"
    }

    # App Service (API)
    try {
        $webApps = az webapp list --resource-group $ResourceGroupName --query "[].{name:name, state:state}" --output json 2>$null | ConvertFrom-Json
        if ($webApps -and $webApps.Count -gt 0) {
            foreach ($app in $webApps) {
                $status = if ($app.state -eq "Running") { "PASS" } else { "WARN" }
                Add-Result "App Service" $app.name $status "State: $($app.state)"
            }
        } else {
            Add-Result "App Service" "Web apps" "FAIL" "No App Service found in $ResourceGroupName"
        }
    } catch {
        Add-Result "App Service" "Web apps" "FAIL" "Could not query: $($_.Exception.Message)"
    }

} else {
    Add-Result "Azure Resources" "Resource group checks" "WARN" "Skipped — provide -ResourceGroupName to check Azure resources"
}

# ============================================================
# OUTPUT
# ============================================================

Write-ResultTable

Write-Host "`n📋 NEXT STEPS:" -ForegroundColor Cyan
$failCount = ($results | Where-Object Status -eq "FAIL").Count
if ($failCount -gt 0) {
    Write-Host "   1. Review failures above and check Azure Portal for resource status" -ForegroundColor White
    Write-Host "   2. Check App Service logs: az webapp log tail --name <app-name> --resource-group $ResourceGroupName" -ForegroundColor White
    Write-Host "   3. Re-run this script after fixing issues" -ForegroundColor White
} else {
    Write-Host "   1. Test the front-end portal in a browser" -ForegroundColor White
    Write-Host "   2. Try a VM checkout flow end-to-end" -ForegroundColor White
    Write-Host "   3. Verify scaling rules are configured via the admin portal" -ForegroundColor White
}

exit $(if ($failCount -gt 0) { 1 } else { 0 })
