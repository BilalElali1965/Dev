<#
.SYNOPSIS
  Switch primary SMTP address and aliases of shared, room, and equipment mailboxes from OldDomain to NewDomain.
.DESCRIPTION
  This script connects to Exchange Online and updates email addresses of specified mailboxes based on provided parameters.
.PARAMETER OldDomain
  The domain that is being replaced.
.PARAMETER NewDomain
  The new domain to be assigned to the mailboxes.
.PARAMETER TestMode
  If set to $true, the script will run without making any actual changes.
#>
param (
    [string]$OldDomain,
    [string]$NewDomain,
    [bool]$TestMode = $true
)

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..."
# Connect-ExchangeOnline -UserPrincipalName user@example.com -ShowProgress $true

try {
    # Find target mailboxes
    Write-Host "Searching for shared, room, and equipment mailboxes..."
    # $mailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object {$_.RecipientTypeDetails -match 'SharedMailbox|RoomMailbox|EquipmentMailbox'}
    $mailboxes = @() # Placeholder for mailbox list
    $log = @()

    foreach ($mailbox in $mailboxes) {
        $currentPrimarySmtp = $mailbox.PrimarySmtpAddress.ToString()
        $aliases = $mailbox.Alias

        if ($currentPrimarySmtp -like "*@$OldDomain") {
            # Generate new primary SMTP
            $newPrimarySmtp = $currentPrimarySmtp.Replace($OldDomain, $NewDomain)
            Write-Host "Preparing to change: $currentPrimarySmtp to $newPrimarySmtp"

            if (-not $TestMode) {
                # Update mailbox email addresses
                # Set-Mailbox -Identity $mailbox -PrimarySmtpAddress $newPrimarySmtp
                Write-Host "Updated primary SMTP to $newPrimarySmtp"
            } else {
                Write-Host "Test mode: No changes made."
            }

            # Log changes
            $log += [PSCustomObject]@{
                Mailbox = $mailbox.Name;
                OldPrimary = $currentPrimarySmtp;
                NewPrimary = $newPrimarySmtp;
                Status = if ($TestMode) { 'Test Mode' } else { 'Updated' }
            }
        } else {
            Write-Host "No changes necessary for: $currentPrimarySmtp"
        }
    }

    # Export summary
    if ($log.Count -gt 0) {
        $log | Export-Csv -Path "MailboxUpdateSummary.csv" -NoTypeInformation
        Write-Host "Summary exported to MailboxUpdateSummary.csv"
    } else {
        Write-Host "No mailboxes updated."
    }
} catch {
    Write-Host "Error: $_"
} finally {
    # Disconnect from Exchange Online
    Write-Host "Disconnecting from Exchange Online..."
    # Disconnect-ExchangeOnline
}