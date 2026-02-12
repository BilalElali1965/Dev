param (
    [string]$MailboxesCsv = ".\Backup\Mailboxes-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-ExchangeOnline -ShowBanner:$false
Import-Csv $MailboxesCsv | ForEach-Object {
    $mbx = $_.UserPrincipalName
    $addrs = $_.EmailAddresses -split ';'
    if ($TestMode) {
        Write-Host "Would set EmailAddresses for mailbox $mbx to $($addrs -join ', ')"
    } else {
        Set-Mailbox -Identity $mbx -EmailAddresses $addrs
    }
}
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Mailbox restore complete."