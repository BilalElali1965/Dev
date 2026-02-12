<#
.SYNOPSIS
    Backup SharePoint Online configuration
.DESCRIPTION
    Exports all SharePoint site collections and related configuration
.PARAMETER ExportPath
    Path to export backup files
.PARAMETER TenantName
    Your tenant name (e.g., 'contoso' from contoso.sharepoint.com)
.EXAMPLE
    .\04-Backup-SharePoint.ps1 -TenantName "contoso" -ExportPath "C:\M365Migration\Backup"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantName,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Backup\SharePoint"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$adminUrl = "https://$TenantName-admin.sharepoint.com"

Write-Host "=== SharePoint Online Backup ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantName" -ForegroundColor Yellow
Write-Host "Export Path: $ExportPath" -ForegroundColor Yellow
Write-Host ""

# Connect to SharePoint Online
Write-Host "Connecting to SharePoint Online..." -ForegroundColor Green
try {
    Connect-SPOService -Url $adminUrl
    Write-Host "  Connected successfully" -ForegroundColor Green
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit
}

# 1. Export All Site Collections
Write-Host "[1/4] Exporting site collections..." -ForegroundColor Cyan
$sites = Get-SPOSite -Limit All
$sitesExport = $sites | Select-Object Url,Owner,Title,Template,StorageQuota,StorageUsageCurrent,Status,SharingCapability,@{N='LastContentModifiedDate';E={$_.LastContentModifiedDate}}
$sitesExport | Export-Csv -Path (Join-Path $ExportPath "SiteCollections-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($sites.Count) site collections" -ForegroundColor Green

# 2. Export Site Administrators
Write-Host "[2/4] Exporting site administrators..." -ForegroundColor Cyan
$siteAdmins = @()
foreach ($site in $sites) {
    try {
        $admins = Get-SPOUser -Site $site.Url | Where-Object { $_.IsSiteAdmin -eq $true }
        foreach ($admin in $admins) {
            $siteAdmins += [PSCustomObject]@{
                SiteUrl = $site.Url
                SiteTitle = $site.Title
                AdminLoginName = $admin.LoginName
                AdminDisplayName = $admin.DisplayName
                AdminEmail = $admin.Email
            }
        }
    } catch {
        Write-Host "  Warning: Could not retrieve admins for $($site.Url)" -ForegroundColor Yellow
    }
}
$siteAdmins | Export-Csv -Path (Join-Path $ExportPath "SiteAdministrators-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($siteAdmins.Count) site administrator assignments" -ForegroundColor Green

# 3. Export External Users
Write-Host "[3/4] Exporting external users..." -ForegroundColor Cyan
$externalUsers = Get-SPOExternalUser -PageSize 50
$externalUsersExport = $externalUsers | Select-Object DisplayName,Email,AcceptedAs,WhenCreated,InvitedBy
$externalUsersExport | Export-Csv -Path (Join-Path $ExportPath "ExternalUsers-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($externalUsers.Count) external users" -ForegroundColor Green

# 4. Export Tenant Settings
Write-Host "[4/4] Exporting tenant settings..." -ForegroundColor Cyan
$tenantSettings = Get-SPOTenant
$tenantExport = $tenantSettings | Select-Object SharingCapability,DefaultSharingLinkType,DefaultLinkPermission,RequireAcceptingAccountMatchInvitedAccount,ProvisionSharedWithEveryoneFolder,EnableGuestSignInAcceleration
$tenantExport | Export-Csv -Path (Join-Path $ExportPath "TenantSettings-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported tenant settings" -ForegroundColor Green

# Disconnect
Disconnect-SPOService

Write-Host "`nSharePoint Online backup complete!" -ForegroundColor Cyan
Write-Host "Files saved to: $ExportPath" -ForegroundColor Green
