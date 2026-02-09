# PowerShell Script to Export Entra ID Users with Mailbox and OneDrive Information

# Import the required modules for Microsoft Graph
Import-Module Microsoft.Graph

# Connect to Microsoft Graph
# Ensure you have the necessary permissions
Connect-MgGraph -Scopes "User.Read.All", "Mail.Read", "MailboxSettings.Read"

# Retrieve users’ mailbox settings and OneDrive information
$users = Get-MgUser -All
$results = @()

foreach ($user in $users) {
    # Get mailbox settings
    $mailboxSettings = Get-MgUserMailboxSettings -UserId $user.Id
    $mailboxType = "Unknown"

    # Determine mailbox type
    if ($mailboxSettings | Where-Object { $_.MailboxType -eq 'UserMailbox' }) {
        $mailboxType = 'User Mailbox'
    } elseif ($mailboxSettings | Where-Object { $_.MailboxType -eq 'SharedMailbox' }) {
        $mailboxType = 'Shared Mailbox'
    } elseif ($mailboxSettings | Where-Object { $_.MailboxType -eq 'RoomMailbox' }) {
        $mailboxType = 'Room Mailbox'
    } elseif ($mailboxSettings | Where-Object { $_.MailboxType -eq 'EquipmentMailbox' }) {
        $mailboxType = 'Equipment Mailbox'
    }

    # Check OneDrive status
    $oneDrive = Get-MgUserDrive -UserId $user.Id
    $hasOneDrive = if ($oneDrive) { $true } else { $false }

    # Create an object to hold the user's information
    $result = [PSCustomObject]@{
        UserPrincipalName = $user.UserPrincipalName
        MailboxType = $mailboxType
        HasOneDrive = $hasOneDrive
    }
    $results += $result
}

# Export results to CSV
$results | Export-Csv -Path "EntraIDUsersExport.csv" -NoTypeInformation -Encoding UTF8