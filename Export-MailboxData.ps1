<#
.SYNOPSIS
    Exports Exchange Online mailbox data to CSV
.DESCRIPTION
    This script connects to Exchange Online and exports detailed mailbox information including
    statistics, quotas, archive status, and forwarding settings to a CSV file.
.PARAMETER OutputPath
    The path where the CSV file will be saved. Default: .\mailbox_export.csv
#>

param(
    [string]$OutputPath = ".\mailbox_export.csv"
)

# Import required modules
try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Host "Exchange Online Management module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Error: Exchange Online Management module not found. Please install it first:" -ForegroundColor Red
    Write-Host "Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

# Connect to Exchange Online
try {
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "Connected successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Error connecting to Exchange Online: $_" -ForegroundColor Red
    exit
}

# Get all mailboxes
Write-Host "Retrieving mailboxes..." -ForegroundColor Cyan
$mailboxes = Get-Mailbox -ResultSize Unlimited

# Initialize results array
$results = @()

$counter = 0
$total = $mailboxes.Count
Write-Host "Processing $total mailboxes..." -ForegroundColor Cyan

foreach ($mailbox in $mailboxes) {
    $counter++
    Write-Progress -Activity "Processing Mailboxes" -Status "Processing $($mailbox.DisplayName) ($counter of $total)" -PercentComplete (($counter / $total) * 100)
    
    try {
        # Get mailbox statistics
        $stats = Get-MailboxStatistics -Identity $mailbox.Identity -ErrorAction SilentlyContinue
        
        # Get mailbox details
        $mbxDetails = Get-Mailbox -Identity $mailbox.Identity
        
        # Get assigned licenses/products
        $user = Get-User -Identity $mailbox.Identity -ErrorAction SilentlyContinue
        
        # Get forwarding information
        $forwardingEnabled = $false
        $forwardingAddress = ""
        if ($mbxDetails.ForwardingAddress -or $mbxDetails.ForwardingSmtpAddress) {
            $forwardingEnabled = $true
            $forwardingAddress = if ($mbxDetails.ForwardingSmtpAddress) { $mbxDetails.ForwardingSmtpAddress } else { $mbxDetails.ForwardingAddress }
        }
        
        # Get email aliases
        $aliases = ($mbxDetails.EmailAddresses | Where-Object { $_ -like "smtp:*" -and $_ -notlike "*$($mbxDetails.PrimarySmtpAddress)*" }) -join "; "
        
        # Get x500 address
        $x500 = ($mbxDetails.EmailAddresses | Where-Object { $_ -like "X500:*" }) -join "; "
        
        # Create custom object with all properties
        $obj = [PSCustomObject]@{
            'Source Employment Status' = $user.RecipientTypeDetails
            'Source Display Name' = $mbxDetails.DisplayName
            'Source Email Address' = $mbxDetails.PrimarySmtpAddress
            'Email Last Activity Date' = $stats.LastLogonTime
            'Assigned Products' = ""  # This requires Azure AD connection - see note below
            'Destination Email Address' = ""  # Populate if migration
            'Destination UPN' = ""  # Populate if migration
            'Source UPN' = $mbxDetails.UserPrincipalName
            'Source Email Alias(es)' = $aliases
            'Item Count' = $stats.ItemCount
            'Send Count' = ""  # Requires message tracking logs
            'Receive Count' = ""  # Requires message tracking logs
            'Read Count' = ""  # Not directly available
            'Deleted Item Count' = $stats.DeletedItemCount
            'Meeting Created Count' = ""  # Requires calendar analysis
            'Source Meeting Interacted Count' = ""  # Requires calendar analysis
            'Storage Used (Byte)' = $stats.TotalItemSize.Value.ToBytes()
            'Issue Warning Quota (Byte)' = if ($mbxDetails.IssueWarningQuota -ne "Unlimited") { $mbxDetails.IssueWarningQuota.Value.ToBytes() } else { "Unlimited" }
            'Prohibit Send Quota (Byte)' = if ($mbxDetails.ProhibitSendQuota -ne "Unlimited") { $mbxDetails.ProhibitSendQuota.Value.ToBytes() } else { "Unlimited" }
            'Prohibit Send/Receive Quota (Byte)' = if ($mbxDetails.ProhibitSendReceiveQuota -ne "Unlimited") { $mbxDetails.ProhibitSendReceiveQuota.Value.ToBytes() } else { "Unlimited" }
            'Deleted Item Size (Byte)' = if ($stats.TotalDeletedItemSize) { $stats.TotalDeletedItemSize.Value.ToBytes() } else { 0 }
            'Deleted Item Quota (Byte)' = if ($mbxDetails.RecoverableItemsQuota -ne "Unlimited") { $mbxDetails.RecoverableItemsQuota.Value.ToBytes() } else { "Unlimited" }
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

Write-Host "Export completed successfully!" -ForegroundColor Green
Write-Host "Total mailboxes exported: $($results.Count)" -ForegroundColor Green
Write-Host "Output file: $OutputPath" -ForegroundColor Green

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false

<#
NOTES:
1. Some fields like 'Assigned Products', 'Send Count', 'Receive Count', etc. require additional data sources:
   - Assigned Products: Requires Microsoft Graph API connection to get user licenses
   - Send/Receive Count: Requires message tracking logs or mailbox audit logs
   - Meeting counts: Requires calendar item analysis

2. To get Assigned Products (licenses), add this code after connecting to Exchange Online:

   Connect-MgGraph -Scopes "User.Read.All"
   $licenses = Get-MgUserLicenseDetail -UserId $mbxDetails.UserPrincipalName
   $assignedProducts = ($licenses.SkuPartNumber) -join "; "

3. For message tracking (Send/Receive counts), you would need to query message tracking logs
   which can be resource-intensive for large environments.
#>