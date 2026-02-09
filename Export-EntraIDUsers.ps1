# Updated PowerShell Script to Export Entra ID Users

# Required Modules
Import-Module AzureAD
Import-Module Microsoft.Graph

# Credentials and Context
$credentials = Get-Credential
Connect-AzureAD -Credential $credentials
Connect-MgGraph -Credential $credentials

# Fetch Users
$users = Get-AzureADUser -All $true

# Create an array for exports
$exportData = @()

foreach ($user in $users) {
    # Fetch additional properties
    $mailbox = Get-MgUserMailbox -UserId $user.ObjectId -ErrorAction SilentlyContinue
    $licenses = Get-AzureADUserLicenseDetail -ObjectId $user.ObjectId
    $assignedLicenses = $licenses | ForEach-Object { $_.SkuPartNumber } -join '; '
    
    # Create an object for export
    $userData = [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        DisplayName = $user.DisplayName
        AccountType = if ($user.AccountEnabled) { 'User' } else { 'Guest' }
        MailboxType = if ($mailbox) { $mailbox.MailboxType } else { 'No Mailbox' }
        AssignedLicenses = $assignedLicenses
    }
    
    $exportData += $userData
}

# Export to CSV
$exportData | Export-Csv -Path 'EntraIDUsersExport.csv' -NoTypeInformation -Encoding UTF8

# Disconnect from services
Disconnect-AzureAD
Disconnect-MgGraph