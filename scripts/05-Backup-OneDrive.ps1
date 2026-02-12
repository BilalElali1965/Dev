<#
.SYNOPSIS
    Backup OneDrive for Business configuration
.DESCRIPTION
    Exports all OneDrive site information
.PARAMETER ExportPath
    Path to export backup files
.PARAMETER TenantName
    Your tenant name (e.g., 'contoso' from contoso.sharepoint.com)
.EXAMPLE
    .\05-Backup-OneDrive.ps1 -TenantName "contoso" -ExportPath "C:\M365Migration\Backup"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantName,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Backup\OneDrive"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$adminUrl = "https://$TenantName-admin.sharepoint.com"

Write-Host "=== OneDrive for Business Backup ===" -ForegroundColor Cyan
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

# 1. Export All OneDrive Sites
Write-Host "[1/2] Exporting OneDrive sites (this may take a while)..." -ForegroundColor Cyan
$oneDriveSites = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'"
$oneDriveExport = $oneDriveSites | Select-Object Url,Owner,StorageQuota,@{N='StorageUsageCurrent';E={$_.StorageUsageCurrent}},Status,SharingCapability,LastContentModifiedDate
$oneDriveExport | Export-Csv -Path (Join-Path $ExportPath "OneDriveSites-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($oneDriveSites.Count) OneDrive sites" -ForegroundColor Green

# 2. Export OneDrive Site Details
Write-Host "[2/2] Exporting detailed OneDrive information..." -ForegroundColor Cyan
$oneDriveDetails = @()
foreach ($site in $oneDriveSites) {
    try {
        $siteOwner = Get-SPOUser -Site $site.Url -Limit All | Where-Object { $_.IsSiteAdmin -eq $true } | Select-Object -First 1
        $oneDriveDetails += [PSCustomObject]@{
            OneDriveUrl = $site.Url
            OwnerLoginName = $site.Owner
            OwnerDisplayName = $siteOwner.DisplayName
            OwnerEmail = $siteOwner.Email
            StorageQuotaMB = $site.StorageQuota
            StorageUsedMB = $site.StorageUsageCurrent
            LastModified = $site.LastContentModifiedDate
            Status = $site.Status
        }
    } catch {
        Write-Host "  Warning: Could not retrieve details for $($site.Url)" -ForegroundColor Yellow
    }
}
$oneDriveDetails | Export-Csv -Path (Join-Path $ExportPath "OneDriveDetails-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($oneDriveDetails.Count) OneDrive details" -ForegroundColor Green

# Disconnect
Disconnect-SPOService

Write-Host "`nOneDrive for Business backup complete!" -ForegroundColor Cyan
Write-Host "Files saved to: $ExportPath" -ForegroundColor Green
