# Quick Deployment Guide

## 🚀 One-Click Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmicrosoft%2FLinuxBrokerForAVDAccess%2Fmain%2Fbicep%2Fmain.bicep)

## ⚡ Quick Start (5 minutes)

### Prerequisites

1. Azure subscription with Contributor access
2. PowerShell 7+ or Azure Cloud Shell

### Step 1: Clone and Prepare

```powershell
git clone https://github.com/microsoft/LinuxBrokerForAVDAccess.git
cd LinuxBrokerForAVDAccess
```

### Step 2: Check Prerequisites

```powershell
.\deploy\Check-Prerequisites.ps1
```

### Step 3: Core Infrastructure Only (Fastest)

Deploy just the API, Database, Frontend, and Function App:

```powershell
.\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId "your-sub-id" -ResourceGroupName "rg-linuxbroker" -Location "East US"
```

### Step 4: Full Deployment (Optional)

Deploy with AVD and Linux VMs:

```powershell
.\deploy\Deploy-LinuxBroker.ps1 `
  -SubscriptionId "your-sub-id" `
  -ResourceGroupName "rg-linuxbroker" `
  -Location "East US" `
  -DeployAVD $true `
  -DeployLinuxVMs $true
```

## 🔧 Alternative: Bicep Direct Deployment

### Core Infrastructure Only

```bash
az deployment group create \
  --resource-group rg-linuxbroker \
  --template-file ./bicep/infrastructure/main.bicep \
  --parameters @./bicep/infrastructure/main.bicepparam
```

### Full Deployment with Options

```bash
az deployment group create \
  --resource-group rg-linuxbroker \
  --template-file ./bicep/main.bicep \
  --parameters @./bicep/main.bicepparam
```

## 🔧 Manual Deployment Steps

If you prefer manual deployment or need to customize:

### 1. Create Azure Resources
- Resource Group
- Azure SQL Database
- App Service Plans (2x)
- Web Apps (API + Frontend)
- Function App
- Key Vault
- Managed Identities

### 2. Configure Security
- Create Security Groups in Azure AD:
  - `LinuxBroker-AVDHost-VMs`
  - `LinuxBroker-LinuxHost-VMs`
- Assign App Roles to Managed Identities
- Configure Key Vault access policies

### 3. Deploy Database Schema
Run SQL scripts in order:
```sql
001_create_table-vm_scaling_rules.sql
002_create_table-vm_scaling_activity_log.sql
003_create_table-virtual_machines.sql
...all stored procedure scripts...
```

### 4. Deploy Applications
- Deploy API to App Service
- Deploy Frontend to App Service  
- Deploy Function App

### 5. Configure AVD Hosts
- Run `Configure-AVD-Host.ps1` on each AVD host
- Update script with correct API URL

### 6. Configure Linux Hosts
- Run appropriate configuration script:
  - RHEL 7: `Configure-RHEL7-Host.sh`
  - RHEL 8: `Configure-RHEL8-Host.sh`
  - RHEL 9: `Configure-RHEL9-Host.sh`
  - Ubuntu 24: `Configure-Ubuntu24_desktop-Host.sh`

## 🔍 Verification Steps

After deployment:

1. **Check API Health**
   ```bash
   curl https://your-api-app.azurewebsites.net/api/health
   ```

2. **Access Management Portal**
   - Navigate to: `https://your-frontend-app.azurewebsites.net`
   - Login with Azure AD
   - Add your first Linux VM

3. **Test VM Checkout**
   - From AVD host, run: `Connect-LinuxBroker.ps1`
   - Should receive Linux VM assignment

## 🛠️ Configuration Files Generated

The deployment creates these configuration files:
- `./api/config.py` - API configuration
- `./front_end/config.py` - Frontend configuration
- `./environment.template` - Environment variables template

## 🔧 Customization Options

### Scaling Rules
Configure in the management portal:
- Minimum VMs: 2
- Maximum VMs: 20
- Scale-up ratio: 80%
- Scale-down ratio: 30%

### VM Sizing
Recommended AVD host sizes:
- Light workload: D8s_v5 (8 vCPU, 32 GB RAM)
- Medium workload: D16s_v5 (16 vCPU, 64 GB RAM)

### Linux Distributions
Supported out of the box:
- RHEL 7, 8, 9
- Ubuntu 24.04 Desktop

## 🆘 Troubleshooting

### Common Issues
1. **Permission Denied**: Ensure managed identities are in correct security groups
2. **SQL Connection Failed**: Check firewall rules and connection strings
3. **VM Checkout Failed**: Verify API URL in AVD host script

### Log Locations
- API logs: Azure App Service logs
- Function logs: Application Insights
- VM logs: Event Viewer (Windows) / syslog (Linux)

## 📚 Additional Resources

- [Detailed Architecture Guide](../README.md)
- [Database Setup Guide](../sql_queries/README.md)
- [RBAC Configuration Guide](../docs/rbac-setup.md)
- [Troubleshooting Guide](../docs/troubleshooting.md)