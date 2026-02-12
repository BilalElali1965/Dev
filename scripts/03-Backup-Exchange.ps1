<#
.SYNOPSIS
    Backup Exchange Online configuration
.DESCRIPTION
    Exports all mailboxes, distribution groups, and email configuration
.PARAMETER OldDomain
    The domain to backup (e.g., olddomain.com)
.PARAMETER ExportPath
    Path to export backup files
.EXAMPLE
    .\03-Backup-Exchange.ps1 -OldDomain "olddomain.com" -ExportPath "C:\M365Migration\Backup"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Backup\Exchange"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== Exchange Online Backup ===" -ForegroundColor Cyan
Write-Host "Domain: $OldDomain" -ForegroundColor Yellow
Write-Host "Export Path: $ExportPath" -ForegroundColor Yellow
Write-Host ""

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Green
Connect-ExchangeOnline -ShowBanner:$false

# 1. Export All User Mailboxes
Write-Host "[1/9] Exporting user mailboxes..." -ForegroundColor Cyan
$userMailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited
$userMailboxesExport = $userMailboxes | Select-Object DisplayName,PrimarySmtpAddress,UserPrincipalName,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},RecipientTypeDetails,WhenCreated
$userMailboxesExport | Export-Csv -Path (Join-Path $ExportPath "UserMailboxes-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($userMailboxes.Count) user mailboxes" -ForegroundColor Green

# 2. Export Shared Mailboxes
Write-Host "[2/9] Exporting shared mailboxes..." -ForegroundColor Cyan
$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited
$sharedMailboxesExport = $sharedMailboxes | Select-Object DisplayName,PrimarySmtpAddress,UserPrincipalName,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},RecipientTypeDetails
$sharedMailboxesExport | Export-Csv -Path (Join-Path $ExportPath "SharedMailboxes-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($sharedMailboxes.Count) shared mailboxes" -ForegroundColor Green

# 3. Export Room Mailboxes
Write-Host "[3/9] Exporting room mailboxes..." -ForegroundColor Cyan
$roomMailboxes = Get-Mailbox -RecipientTypeDetails RoomMailbox -ResultSize Unlimited
$roomMailboxesExport = $roomMailboxes | Select-Object DisplayName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},RecipientTypeDetails
$roomMailboxesExport | Export-Csv -Path (Join-Path $ExportPath "RoomMailboxes-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($roomMailboxes.Count) room mailboxes" -ForegroundColor Green

# 4. Export Equipment Mailboxes
Write-Host "[4/9] Exporting equipment mailboxes..." -ForegroundColor Cyan
$equipmentMailboxes = Get-Mailbox -RecipientTypeDetails EquipmentMailbox -ResultSize Unlimited
$equipmentMailboxesExport = $equipmentMailboxes | Select-Object DisplayName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},RecipientTypeDetails
$equipmentMailboxesExport | Export-Csv -Path (Join-Path $ExportPath "EquipmentMailboxes-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($equipmentMailboxes.Count) equipment mailboxes" -ForegroundColor Green

# 5. Export Distribution Groups
Write-Host "[5/9] Exporting distribution groups..." -ForegroundColor Cyan
$distributionGroups = Get-DistributionGroup -ResultSize Unlimited
$dgExport = $distributionGroups | Select-Object DisplayName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},GroupType,@{N='ManagedBy';E={$_.ManagedBy -join ';'}}
$dgExport | Export-Csv -Path (Join-Path $ExportPath "DistributionGroups-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($distributionGroups.Count) distribution groups" -ForegroundColor Green

# 6. Export Mail-Enabled Security Groups
Write-Host "[6/9] Exporting mail-enabled security groups..." -ForegroundColor Cyan
$securityGroups = Get-DistributionGroup -RecipientTypeDetails MailUniversalSecurityGroup -ResultSize Unlimited
$sgExport = $securityGroups | Select-Object DisplayName,PrimarySmtpAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}},RecipientTypeDetails
$sgExport | Export-Csv -Path (Join-Path $ExportPath "MailEnabledSecurityGroups-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($securityGroups.Count) mail-enabled security groups" -ForegroundColor Green

# 7. Export Mail Contacts
Write-Host "[7/9] Exporting mail contacts..." -ForegroundColor Cyan
$mailContacts = Get-MailContact -ResultSize Unlimited
$contactsExport = $mailContacts | Select-Object DisplayName,PrimarySmtpAddress,ExternalEmailAddress,@{N='EmailAddresses';E={$_.EmailAddresses -join ';'}}
$contactsExport | Export-Csv -Path (Join-Path $ExportPath "MailContacts-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($mailContacts.Count) mail contacts" -ForegroundColor Green

# 8. Export Transport Rules
Write-Host "[8/9] Exporting transport rules..." -ForegroundColor Cyan
$transportRules = Get-TransportRule
$rulesExport = $transportRules | Select-Object Name,State,Priority,Description,@{N='FromAddressContainsWords';E={$_.FromAddressContainsWords -join ';'}},@{N='SentToScope';E={$_.SentToScope}}
$rulesExport | Export-Csv -Path (Join-Path $ExportPath "TransportRules-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($transportRules.Count) transport rules" -ForegroundColor Green

# 9. Export Accepted Domains
Write-Host "[9/9] Exporting accepted domains..." -ForegroundColor Cyan
$acceptedDomains = Get-AcceptedDomain
$domainsExport = $acceptedDomains | Select-Object DomainName,DomainType,Default,EmailOnly
$domainsExport | Export-Csv -Path (Join-Path $ExportPath "AcceptedDomains-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($acceptedDomains.Count) accepted domains" -ForegroundColor Green

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`nExchange Online backup complete!" -ForegroundColor Cyan
Write-Host "Files saved to: $ExportPath" -ForegroundColor Green
