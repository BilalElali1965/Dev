param (
    [string]$SitesCsv = ".\Backup\SharePointSites-YYYYMMDD.csv",
    [string]$AdminsCsv = ".\Backup\SharePointSiteAdmins-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-SPOService
# Restore Sites (template, storage, sharing only; files/lists not covered)
if (Test-Path $SitesCsv) {
    $sites = Import-Csv $SitesCsv
    foreach ($s in $sites) {
        if ($TestMode) {
            Write-Host "Would create SPO site $($s.Url) titled $($s.Title) with owner $($s.Owner) and template $($s.Template)"
        } else {
            New-SPOSite -Url $s.Url -Owner $s.Owner -Title $s.Title -Template $s.Template -StorageQuota $s.StorageQuota -SharingCapability $s.SharingCapability
        }
    }
}
# Restore Site Admins
if (Test-Path $AdminsCsv) {
    $admins = Import-Csv $AdminsCsv
    foreach ($a in $admins) {
        if ($TestMode) {
            Write-Host "Would add $($a.AdminEmail) as SPO Admin to $($a.SiteUrl)"
        } else {
            Set-SPOUser -Site $a.SiteUrl -LoginName $a.AdminEmail -IsSiteCollectionAdmin $true
        }
    }
}
Disconnect-SPOService
Write-Host "SPO restore complete."