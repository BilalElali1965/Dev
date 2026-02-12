<#
.SYNOPSIS
    Backup SPO sites metadata, owners/admins, sharing settings.
#>
param([string]$ExportPath = ".\Backup")
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
Connect-SPOService
$sites = Get-SPOSite -Limit All
$sites | Select-Object Url,Owner,Title,Template,StorageQuota,StorageUsageCurrent,Status,SharingCapability,@{N='LastContentModifiedDate';E={$_.LastContentModifiedDate}} |
    Export-Csv -Path (Join-Path $ExportPath "SharePointSites-$stamp.csv") -NoTypeInformation -Encoding UTF8
# Site administrators
$admins = @()
foreach ($s in $sites) {
    try {
        $siteAdmins = Get-SPOUser -Site $s.Url | Where-Object { $_.IsSiteAdmin -eq $true }
        foreach ($a in $siteAdmins) {
            $admins += [PSCustomObject]@{ SiteUrl = $s.Url; SiteTitle = $s.Title; AdminEmail = $a.Email }
        }
    } catch {}
}
$admins | Export-Csv -Path (Join-Path $ExportPath "SharePointSiteAdmins-$stamp.csv") -NoTypeInformation -Encoding UTF8
Disconnect-SPOService
Write-Host "SharePoint sites backup complete."