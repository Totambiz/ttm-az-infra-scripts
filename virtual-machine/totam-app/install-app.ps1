$siteName = "totam"
$dnsBase = "totam.biz"

$storageAccountName = "ttmcoreeusautomainsa"
$containerName = "totam-app-dev"
$blobName = "totam-app.zip"
$destinationPath = "C:\inetpub\wwwroot\$siteName"
$downloadPath = "C:\inetpub\wwwroot\$siteName.zip"

$blobUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

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

Log-Message "Downloading application zip and saving to $downloadPath..."
Invoke-WebRequest -Uri $blobUrl -OutFile $downloadPath
Log-Message "Application zip downloaded and saved to $downloadPath"

Log-Message "Deleting all existing files in $destinationPath..."
Get-ChildItem -Path $destinationPath -Recurse -Force | Remove-Item -Recurse -Force
Log-Message "All content in $destinationPath has been deleted."

Log-Message "Extracting all application files to $destinationPath..."
Expand-Archive -Path $downloadPath -DestinationPath $destinationPath -Force
Log-Message "Application files extracted to $destinationPath."

Remove-Item -Path $downloadPath -Force
Log-Message "Application zip file deleted from $downloadPath."

$httpBindings = Get-WebBinding -Name $siteName -Protocol http -ErrorAction SilentlyContinue

if ($httpBindings) {
    foreach ($binding in $httpBindings) {
        Log-Message "Removing HTTP binding for site: $siteName with Binding Information: $($binding.BindingInformation)"
        Remove-WebBinding -Name $siteName -Protocol http -BindingInformation $binding.BindingInformation -ErrorAction SilentlyContinue
    }

    Log-Message "All HTTP bindings for site '$siteName' have been removed."
}
else {
    Log-Message "No HTTP bindings found for site '$siteName'."
}

Log-Message "Installing SSL certificates and bindings to the website..." 

$certStorePath = "Cert:\LocalMachine\My"
$certSubjectNamePattern = "*.${dnsBase}"
$httpBindingsCreated = $false

Get-ChildItem -Path $certStorePath | ForEach-Object {
    $certThumbprint = $_.Thumbprint
    $allDnsNames = @()

    # Extract and process all CNs from the Subject field
    $subjectItems = ($_.Subject -split "CN=") | ForEach-Object { $_ -split "," }

    foreach ($subjectItem in $subjectItems) {
        $subjectCN = $subjectItem.Trim()

        if ($subjectCN -like $certSubjectNamePattern) {
            $allDnsNames += $subjectCN 
            Log-Message "Subject CN matches: $subjectCN"
        }
    }

    # Check if the certificate has SANs and match them
    if ($_.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }) {
        $sanExtension = $_.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }
        $sanText = [System.Text.Encoding]::UTF8.GetString($sanExtension.RawData)

        # Extract DNS names from the SAN
        $dnsNames = $sanText -split "\s+" | Where-Object { $_ -like $certSubjectNamePattern }

        if ($dnsNames) {
            $allDnsNames += $dnsNames 
            Log-Message "Matching SAN DNS Names: $($dnsNames -join ', ')"
        }
    }

    foreach ($dnsName in $allDnsNames) {
        $httpBindingsCreated = $true
        Log-Message "Adding HTTPS web binding. DNS: $dnsName; Thumbprint: $certThumbprint"
    
        New-WebBinding -Name $siteName -HostHeader $dnsName -IPAddress "*" -Port 443 -Protocol "https"
    
        (Get-WebBinding -Name $siteName -HostHeader $dnsName -IPAddress "*" -Port 443 -Protocol "https").AddSslCertificate($certThumbprint, "my")
    }
}

if (-not $httpBindingsCreated) {
    Log-Message "No HTTPS web bindings were created because no certificates with a CN or DNS name ending in '$dnsBase' were found in the store: $certStorePath"
    Log-Message "$siteName Website NOT configured successfully"
    exit 1
}

Log-Message "Restarting $siteName Website..."

Restart-WebAppPool -Name $siteName
Stop-WebSite -Name $siteName
Start-WebSite -Name $siteName 

Log-Message "Restarted $siteName Website"
Log-Message "$siteName installed"