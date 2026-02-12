<#
.SYNOPSIS
    Backup users' UPN, mail, and proxy addresses for restore.
#>
param([string]$ExportPath = ".\Backup")
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -NoWelcome
Connect-ExchangeOnline -ShowBanner:$false
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
# Only include users who have mailboxes
$users = Get-MgUser -All -Property Id,UserPrincipalName,Mail,ProxyAddresses,DisplayName
$data = foreach ($u in $users) {
    try {
        $mbx = Get-Mailbox -Identity $u.UserPrincipalName -ErrorAction Stop
        [PSCustomObject]@{
            Id = $u.Id
            UserPrincipalName = $u.UserPrincipalName
            DisplayName = $u.DisplayName
            Mail = $u.Mail
            ProxyAddresses = ($mbx.EmailAddresses -join ';')
        }
    } catch {
        # If no mailbox, fall back to Graph proxyaddresses
        [PSCustomObject]@{
            Id = $u.Id
            UserPrincipalName = $u.UserPrincipalName
            DisplayName = $u.DisplayName
            Mail = $u.Mail
            ProxyAddresses = ($u.ProxyAddresses -join ';')
        }
    }
}
$data | Export-Csv -Path (Join-Path $ExportPath "Users-$stamp.csv") -NoTypeInformation -Encoding UTF8
Disconnect-MgGraph | Out-Null
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Users backup completed."