param (
    [string]$GroupsCsv = ".\Backup\DistributionGroups-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-ExchangeOnline -ShowBanner:$false
Import-Csv $GroupsCsv | ForEach-Object {
    $identity = $_.PrimarySmtpAddress
    $addrs = $_.EmailAddresses -split ';'
    if ($TestMode) {
        Write-Host "Would set EmailAddresses for DistributionGroup $identity to $($addrs -join ', ')"
    } else {
        Set-DistributionGroup -Identity $identity -EmailAddresses $addrs
    }
}
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "Distribution group restore complete."