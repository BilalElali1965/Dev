<#
.SYNOPSIS
    Backup all user/shared/resource mailbox addresses for restore.
#>
param([string]$ExportPath = ".\Backup")
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
Connect-ExchangeOnline -ShowBanner:alse
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Get-Mailbox -ResultSize Unlimited |
Select-Object DisplayName,UserPrincipalName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}} |
Export-Csv -Path (Join-Path $ExportPath "Mailboxes-$stamp.csv") -NoTypeInformation -Encoding UTF8
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Mailbox backup complete."