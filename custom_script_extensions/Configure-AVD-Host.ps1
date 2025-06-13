# Installs and configures the necessary packages for Linux Broker for AVD Access on the AVD host

$sourceName = "LinuxBrokerScript"
$logName = "Application"
$moduleName = "SqlServer"

# URL of the script to download
$url = "https://raw.githubusercontent.com/microsoft/LinuxBrokerForAVDAccess/refs/heads/main/avd_host/broker/Connect-LinuxBroker.ps1"

# Define the Linux Broker API Base URL
$linuxBrokerApiBaseUrl = "https://your_linuxbroker_api_fqdn_here/api"

# Check if the folder exists, if not, create it
$folderPath = "C:\Temp"

# Output path for the downloaded script
$outputPath = "$folderPath\Connect-LinuxBroker.ps1"

if (-Not (Test-Path -Path $folderPath)) {
    try {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
        Write-Host "Folder $folderPath created successfully."
    } catch {
        Write-Host "Failed to create folder $folderPath. Error: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Folder $folderPath already exists."
}

# Check if the CredentialManager module is installed, if not, install it
try {
    if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
        Write-Host "CredentialManager module is not installed. Attempting to install..."
        Install-Module -Name CredentialManager -Force
    } else {
        Write-Host "CredentialManager module is already installed."
    }

} catch {
    Write-Host "Failed to install or import CredentialManager module. Error: $_" -ForegroundColor Red
    exit 1
}

# Check if the CredentialManager module is already imported, if not, import it
try {
    if (-not (Get-Module -Name CredentialManager)) {
        Write-Host "Importing CredentialManager module..."
        Import-Module CredentialManager -Force
    } else {
        Write-Host "CredentialManager module is already imported."
    }
} catch {
    Write-Host "Failed to import CredentialManager module. Error: $_" -ForegroundColor Red
    exit 1
}

# Download the script using Invoke-WebRequest
try {
    Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    Write-Host "Script downloaded successfully to $outputPath"

    # Unblock the downloaded file to clear the "Mark of the Web"
    Unblock-File -Path $outputPath
    Write-Host "The downloaded script has been unblocked successfully."

} catch {
    Write-Host "Failed to download the script. Error: $_" -ForegroundColor Red
}

# Modify the API base URL in the script
try {
    (Get-Content $outputPath) -replace 'https://your_linuxbroker_api_base_url/api', $linuxBrokerApiBaseUrl | Set-Content $outputPath
    Write-Host "Updated API Base URL in $outputPath"
} catch {
    Write-Host "Failed to update API Base URL. Error: $_" -ForegroundColor Red
    exit 1
}


if (-not [System.Diagnostics.EventLog]::SourceExists($sourceName)) {
    try {
        Write-Host "Event source '$sourceName' does not exist. Creating..."
        New-EventLog -LogName $logName -Source $sourceName
        Write-Host "Event source '$sourceName' created successfully."
    }
    catch {
        Write-Error "Failed to create event source '$sourceName': $_"
    }
}
else {
    Write-Host "Event source '$sourceName' already exists."
}

try {
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindowsx64 -OutFile .\AzureCLI.msi
}
catch {
    Write-Error "Failed to download the Azure CLI installer: $_"
}

try {
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
}
catch {
    Write-Error "Failed to install the Azure CLI: $_"
}

try {
    Remove-Item .\AzureCLI.msi
}
catch {
    Write-Error "Failed to remove the Azure CLI installer: $_"
}

try {
    az extension add --name ssh
}
catch {
    Write-Error "Failed to install the SSH extension: $_"
}

# Check if the SqlServer module is installed
if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    Write-Log "SqlServer module is not installed. Attempting to install..."
    
    try {
        $moduleOutput = Import-Module PowerShellGet
        Write-Log "PowerShellGet module has been loaded. $moduleOutput"
        Install-Module -Name $moduleName -Scope CurrentUser -AllowClobber -Force

        Import-Module $moduleName

        Write-Log "SqlServer module has been successfully installed."
    }
    catch {
        Write-Error "Failed to install the SqlServer module: $_"
    }
}
else {
    Write-Log "SqlServer module is already installed."
}

try {
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Terminal Server Client" /v "AuthenticationLevelOverride" /t "REG_DWORD" /d 0 /f | Out-Null
}
catch {
    Write-Error "Failed to set the AuthenticationLevelOverride registry key: $_"
}