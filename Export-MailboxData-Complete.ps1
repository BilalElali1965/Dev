# Export-MailboxData-Complete.ps1

# This script is designed to export mailbox data, specifically filtering for UserMailbox type mailboxes.

# Getting UserMailbox data
$UserMailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited

# Proceed with the rest of the exporting logic

# Updated on 2026-02-10
# The script now only processes UserMailbox mailboxes, ensuring that only relevant data is exported.