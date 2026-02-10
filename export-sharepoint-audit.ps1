# M365 SharePoint Site Audit Export Script
# This script exports SharePoint site URLs, titles, owners, members, permissions, and user details

Write-Host "Connecting to SharePoint Admin Center..." -ForegroundColor Green
Write-Host "Note: You must connect to SharePoint first using Connect-SPOService" -ForegroundColor Yellow

# Get all SharePoint sites
Write-Host "Retrieving all SharePoint sites..." -ForegroundColor Green
$sites = Get-SPOSite -Limit All

$results = @()
$counter = 0

foreach ($site in $sites) {
    $counter++
    Write-Host "Processing site $counter of $($sites.Count): $($site.Url)" -ForegroundColor Cyan
    
    try {
        # Get site URL and Title
        $siteUrl = $site.Url
        $siteTitle = $site.Title
        
        # Get Site Owners (Site Collection Admins)
        $owners = Get-SPOUser -Site $siteUrl | Where-Object {$_.IsSiteAdmin -eq $true}
        
        # Get all users on the site
        $users = Get-SPOUser -Site $siteUrl
        
        foreach ($user in $users) {
            $results += [PSCustomObject]@{
                SiteUrl         = $siteUrl
                SiteTitle       = $siteTitle
                UserName        = $user.DisplayName
                UserEmail       = $user.LoginName
                LoginName       = $user.LoginName
                IsOwner         = $user.IsSiteAdmin
                IsSiteAdmin     = $user.IsSiteAdmin
            }
        }
    }
    catch {
        Write-Host "Error processing site $siteUrl : $_" -ForegroundColor Red
    }
}

# Export to CSV
$outputPath = "M365_SharePointSiteAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Host "Export completed! File saved to $outputPath" -ForegroundColor Green
Write-Host "Total sites processed: $counter" -ForegroundColor Green
Write-Host "Total user records exported: $($results.Count)" -ForegroundColor Green