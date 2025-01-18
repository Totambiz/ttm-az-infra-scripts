param (
    [string]$StorageAccountName,
    [string]$ContainerName,
    [string]$Blob
)

Import-Module Az.Accounts
Import-Module Az.Storage

# Authenticate using the managed identity
Connect-AzAccount -Identity 

$siteName = "totam"
$destinationPath = "C:\inetpub\wwwroot\$siteName"
$downloadPath = "C:\temp\$siteName.zip"

$logDirectory = "C:\logs"
$logFile = "$logDirectory\install-app-log.txt"

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

if (-not $StorageAccountName) {
    Log-Message "StorageAccountName param is required."
    exit 1
}

Log-Message "StorageAccountName param provided: $StorageAccountName"

if (-not $ContainerName) {
    Log-Message "ContainerName param is required."
    exit 1
}

Log-Message "ContainerName param provided: $ContainerName"

if (-not $Blob) {
    Log-Message "Blob param is required."
    exit 1
}

Log-Message "Blob param provided: $Blob"


if (-Not (Test-Path -Path $destinationPath)) {
    Log-Message "The application folder doesn't exist at $destinationPath. This image is not configured correctly"
    exit 1
}

if (Test-Path -Path $downloadPath) {
    Remove-Item -Path $downloadPath -Force
    Log-Message "Previous application zip file deleted from $downloadPath."
}
else {
    Log-Message "No previous application zip file found at $downloadPath."
}

Log-Message "Downloading application zip from $SourceCodeUrl and saving it to $downloadPath..."

$storageCtx = New-AzStorageContext -StorageAccountName $StorageAccountName

Get-AzStorageBlobContent -Container $ContainerName -Blob $Blob -Destination $downloadPath -Context $storageCtx -Force

Log-Message "Application zip downloaded and saved to $downloadPath"

Log-Message "Deleting all existing files in $destinationPath..."
Get-ChildItem -Path $destinationPath -Recurse -Force | Remove-Item -Recurse -Force
Log-Message "All content in $destinationPath has been deleted."

Log-Message "Extracting all application files to $destinationPath..."
Expand-Archive -Path $downloadPath -DestinationPath $destinationPath -Force
Log-Message "Application files extracted to $destinationPath."

Remove-Item -Path $downloadPath -Force
Log-Message "Application zip file deleted from $downloadPath."

Log-Message "Restarting $siteName Website..."

Restart-WebAppPool -Name $siteName
Stop-WebSite -Name $siteName
Start-WebSite -Name $siteName 

Log-Message "Restarted $siteName Website"
Log-Message "$siteName installed"