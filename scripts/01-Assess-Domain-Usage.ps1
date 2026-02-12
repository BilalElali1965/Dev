<#
.SYNOPSIS
    Assess Domain Usage across M365 tenant
.DESCRIPTION
    This script identifies all objects using a specific domain across Azure AD, Exchange, SharePoint, OneDrive, and Teams
.PARAMETER OldDomain
    The domain to assess (e.g., olddomain.com)
.PARAMETER ExportPath
    Path to export assessment results
.EXAMPLE
    .\01-Assess-Domain-Usage.ps1 -OldDomain "olddomain.com" -ExportPath "C:\M365Migration\Assessment"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Assessment"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $ExportPath "DomainAssessment-$timestamp.txt"

Write-Host "=== M365 Domain Usage Assessment ===" -ForegroundColor Cyan
Write-Host "Domain: $OldDomain" -ForegroundColor Yellow
Write-Host "Export Path: $ExportPath" -ForegroundColor Yellow
Write-Host ""

# Initialize report
$report = @()
$report += "M365 Domain Usage Assessment Report"
$report += "Domain: $OldDomain"
$report += "Date: $(Get-Date)"
$report += "=" * 80
$report += ""

# Connect to services
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Green
try {
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Directory.Read.All" -NoWelcome
    $report += "[SUCCESS] Connected to Microsoft Graph"
} catch {
    $report += "[ERROR] Failed to connect to Microsoft Graph: $_"
    Write-Host "Error connecting to Microsoft Graph: $_" -ForegroundColor Red
}

Write-Host "Connecting to Exchange Online..." -ForegroundColor Green
try {
    Connect-ExchangeOnline -ShowBanner:$false
    $report += "[SUCCESS] Connected to Exchange Online"
} catch {
    $report += "[ERROR] Failed to connect to Exchange Online: $_"
    Write-Host "Error connecting to Exchange Online: $_" -ForegroundColor Red
}

$report += ""
$report += "=" * 80
$report += "ASSESSMENT RESULTS"
$report += "=" * 80
$report += ""

# 1. Check Users
Write-Host "`n[1/7] Checking Azure AD Users..." -ForegroundColor Cyan
$usersWithDomain = Get-MgUser -All | Where-Object {
    $_.UserPrincipalName -like "*@$OldDomain" -or
    $_.Mail -like "*@$OldDomain" -or
    $_.ProxyAddresses -like "*@$OldDomain"
}
$userCount = ($usersWithDomain | Measure-Object).Count
$report += "Azure AD Users with domain: $userCount"
Write-Host "  Found $userCount users" -ForegroundColor Yellow

# 2. Check Groups
Write-Host "[2/7] Checking Groups..." -ForegroundColor Cyan
$groupsWithDomain = Get-MgGroup -All | Where-Object {
    $_.Mail -like "*@$OldDomain" -or
    $_.ProxyAddresses -like "*@$OldDomain"
}
$groupCount = ($groupsWithDomain | Measure-Object).Count
$report += "Groups with domain: $groupCount"
Write-Host "  Found $groupCount groups" -ForegroundColor Yellow

# 3. Check Mailboxes
Write-Host "[3/7] Checking Mailboxes..." -ForegroundColor Cyan
$mailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object {
    $_.PrimarySmtpAddress -like "*@$OldDomain" -or
    $_.EmailAddresses -like "*@$OldDomain"
}
$mailboxCount = ($mailboxes | Measure-Object).Count
$report += "Mailboxes with domain: $mailboxCount"
Write-Host "  Found $mailboxCount mailboxes" -ForegroundColor Yellow

# 4. Check Shared Mailboxes
Write-Host "[4/7] Checking Shared Mailboxes..." -ForegroundColor Cyan
$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | Where-Object {
    $_.PrimarySmtpAddress -like "*@$OldDomain" -or
    $_.EmailAddresses -like "*@$OldDomain"
}
$sharedCount = ($sharedMailboxes | Measure-Object).Count
$report += "Shared Mailboxes with domain: $sharedCount"
Write-Host "  Found $sharedCount shared mailboxes" -ForegroundColor Yellow

# 5. Check Distribution Groups
Write-Host "[5/7] Checking Distribution Groups..." -ForegroundColor Cyan
$distributionGroups = Get-DistributionGroup -ResultSize Unlimited | Where-Object {
    $_.PrimarySmtpAddress -like "*@$OldDomain" -or
    $_.EmailAddresses -like "*@$OldDomain"
}
$dgCount = ($distributionGroups | Measure-Object).Count
$report += "Distribution Groups with domain: $dgCount"
Write-Host "  Found $dgCount distribution groups" -ForegroundColor Yellow

# 6. Check Mail Contacts
Write-Host "[6/7] Checking Mail Contacts..." -ForegroundColor Cyan
$mailContacts = Get-MailContact -ResultSize Unlimited | Where-Object {
    $_.ExternalEmailAddress -like "*@$OldDomain"
}
$contactCount = ($mailContacts | Measure-Object).Count
$report += "Mail Contacts with domain: $contactCount"
Write-Host "  Found $contactCount mail contacts" -ForegroundColor Yellow

# 7. Check Accepted Domains
Write-Host "[7/7] Checking Accepted Domains..." -ForegroundColor Cyan
$acceptedDomain = Get-AcceptedDomain | Where-Object { $_.DomainName -eq $OldDomain }
if ($acceptedDomain) {
    $report += "Domain Status: $($acceptedDomain.DomainType) - Default: $($acceptedDomain.Default)"
    Write-Host "  Domain is configured as: $($acceptedDomain.DomainType)" -ForegroundColor Yellow
} else {
    $report += "Domain Status: NOT FOUND in accepted domains"
    Write-Host "  Domain not found in accepted domains" -ForegroundColor Red
}

# Summary
$report += ""
$report += "=" * 80
$report += "SUMMARY"
$report += "=" * 80
$totalObjects = $userCount + $groupCount + $mailboxCount + $sharedCount + $dgCount + $contactCount
$report += "Total objects using domain: $totalObjects"
$report += ""
$report += "BREAKDOWN:"
$report += "  Users: $userCount"
$report += "  Groups: $groupCount"
$report += "  User Mailboxes: $mailboxCount"
$report += "  Shared Mailboxes: $sharedCount"
$report += "  Distribution Groups: $dgCount"
$report += "  Mail Contacts: $contactCount"
$report += ""

if ($totalObjects -eq 0) {
    $report += "STATUS: Domain is ready for removal"
    Write-Host "`nSTATUS: Domain appears ready for removal!" -ForegroundColor Green
} else {
    $report += "STATUS: Domain has $totalObjects associated objects - migration required"
    Write-Host "`nWARNING: Domain has $totalObjects associated objects" -ForegroundColor Red
    Write-Host "Migration required before domain removal" -ForegroundColor Red
}

# Export report
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`nAssessment report saved to: $reportPath" -ForegroundColor Green

# Disconnect
Disconnect-MgGraph | Out-Null
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`nAssessment complete!" -ForegroundColor Cyan
