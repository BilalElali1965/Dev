<#!
.SYNOPSIS
    Master monolithic script for full or selective M365 backup.
    Usage examples:
      .\Monolithic-Master-Backup-Script.ps1            # Back up ALL aspects.
      .\Monolithic-Master-Backup-Script.ps1 -Teams     # Only Teams.
      .\Monolithic-Master-Backup-Script.ps1 -SharePoint -Teams   # Just SharePoint and Teams.
#!>
param(
    [switch]$OneDrive,
    [switch]$SharePoint,
    [switch]$Teams,
    [switch]$Mailboxes,
    [switch]$UnifiedGroups,
    [switch]$DistributionGroups,
    [switch]$All = $false,
    [string]$ExportPath = ".\\Backup"
)

function Backup-OneDrive {
    Write-Host "`n=== OneDrive backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Connect-SPOService
    $sites = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'"
    $sites | Select-Object Url,Owner,StorageQuota,StorageUsageCurrent,Status,SharingCapability,LastContentModifiedDate |
        Export-Csv -Path (Join-Path $ExportPath "OneDriveSites-$stamp.csv") -NoTypeInformation -Encoding UTF8
    Disconnect-SPOService
    Write-Host "OneDrive backup complete."
}

function Backup-SharePoint {
    Write-Host "`n=== SharePoint backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Connect-SPOService
    $sites = Get-SPOSite -Limit All
    $sites | Select-Object Url,Owner,Title,Template,StorageQuota,StorageUsageCurrent,Status,SharingCapability,@{N='LastContentModifiedDate';E={$_.LastContentModifiedDate}} |
        Export-Csv -Path (Join-Path $ExportPath "SharePointSites-$stamp.csv") -NoTypeInformation -Encoding UTF8
    # Admins
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
}

function Backup-Teams {
    Write-Host "`n=== Teams backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    Connect-MicrosoftTeams
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Get-Team | Select-Object GroupId,DisplayName,Description,Visibility,MailNickName,Archived |
        Export-Csv -Path (Join-Path $ExportPath "Teams-$stamp.csv") -NoTypeInformation -Encoding UTF8
    $channels = @()
    foreach ($t in Get-Team) {
        $gId = $t.GroupId
        try { $ch = Get-TeamChannel -GroupId $gId | Select-Object @{N='TeamGroupId';E={$gId}},Id,DisplayName,Description,MembershipType
              $channels += $ch
        } catch {}
    }
    $channels | Export-Csv -Path (Join-Path $ExportPath "TeamChannels-$stamp.csv") -NoTypeInformation -Encoding UTF8
    $members = @()
    foreach ($t in Get-Team) {
        $gId = $t.GroupId
        try { $m = Get-TeamUser -GroupId $gId | Select-Object @{N='TeamGroupId';E={$gId}},User,Role
              $members += $m
        } catch {}
    }
    $members | Export-Csv -Path (Join-Path $ExportPath "TeamMembers-$stamp.csv") -NoTypeInformation -Encoding UTF8
    Disconnect-MicrosoftTeams
    Write-Host "Teams backup complete."
}

function Backup-Mailboxes {
    Write-Host "`n=== Mailboxes backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    Connect-ExchangeOnline -ShowBanner:$false
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Get-Mailbox -ResultSize Unlimited |
        Select-Object DisplayName,UserPrincipalName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}} |
        Export-Csv -Path (Join-Path $ExportPath "Mailboxes-$stamp.csv") -NoTypeInformation -Encoding UTF8
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "Mailboxes backup complete."
}

function Backup-UnifiedGroups {
    Write-Host "`n=== Unified Groups backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    Connect-ExchangeOnline -ShowBanner:$false
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Get-UnifiedGroup -ResultSize Unlimited |
        Select-Object DisplayName,PrimarySmtpAddress,GroupId,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}} |
        Export-Csv -Path (Join-Path $ExportPath "UnifiedGroups-$stamp.csv") -NoTypeInformation -Encoding UTF8
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "Unified groups backup complete."
}

function Backup-DistributionGroups {
    Write-Host "`n=== Distribution Groups backup ==="
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
    Connect-ExchangeOnline -ShowBanner:$false
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Get-DistributionGroup -ResultSize Unlimited |
        Select-Object DisplayName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}} |
        Export-Csv -Path (Join-Path $ExportPath "DistributionGroups-$stamp.csv") -NoTypeInformation -Encoding UTF8
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "Distribution groups backup complete."
}

Write-Host "`n=== M365 Monolithic Backup Script Start ===`n"
if ($All -or $OneDrive)          { Backup-OneDrive }
if ($All -or $SharePoint)        { Backup-SharePoint }
if ($All -or $Teams)             { Backup-Teams }
if ($All -or $Mailboxes)         { Backup-Mailboxes }
if ($All -or $UnifiedGroups)     { Backup-UnifiedGroups }
if ($All -or $DistributionGroups){ Backup-DistributionGroups }
Write-Host "`n=== All Selected Backups Complete ===`n"