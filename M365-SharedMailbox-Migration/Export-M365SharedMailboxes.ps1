<#
.SYNOPSIS
    Exports all M365 Shared Mailboxes to a CSV file with comprehensive configuration details.

.DESCRIPTION
    This script connects to Exchange Online and exports all shared mailboxes with detailed 
    information including permissions, aliases, size, archive status, and litigation hold settings.
    The export includes all necessary information for migration or backup purposes.

.PARAMETER OutputPath
    The path where the CSV file will be saved. 
    Default: .\SharedMailboxes_Export_YYYYMMDD_HHMMSS.csv

.PARAMETER Verbose
    Display detailed progress and diagnostic information during export.

.EXAMPLE
    .\Export-M365SharedMailboxes.ps1
    Exports all shared mailboxes to the default output file.

.EXAMPLE
    .\Export-M365SharedMailboxes.ps1 -OutputPath "C:\Exports\SharedMailboxes.csv" -Verbose
    Exports shared mailboxes to a specific path with verbose output.

.NOTES
    Requires: ExchangeOnlineManagement module (v3.0.0 or higher)
    Requires: Exchange Administrator role or higher
    Compatible with: PowerShell 5.1 and PowerShell 7+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\SharedMailboxes_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'Info'    { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    
    # Also log to file
    $logPath = $OutputPath -replace '\.csv$', '.log'
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logPath -Append -Encoding UTF8
}

function Test-ExchangeOnlineConnection {
    try {
        $null = Get-OrganizationConfig -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Connect-ExchangeOnlineIfNeeded {
    Write-Log "Checking Exchange Online connection..." -Level Info
    
    if (-not (Test-ExchangeOnlineConnection)) {
        Write-Log "Not connected to Exchange Online. Initiating connection..." -Level Warning
        
        try {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            Write-Log "Successfully connected to Exchange Online" -Level Success
        }
        catch {
            Write-Log "Failed to connect to Exchange Online: $($_.Exception.Message)" -Level Error
            throw
        }
    }
    else {
        Write-Log "Already connected to Exchange Online" -Level Success
    }
}

function Get-MailboxOwners {
    param($MailboxIdentity)
    
    try {
        $permissions = Get-MailboxPermission -Identity $MailboxIdentity -ErrorAction SilentlyContinue | 
            Where-Object { $_.IsInherited -eq $false -and $_.User -notlike "NT AUTHORITY\*" -and $_.User -notlike "S-1-5-*" }
        
        if ($permissions) {
            $owners = $permissions | Where-Object { $_.AccessRights -contains "FullAccess" } | Select-Object -ExpandProperty User
            return ($owners -join '; ')
        }
    }
    catch {
        Write-Verbose "Error getting owners for $MailboxIdentity : $($_.Exception.Message)"
    }
    
    return ""
}

function Get-MailboxMembers {
    param($MailboxIdentity)
    
    try {
        $permissions = Get-MailboxPermission -Identity $MailboxIdentity -ErrorAction SilentlyContinue | 
            Where-Object { $_.IsInherited -eq $false -and $_.User -notlike "NT AUTHORITY\*" -and $_.User -notlike "S-1-5-*" }
        
        if ($permissions) {
            $members = $permissions | Select-Object -ExpandProperty User -Unique
            return ($members -join '; ')
        }
    }
    catch {
        Write-Verbose "Error getting members for $MailboxIdentity : $($_.Exception.Message)"
    }
    
    return ""
}

function Get-SendOnBehalfUsers {
    param($Mailbox)
    
    try {
        if ($Mailbox.GrantSendOnBehalfTo) {
            return ($Mailbox.GrantSendOnBehalfTo -join '; ')
        }
    }
    catch {
        Write-Verbose "Error getting SendOnBehalf for $($Mailbox.Identity) : $($_.Exception.Message)"
    }
    
    return ""
}

function Get-EmailAliases {
    param($Mailbox)
    
    try {
        if ($Mailbox.EmailAddresses) {
            $aliases = $Mailbox.EmailAddresses | Where-Object { $_ -like "smtp:*" -and $_ -notlike "SMTP:*" } | 
                ForEach-Object { $_ -replace "smtp:", "" }
            
            if ($aliases) {
                return ($aliases -join '; ')
            }
        }
    }
    catch {
        Write-Verbose "Error getting aliases for $($Mailbox.Identity) : $($_.Exception.Message)"
    }
    
    return ""
}

function Get-MailboxSizeInfo {
    param($MailboxIdentity)
    
    try {
        $stats = Get-MailboxStatistics -Identity $MailboxIdentity -ErrorAction SilentlyContinue
        
        if ($stats -and $stats.TotalItemSize) {
            return $stats.TotalItemSize.ToString()
        }
    }
    catch {
        Write-Verbose "Error getting size for $MailboxIdentity : $($_.Exception.Message)"
    }
    
    return "0 bytes"
}

function Get-ArchiveStatusInfo {
    param($Mailbox)
    
    try {
        if ($Mailbox.ArchiveStatus -eq "Active" -or $Mailbox.ArchiveState -eq "Local") {
            return "Enabled"
        }
        elseif ($Mailbox.ArchiveStatus -eq "None" -or $Mailbox.ArchiveState -eq "None") {
            return "Disabled"
        }
        else {
            return $Mailbox.ArchiveStatus.ToString()
        }
    }
    catch {
        return "Unknown"
    }
}

function Get-LitigationHoldInfo {
    param($Mailbox)
    
    try {
        if ($Mailbox.LitigationHoldEnabled -eq $true) {
            return "Enabled"
        }
        else {
            return "Disabled"
        }
    }
    catch {
        return "Disabled"
    }
}

function Get-LitigationDurationInfo {
    param($Mailbox)
    
    try {
        if ($Mailbox.LitigationHoldDuration) {
            return $Mailbox.LitigationHoldDuration.ToString()
        }
    }
    catch {
        Write-Verbose "Error getting litigation duration: $($_.Exception.Message)"
    }
    
    return ""
}

#endregion

#region Main Script

try {
    Write-Log "========================================" -Level Info
    Write-Log "M365 Shared Mailbox Export Script" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "" -Level Info
    
    # Check for required module
    Write-Log "Checking for ExchangeOnlineManagement module..." -Level Info
    $module = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
    
    if (-not $module) {
        Write-Log "ExchangeOnlineManagement module not found!" -Level Error
        Write-Log "Please install it using: Install-Module -Name ExchangeOnlineManagement -Force" -Level Error
        throw "Required module not found"
    }
    
    if ($module.Version -lt [Version]"3.0.0") {
        Write-Log "ExchangeOnlineManagement version $($module.Version) found, but 3.0.0 or higher is recommended" -Level Warning
    }
    else {
        Write-Log "ExchangeOnlineManagement version $($module.Version) found" -Level Success
    }
    
    # Import module
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    
    # Connect to Exchange Online
    Connect-ExchangeOnlineIfNeeded
    
    # Get all shared mailboxes
    Write-Log "Retrieving all shared mailboxes from tenant..." -Level Info
    $sharedMailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox -ErrorAction Stop
    
    if (-not $sharedMailboxes) {
        Write-Log "No shared mailboxes found in the tenant" -Level Warning
        return
    }
    
    $totalMailboxes = @($sharedMailboxes).Count
    Write-Log "Found $totalMailboxes shared mailbox(es) to export" -Level Success
    Write-Log "" -Level Info
    
    # Initialize results array
    $results = @()
    $counter = 0
    
    # Process each mailbox
    foreach ($mailbox in $sharedMailboxes) {
        $counter++
        $percentComplete = [math]::Round(($counter / $totalMailboxes) * 100)
        
        Write-Progress -Activity "Exporting Shared Mailboxes" -Status "Processing $($mailbox.DisplayName) ($counter of $totalMailboxes)" -PercentComplete $percentComplete
        Write-Log "[$counter/$totalMailboxes] Processing: $($mailbox.DisplayName)" -Level Info
        
        try {
            # Get mailbox details
            $owners = Get-MailboxOwners -MailboxIdentity $mailbox.Identity
            $members = Get-MailboxMembers -MailboxIdentity $mailbox.Identity
            $sendOnBehalf = Get-SendOnBehalfUsers -Mailbox $mailbox
            $aliases = Get-EmailAliases -Mailbox $mailbox
            $mailboxSize = Get-MailboxSizeInfo -MailboxIdentity $mailbox.Identity
            $archiveStatus = Get-ArchiveStatusInfo -Mailbox $mailbox
            $litigationHold = Get-LitigationHoldInfo -Mailbox $mailbox
            $litigationDuration = Get-LitigationDurationInfo -Mailbox $mailbox
            
            # Create result object with exact column order
            $resultObject = [PSCustomObject]@{
                'Source Display Name' = $mailbox.DisplayName
                'Mailbox Type' = $mailbox.RecipientTypeDetails.ToString()
                'Source Email Address' = $mailbox.PrimarySmtpAddress
                'Source UPN' = $mailbox.UserPrincipalName
                'Source Owner' = $owners
                'Source Members' = $members
                'Source Email Alias(es)' = $aliases
                'Current Mailbox Size' = $mailboxSize
                'Grant Send On Behalf' = $sendOnBehalf
                'Require Sender Auth' = $mailbox.RequireSenderAuthenticationEnabled
                'Archive Status' = $archiveStatus
                'Legal Hold' = $litigationHold
                'Litigation Duration' = $litigationDuration
                'Source Object ID' = $mailbox.ExternalDirectoryObjectId
            }
            
            $results += $resultObject
            Write-Verbose "Successfully processed: $($mailbox.DisplayName)"
        }
        catch {
            Write-Log "Error processing mailbox $($mailbox.DisplayName): $($_.Exception.Message)" -Level Error
        }
    }
    
    Write-Progress -Activity "Exporting Shared Mailboxes" -Completed
    
    # Export to CSV
    Write-Log "" -Level Info
    Write-Log "Exporting results to CSV..." -Level Info
    
    try {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Successfully exported $($results.Count) shared mailbox(es) to: $OutputPath" -Level Success
        
        # Display summary
        Write-Log "" -Level Info
        Write-Log "========================================" -Level Info
        Write-Log "Export Summary" -Level Info
        Write-Log "========================================" -Level Info
        Write-Log "Total Shared Mailboxes: $totalMailboxes" -Level Info
        Write-Log "Successfully Exported: $($results.Count)" -Level Success
        Write-Log "Failed: $($totalMailboxes - $results.Count)" -Level Warning
        Write-Log "Output File: $OutputPath" -Level Info
        Write-Log "Log File: $($OutputPath -replace '\.csv$', '.log')" -Level Info
        Write-Log "========================================" -Level Info
    }
    catch {
        Write-Log "Failed to export CSV: $($_.Exception.Message)" -Level Error
        throw
    }
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    throw
}
finally {
    Write-Log "" -Level Info
    Write-Log "Script execution completed" -Level Info
}

#endregion
