param (
    [string]$SitesCsv = ".\Backup\OneDriveSites-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-SPOService
if (Test-Path $SitesCsv) {
    $sites = Import-Csv $SitesCsv
    foreach ($s in $sites) {
        if ($TestMode) {
            Write-Host "Would restore OneDrive site for $($s.Owner) at $($s.Url) with quota $($s.StorageQuota)MB, sharing $($s.SharingCapability)"
        } else {
            Set-SPOSite -Identity $s.Url -StorageQuota $s.StorageQuota -SharingCapability $s.SharingCapability
        }
    }
}
Disconnect-SPOService
Write-Host "OneDrive site settings restore complete."