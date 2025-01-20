$siteName = "totam"

$installScriptUrl = "https://raw.githubusercontent.com/Totambiz/ttm-az-infra-scripts/refs/tags/0.2.0/virtual-machine/totam-app/install-app.ps1"
$installScriptPath = "C:\install-app.ps1"

$logDirectory = "C:\logs"
$logFile = "$logDirectory\configure-image-log.txt"

if (-not (Test-Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force
}

function Log-Message {
    param (
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"

    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

# Global error handler
$ErrorActionPreference = "Stop"

Trap {
    $errorMessage = $_.Exception.Message
    $errorStackTrace = $_.Exception.StackTrace
    Log-Message "Error: $errorMessage"
    Log-Message "Stack Trace: $errorStackTrace"
    exit 1
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Log-Message "This script must be run as Administrator!"
    exit 1
}

if (Test-Path -Path $installScriptPath) {
    Remove-Item -Path $installScriptPath -Force
    Log-Message "Existing install script file deleted: $installScriptPath"
}

Log-Message "Installing modules and features..."
Install-PackageProvider -Name NuGet -Force -Scope AllUsers

Install-Module -Name PowerShellGet -Force -Scope AllUsers
Install-Module -Name Az.Accounts -AllowClobber -Force -Scope AllUsers
Install-Module -Name Az.Storage -AllowClobber -Force -Scope AllUsers
Install-Module -Name Az.KeyVault -AllowClobber -Force -Scope AllUsers

Log-Message "Module and feature installation complete"

Import-Module PKI -ErrorAction SilentlyContinue
Import-Module WebAdministration -ErrorAction SilentlyContinue


Log-Message "Downloading install script and saving to $installScriptPath..."

Invoke-WebRequest -Uri $installScriptUrl -OutFile $installScriptPath

Log-Message "Install script downloaded and saved to $installScriptPath"


Log-Message "Installing IIS..."
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Tools -IncludeManagementTools

$feature = Get-WindowsFeature -Name Web-Server

if ($feature.Installed) {
    Log-Message "IIS was successfully installed."
}
else {
    Log-Message "IIS installation failed."
    exit 1
}

Log-Message "Starting IIS services..."
Start-Service -Name W3SVC

$dotNetRuntimeUrl = "https://go.microsoft.com/fwlink/?linkid=2203305"
$dotNetInstalleRuntimePath = "$env:TEMP\NDP481-x86-x64-AllOS-ENU.exe"

if (Test-Path $dotNetInstalleRuntimePath) {
    Remove-Item -Path $dotNetInstalleRuntimePath -Force
    Log-Message "Existing .NET Framework 4.8.1 Runtime installer deleted: $dotNetInstalleRuntimePath"
}

Log-Message "Downloading .NET Framework 4.8.1 Runtime installer..."
Invoke-WebRequest -Uri $dotNetRuntimeUrl -OutFile $dotNetInstalleRuntimePath -UseBasicParsing

Log-Message "Running .NET Framework 4.8.1 Runtime installer..."
Start-Process -FilePath $dotNetInstalleRuntimePath -ArgumentList "/quiet /norestart" -Wait


$dotNetDeveloperPackUrl = "https://go.microsoft.com/fwlink/?linkid=2203306"
$dotNetInstalleDeveloperPackPath = "$env:TEMP\NDP481-DevPack-ENU.exe"

if (Test-Path $dotNetInstalleDeveloperPackPath) {
    Remove-Item -Path $dotNetInstalleDeveloperPackPath -Force
    Log-Message "Existing .NET Framework 4.8.1 Developer Pack installer deleted: $dotNetInstalleDeveloperPackPath"
}

Log-Message "Downloading .NET Framework 4.8.1 Developer Pack installer..."
Invoke-WebRequest -Uri $dotNetDeveloperPackUrl -OutFile $dotNetInstalleDeveloperPackPath -UseBasicParsing

Log-Message "Running .NET Framework 4.8.1 Developer Pack installer..."
Start-Process -FilePath $dotNetInstalleDeveloperPackPath -ArgumentList "/quiet /norestart" -Wait


Log-Message "Installing URL Rewrite module..."
$urlRewriteUrl = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
$urlRewriteInstallerPath = "$env:TEMP\rewrite_amd64_en-US.msi"

if (Test-Path $urlRewriteInstallerPath) {
    Remove-Item -Path $urlRewriteInstallerPath -Force
    Log-Message "Existing URL Rewrite module installer deleted: $urlRewriteInstallerPath"
}

Log-Message "Downloading URL Rewrite module installer..."
Invoke-WebRequest -Uri $urlRewriteUrl -OutFile $urlRewriteInstallerPath -UseBasicParsing

Log-Message "Running URL Rewrite module installer..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $urlRewriteInstallerPath /quiet /norestart" -Wait


$websites = Get-Website

if ($websites) {
    Log-Message "Found the following websites:"
    $websites | ForEach-Object { Log-Message $_.Name }

    Log-Message "Removing all websites..."
    $websites | ForEach-Object { Remove-Website -Name $_.Name }

    Log-Message "All websites have been removed."
} else {
    Log-Message "No websites exist in IIS. Nothing to remove."
}

$appPools = Get-IISAppPool

if ($appPools) {
    Log-Message "Found the following application pools:"
    $appPools | ForEach-Object { Log-Message $_.Name }

    Log-Message "Removing all application pools..."
    $appPools | ForEach-Object { Remove-WebAppPool -Name $_.Name }

    Log-Message "All application pools have been removed."
} else {
    Log-Message "No application pools exist in IIS. Nothing to remove."
}

Log-Message "Creating IIS $siteName Website..."
$physicalPath = "C:\inetpub\wwwroot\$siteName"

if (-not (Test-Path $physicalPath)) {
    Log-Message "Creating website directory: $physicalPath"
    New-Item -Path $physicalPath -ItemType Directory -Force
}

Log-Message "Granting IIS_IUSRS full control of $physicalPath..."
$acl = Get-Acl $physicalPath
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl -Path $physicalPath -AclObject $acl

# Add the website to IIS
New-WebAppPool -Name $siteName -Force
New-Website -Name $siteName -PhysicalPath $physicalPath -ApplicationPool $siteName -Force

# Reset so the new app pool is availabe for configuration
Reset-IISServerManager -Confirm:$false
(Get-IISAppPool -Name $siteName).enable32BitAppOnWin64 = $false

Log-Message "$siteName Website configured successfully"


Log-Message "Authenticate with Azure using the VM's managed identity.."
Connect-AzAccount -Identity 
Log-Message "Authenticated"

Log-Message "Retrieving Datadog API key from key vault..."
$datadogApiKeySecret = Get-AzKeyVaultSecret -VaultName "ttm-core-eus-auto-main" -Name "datadog-api-key"
$datadogApiKey = $datadogApiKeySecret.SecretValueText

if (-not [string]::IsNullOrWhiteSpace($datadogApiKey)) {
    Log-Message "Retrieved Datadog API key from key vault"
} else {
    Log-Message "The Datadog API key secret value is empty or could not be retrieved."
}

Log-Message "Installing Datadog agent..."
$datadogAgentUrl = "https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi"
$datadogAgentInstallerPath = "$env:TEMP\datadog-agent-7-latest.amd64.msi"

if (Test-Path $datadogAgentInstallerPath) {
    Remove-Item -Path $datadogAgentInstallerPath -Force
    Log-Message "Existing Datadog agent installer deleted: $datadogAgentInstallerPath"
}

Log-Message "Downloading Datadog agent installer..."
Invoke-WebRequest -Uri $datadogAgentUrl -OutFile $datadogAgentInstallerPath -UseBasicParsing

Log-Message "Running Datadog agent installer..."
Start-Process -FilePath "msiexec.exe" -ArgumentList '/qn /i $datadogAgentInstallerPath APIKEY="${$datadogApiKey}" /quiet /norestart' -Wait

Log-Message "Datadog agent installed"