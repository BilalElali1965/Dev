param (
    [string]$UnifiedGroupsCsv = ".\Backup\UnifiedGroups-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-ExchangeOnline -ShowBanner:$false
Import-Csv $UnifiedGroupsCsv | ForEach-Object {
    $identity = if ($_.PrimarySmtpAddress) { $_.PrimarySmtpAddress } else { $_.GroupId }
    $addrs = $_.EmailAddresses -split ';'
    if ([string]::IsNullOrWhiteSpace($identity)) {
        Write-Host "ERROR: No identity for this group, skipping..." -ForegroundColor Red
        return
    }
    if ($TestMode) {
        Write-Host "Would set EmailAddresses for UnifiedGroup $identity to $($addrs -join ', ')"
    } else {
        Set-UnifiedGroup -Identity $identity -EmailAddresses $addrs
    }
}
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Unified group restore complete."