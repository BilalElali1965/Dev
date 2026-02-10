<#
.SYNOPSIS
    Exports comprehensive Exchange Online mailbox data to CSV
.DESCRIPTION
    This script connects to Exchange Online and Microsoft Graph to export detailed mailbox 
    information including statistics, message tracking, calendar data, quotas, and licenses.
.PARAMETER OutputPath
    The path where the CSV file will be saved. Default: .\mailbox_export.csv
.PARAMETER SkipLicenses
    Skip retrieving license information (faster but incomplete data)
.PARAMETER SkipMessageTracking
    Skip message tracking (send/receive counts) - significantly faster
.PARAMETER Days
    Number of days to look back for message tracking data. Default: 10 (max for Get-MessageTraceV2)
#>

param(
    [string]$OutputPath = ".\mailbox_export.csv",
    [switch]$SkipLicenses,
    [switch]$SkipMessageTracking,
    [int]$Days = 10
)

# Function to convert ByteQuantifiedSize to bytes
function ConvertTo-Bytes {
    param($Size)
    
    if ($null -eq $Size -or $Size -eq "" -or $Size -eq "Unlimited") {
        return "Unlimited"
    }
    
    # Handle the size string format
    $sizeString = $Size.ToString()
    
    # Extract numeric value and unit
    if ($sizeString -match '([\d,\.]+)\s*([KMGT]?B)') {
        $value = [double]($matches[1] -replace ',', '');
        $unit = $matches[2];
        
        switch ($unit) {
            'KB' { return [math]::Round($value * 1KB) }
            'MB' { return [math]::Round($value * 1MB) }
            'GB' { return [math]::Round($value * 1GB) }
            'TB' { return [math]::Round($value * 1TB) }
            'B'  { return [math]::Round($value) }
            default { return $value }
        }
    }
    
    # Try to extract bytes from format like "1.5 GB (1,610,612,736 bytes)"
    if ($sizeString -match '\(([\d,]+)\s*bytes\)') {
        return [long]($matches[1] -replace ',', '')
    }
    
    return 0
}

# Function to get calendar statistics
function Get-CalendarStats {
    param($MailboxIdentity)
    
    try {
        $calendarFolder = Get-MailboxFolderStatistics -Identity $MailboxIdentity -FolderScope Calendar -ErrorAction SilentlyContinue | 
            Where-Object {$_.FolderType -eq "Calendar"} | 
            Select-Object -First 1
        
        if ($calendarFolder) {
            return $calendarFolder.ItemsInFolder
        }
    }
    catch {
        # Silently continue
    }
    
    return 0
}

# Function to get account status
function Get-AccountStatus {
    param($UserPrincipalName)
    
    if (-not $UserPrincipalName) {
        return "Unknown"
    }
    
    try {
        $user = Get-MgUser -UserId $UserPrincipalName -Property AccountEnabled -ErrorAction SilentlyContinue
        if ($user -and $null -ne $user.AccountEnabled) {
            return $user.AccountEnabled
        }
    }
    catch {
        # Silently continue
    }
    
    return "Unknown"
}

# Import Exchange Online Management module
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Host "Exchange Online Management module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Error: Exchange Online Management module not found. Please install it first:" -ForegroundColor Red
    Write-Host "Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Import Microsoft Graph module
try {
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Host "Microsoft Graph Users module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Error: Microsoft Graph Users module not found. Please install it first:" -ForegroundColor Red
    Write-Host "Install-Module -Name Microsoft.Graph.Users -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Connect to Exchange Online
try {
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "Connected to Exchange Online successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Error connecting to Exchange Online: $_" -ForegroundColor Red
    exit
}

# Connect to Microsoft Graph
$graphConnected = $false
try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Write-Host "Please complete the authentication in your browser..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "User.Read.All" -NoWelcome -ErrorAction Stop
    Write-Host "Connected to Microsoft Graph successfully!" -ForegroundColor Green
    $graphConnected = $true
}
catch {
    Write-Host "Warning: Could not connect to Microsoft Graph. License and account status information will be limited." -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Yellow
    $graphConnected = $false
}

# Get all mailboxes
Write-Host "`nRetrieving mailboxes..." -ForegroundColor Cyan
$mailboxes = Get-Mailbox -ResultSize Unlimited

# Get message tracking data if not skipped
$messageTrackingData = @{}
if (-not $SkipMessageTracking) {
    # Limit days to 10 for Get-MessageTraceV2
    if ($Days -gt 10) {
        Write-Host "Warning: Get-MessageTraceV2 supports max 10 days. Adjusting from $Days to 10 days." -ForegroundColor Yellow
        $Days = 10
    }
    
    Write-Host "Retrieving message tracking logs (this may take a while for large organizations)..." -ForegroundColor Cyan
    Write-Host "Looking back $Days days..." -ForegroundColor Cyan
    
    $startDate = (Get-Date).AddDays(-$Days)
    $endDate = Get-Date
    
    try {
        # Get all messages - Get-MessageTraceV2 returns all results automatically
        Write-Host "  Fetching message trace data..." -ForegroundColor Gray
        $allMessages = @(Get-MessageTraceV2 -StartDate $startDate -EndDate $endDate)
        
        Write-Host "Retrieved $($allMessages.Count) message trace records" -ForegroundColor Green
        
        if ($allMessages.Count -gt 0) {
            Write-Host "Processing message tracking data..." -ForegroundColor Cyan
            
            foreach ($msg in $allMessages) {
                # Count sent messages
                if ($msg.SenderAddress) {
                    $sender = $msg.SenderAddress.ToLower()
                    if (-not $messageTrackingData.ContainsKey($sender)) {
                        $messageTrackingData[$sender] = @{
                            SendCount = 0
                            ReceiveCount = 0
                        }
                    }
                    $messageTrackingData[$sender].SendCount++
                }
                
                # Count received messages
                if ($msg.RecipientAddress) {
                    $recipients = if ($msg.RecipientAddress -is [array]) { $msg.RecipientAddress } else { @($msg.RecipientAddress) }
                    foreach ($recipient in $recipients) {
                        $recipientLower = $recipient.ToLower()
                        if (-not $messageTrackingData.ContainsKey($recipientLower)) {
                            $messageTrackingData[$recipientLower] = @{
                                SendCount = 0
                                ReceiveCount = 0
                            }
                        }
                        $messageTrackingData[$recipientLower].ReceiveCount++
                    }
                }
            }
            Write-Host "Message tracking data processed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "No message trace records found for the specified time period" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Warning: Could not retrieve message tracking logs. Send/Receive counts will be 0." -ForegroundColor Yellow
        Write-Host "Error: $_" -ForegroundColor Yellow
    }
}

# Initialize results array
$results = @()

$counter = 0
$total = $mailboxes.Count
Write-Host "`nProcessing $total mailboxes..." -ForegroundColor Cyan

foreach ($mailbox in $mailboxes) {
    $counter++
    Write-Progress -Activity "Processing Mailboxes" -Status "Processing $($mailbox.DisplayName) ($counter of $total)" -PercentComplete (($counter / $total) * 100)
    
    try {
        # Get mailbox statistics
        $stats = Get-MailboxStatistics -Identity $mailbox.Identity -ErrorAction SilentlyContinue
        
        # Get mailbox details
        $mbxDetails = Get-Mailbox -Identity $mailbox.Identity
        
        # Get user information
        $user = Get-User -Identity $mailbox.Identity -ErrorAction SilentlyContinue
        
        # Get account status from Microsoft Graph
        $accountStatus = "Unknown"
        if ($graphConnected -and $mbxDetails.UserPrincipalName) {
            $accountStatus = Get-AccountStatus -UserPrincipalName $mbxDetails.UserPrincipalName
        }
        
        # Get license information from Graph API
        $assignedProducts = ""
        if ($graphConnected -and $mbxDetails.UserPrincipalName) {
            try {
                $licenses = Get-MgUserLicenseDetail -UserId $mbxDetails.UserPrincipalName -ErrorAction SilentlyContinue
                if ($licenses) {
                    $assignedProducts = ($licenses.SkuPartNumber) -join "; "
                }
            }
            catch {
                # Silently continue if license retrieval fails for this user
            }
        }
        
        # Get message tracking counts
        $sendCount = 0
        $receiveCount = 0
        if (-not $SkipMessageTracking) {
            $emailKey = $mbxDetails.PrimarySmtpAddress.ToLower()
            if ($messageTrackingData.ContainsKey($emailKey)) {
                $sendCount = $messageTrackingData[$emailKey].SendCount
                $receiveCount = $messageTrackingData[$emailKey].ReceiveCount
            }
        }
        
        # Get calendar statistics
        $calendarItemCount = Get-CalendarStats -MailboxIdentity $mailbox.Identity
        
        # Get forwarding information
        $forwardingEnabled = $false
        $forwardingAddress = ""
        if ($mbxDetails.ForwardingAddress -or $mbxDetails.ForwardingSmtpAddress) {
            $forwardingEnabled = $true
            $forwardingAddress = if ($mbxDetails.ForwardingSmtpAddress) { $mbxDetails.ForwardingSmtpAddress } else { $mbxDetails.ForwardingAddress }
        }
        
        # Get email aliases
        $aliases = ($mbxDetails.EmailAddresses | Where-Object { $_ -like "smtp:*" -and $_ -notlike "* $($mbxDetails.PrimarySmtpAddress)*" }) -join "; "
        
        # Get x500 address
        $x500 = ($mbxDetails.EmailAddresses | Where-Object { $_ -like "X500:*" }) -join "; "
        
        # Determine mailbox type
        $mailboxType = $mbxDetails.RecipientTypeDetails
        
        # Create custom object with all properties in the specified order
        $obj = [PSCustomObject]@{
            'Source Employment Status' = $accountStatus
            'Mailbox Type' = $mailboxType
            'Source Display Name' = $mbxDetails.DisplayName
            'Source Email Address' = $mbxDetails.PrimarySmtpAddress
            'Email Last Activity Date' = $stats.LastLogonTime
            'Assigned Products' = $assignedProducts
            'Workday ID' = ""
            'Destination Email Address' = ""
            'Destination UPN' = ""
            'Source UPN' = $mbxDetails.UserPrincipalName
            'Source Email Alias(es)' = $aliases
            'Item Count' = $stats.ItemCount
            'Send Count' = $sendCount
            'Receive Count' = $receiveCount
            'Read Count' = $stats.ItemCount - $stats.DeletedItemCount
            'Deleted Item Count' = $stats.DeletedItemCount
            'Meeting Created Count' = $calendarItemCount
            'Source Meeting Interacted Count' = $calendarItemCount
            'Storage Used (Byte)' = ConvertTo-Bytes -Size $stats.TotalItemSize
            'Issue Warning Quota (Byte)' = ConvertTo-Bytes -Size $mbxDetails.IssueWarningQuota
            'Prohibit Send Quota (Byte)' = ConvertTo-Bytes -Size $mbxDetails.ProhibitSendQuota
            'Prohibit Send/Receive Quota (Byte)' = ConvertTo-Bytes -Size $mbxDetails.ProhibitSendReceiveQuota
            'Deleted Item Size (Byte)' = ConvertTo-Bytes -Size $stats.TotalDeletedItemSize
            'Deleted Item Quota (Byte)' = ConvertTo-Bytes -Size $mbxDetails.RecoverableItemsQuota
            'x500' = $x500
            'Has Archive?' = $mbxDetails.ArchiveStatus -ne "None"
            'Legal Hold?' = $mbxDetails.LitigationHoldEnabled
            'Litigation Duration' = $mbxDetails.LitigationHoldDuration
            'Source Object ID' = $mbxDetails.ExternalDirectoryObjectId
            'Exchange Forwarding Enabled?' = $forwardingEnabled
            'Exchange Forwarding Address' = $forwardingAddress
        }
        
        $results += $obj
    }
    catch {
        Write-Warning "Error processing mailbox $($mailbox.DisplayName): $_"
    }
}

# Export to CSV
Write-Host "`nExporting to CSV: $OutputPath" -ForegroundColor Cyan
$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Export completed successfully!" -ForegroundColor Green
Write-Host "Total mailboxes exported: $($results.Count)" -ForegroundColor Green
Write-Host "Output file: $OutputPath" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Disconnect from services
Write-Host "Disconnecting from services..." -ForegroundColor Cyan
Disconnect-ExchangeOnline -Confirm:$false

if ($graphConnected) {
    Disconnect-MgGraph | Out-Null
}

Write-Host "Done!" -ForegroundColor Green
