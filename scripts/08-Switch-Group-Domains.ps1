<#
.SYNOPSIS
    Switch group email addresses from old domain to new domain
.DESCRIPTION
    Updates email addresses for distribution groups, Microsoft 365 groups, and mail-enabled security groups
.PARAMETER OldDomain
    The old domain (e.g., olddomain.com)
.PARAMETER NewDomain
    The new domain (e.g., newdomain.com)
.PARAMETER TestMode
    Run in test mode without making changes (default: $true)
.EXAMPLE
    .\08-Switch-Group-Domains.ps1 -OldDomain "olddomain.com" -NewDomain "newdomain.com" -TestMode $true
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$true)]
    [string]$NewDomain,
    
    [Parameter(Mandatory=$false)]
    [bool]$TestMode = $true
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = "./Logs/GroupDomainSwitch-$timestamp.log"

# Create log directory
if (-not (Test-Path "./Logs")) {
    New-Item -ItemType Directory -Path "./Logs" -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $logPath -Value $logMessage
    Write-Host $logMessage
}

Write-Host "=== Group Domain Migration ===" -ForegroundColor Cyan
Write-Host "Old Domain: $OldDomain" -ForegroundColor Yellow
Write-Host "New Domain: $NewDomain" -ForegroundColor Yellow
Write-Host "Test Mode: $TestMode" -ForegroundColor $(if($TestMode){"Yellow"}else{"Red"})
Write-Host ""

if ($TestMode) {
    Write-Host "*** RUNNING IN TEST MODE - NO CHANGES WILL BE MADE ***" -ForegroundColor Yellow
    Write-Log "Running in TEST MODE"
} else {
    Write-Host "*** LIVE MODE - CHANGES WILL BE APPLIED ***" -ForegroundColor Red
    $confirmation = Read-Host "Are you sure you want to proceed? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled" -ForegroundColor Yellow
        exit
    }
    Write-Log "Running in LIVE MODE"
}

# Connect to Exchange Online
Write-Host "`nConnecting to Exchange Online..." -ForegroundColor Green
Connect-ExchangeOnline -ShowBanner:$false
Write-Log "Connected to Exchange Online"

# Get all distribution groups
Write-Host "`nIdentifying groups to migrate..." -ForegroundColor Cyan
Write-Log "Querying distribution groups"

$allGroups = Get-DistributionGroup -ResultSize Unlimited
$groupsToMigrate = $allGroups | Where-Object { 
    $_.PrimarySmtpAddress -like "*@${OldDomain}" -or 
    $_.EmailAddresses -like "*@${OldDomain}" 
}

$totalGroups = ($groupsToMigrate | Measure-Object).Count
Write-Host "Found $totalGroups groups to migrate" -ForegroundColor Yellow
Write-Log "Found $totalGroups groups to migrate"

if ($totalGroups -eq 0) {
    Write-Host "No groups found to migrate. Exiting." -ForegroundColor Yellow
    exit
}

# Migration counters
$successCount = 0
$failCount = 0

# Process each group
$counter = 0
foreach ($group in $groupsToMigrate) {
    $counter++
    $currentEmail = $group.PrimarySmtpAddress
    $groupName = $group.DisplayName
    $alias = $group.Alias
    $newEmail = "$alias@${NewDomain}"
    
    Write-Host "`n[$counter/$totalGroups] Processing: $groupName" -ForegroundColor Cyan
    Write-Host "  Current Email: $currentEmail" -ForegroundColor Gray
    Write-Log "Processing group: $groupName ($currentEmail)"
    
    try {
        if (-not $TestMode) {
            # Get current email addresses
            $emailAddresses = @($group.EmailAddresses)
            
            # Remove old primary SMTP
            $emailAddresses = $emailAddresses | Where-Object { $_ -notlike "SMTP:*@$OldDomain" }
            
            # Add new primary SMTP at the beginning
            $newPrimarySMTP = "SMTP:$alias@$NewDomain"
            $emailAddresses = @($newPrimarySMTP) + $emailAddresses
            
            # Add old domain as secondary alias if not already present
            $oldSecondary = "smtp:$alias@$OldDomain"
            if ($emailAddresses -notcontains $oldSecondary) {
                $emailAddresses += $oldSecondary
            }
            
            # Update the group with EmailAddresses only
            Write-Host "  Updating to: $newEmail" -ForegroundColor Gray
            Set-DistributionGroup -Identity $group.Identity -EmailAddresses $emailAddresses
            
            Write-Log "  Updated: $currentEmail -> $newEmail"
            Write-Host "  SUCCESS" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  TEST MODE: Would update to: $newEmail" -ForegroundColor Yellow
            Write-Host "  TEST MODE: Old email would be kept as alias" -ForegroundColor Yellow
            Write-Log "  TEST MODE: $currentEmail -> $newEmail"
            $successCount++
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Log "  ERROR processing $groupName : $_"
        $failCount++;
    }
    
    # Small delay to avoid throttling
    Start-Sleep -Milliseconds 500
}

# Summary
Write-Host "`n=== Migration Summary ===" -ForegroundColor Cyan
Write-Host "Total Groups: $totalGroups" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

Write-Log "Migration Summary - Total: $totalGroups, Success: $successCount, Failed: $failCount"

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`nLog file saved to: $logPath" -ForegroundColor Green
Write-Host "Group domain migration complete!" -ForegroundColor Cyan
