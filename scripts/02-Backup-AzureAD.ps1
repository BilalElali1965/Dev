<#
.SYNOPSIS
    Backup Azure AD/Entra ID user and group information
.DESCRIPTION
    Exports all users, groups, and related configuration that reference the old domain
.PARAMETER OldDomain
    The domain to backup (e.g., olddomain.com)
.PARAMETER ExportPath
    Path to export backup files
.EXAMPLE
    .\02-Backup-AzureAD.ps1 -OldDomain "olddomain.com" -ExportPath "C:\M365Migration\Backup"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Backup\AzureAD"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== Azure AD Backup ===" -ForegroundColor Cyan
Write-Host "Domain: $OldDomain" -ForegroundColor Yellow
Write-Host "Export Path: $ExportPath" -ForegroundColor Yellow
Write-Host ""

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Green
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All" -NoWelcome

# Export All Users
Write-Host "[1/4] Exporting all users..." -ForegroundColor Cyan
$allUsers = Get-MgUser -All -Property Id,UserPrincipalName,DisplayName,Mail,ProxyAddresses,AccountEnabled,UserType,CreatedDateTime
$usersExport = $allUsers | Select-Object Id,UserPrincipalName,DisplayName,Mail,@{N='ProxyAddresses';E={$_.ProxyAddresses -join ';'}},AccountEnabled,UserType,CreatedDateTime
$usersExport | Export-Csv -Path (Join-Path $ExportPath "AllUsers-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($allUsers.Count) users" -ForegroundColor Green

# Export Users with Old Domain
Write-Host "[2/4] Exporting users with old domain..." -ForegroundColor Cyan
$domainUsers = $allUsers | Where-Object {
    $_.UserPrincipalName -like "*@${OldDomain}" -or
    $_.Mail -like "*@${OldDomain}" -or
    $_.ProxyAddresses -like "*@${OldDomain}"
}
$domainUsersExport = $domainUsers | Select-Object Id,UserPrincipalName,DisplayName,Mail,@{N='ProxyAddresses';E={$_.ProxyAddresses -join ';'}},AccountEnabled,UserType
$domainUsersExport | Export-Csv -Path (Join-Path $ExportPath "DomainUsers-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($domainUsers.Count) users with domain" -ForegroundColor Green

# Export All Groups
Write-Host "[3/4] Exporting all groups..." -ForegroundColor Cyan
$allGroups = Get-MgGroup -All -Property Id,DisplayName,Mail,ProxyAddresses,GroupTypes,SecurityEnabled,MailEnabled
$groupsExport = $allGroups | Select-Object Id,DisplayName,Mail,@{N='ProxyAddresses';E={$_.ProxyAddresses -join ';'}},@{N='GroupTypes';E={$_.GroupTypes -join ';'}},SecurityEnabled,MailEnabled
$groupsExport | Export-Csv -Path (Join-Path $ExportPath "AllGroups-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($allGroups.Count) groups" -ForegroundColor Green

# Export Groups with Old Domain
Write-Host "[4/4] Exporting groups with old domain..." -ForegroundColor Cyan
$domainGroups = $allGroups | Where-Object {
    $_.Mail -like "*@${OldDomain}" -or
    $_.ProxyAddresses -like "*@${OldDomain}"
}
$domainGroupsExport = $domainGroups | Select-Object Id,DisplayName,Mail,@{N='ProxyAddresses';E={$_.ProxyAddresses -join ';'}},@{N='GroupTypes';E={$_.GroupTypes -join ';'}},SecurityEnabled,MailEnabled
$domainGroupsExport | Export-Csv -Path (Join-Path $ExportPath "DomainGroups-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($domainGroups.Count) groups with domain" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph | Out-Null

Write-Host "`nAzure AD backup complete!" -ForegroundColor Cyan
Write-Host "Files saved to: $ExportPath" -ForegroundColor Green
