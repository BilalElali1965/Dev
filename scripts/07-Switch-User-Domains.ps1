<#
.SYNOPSIS
    Switch user UPNs and email addresses from old domain to new domain
.DESCRIPTION
    Updates User Principal Names and email addresses for users in Azure AD and Exchange Online.
    This script will:
    - Change UserPrincipalName from old domain to new domain
    - Update primary SMTP address to new domain
    - Replace ALL email aliases containing old domain with new domain
    - Preserve all other email addresses unchanged
.PARAMETER OldDomain
    The old domain (e.g., olddomain.com)
.PARAMETER NewDomain
    The new domain (e.g., newdomain.com)
.PARAMETER TestMode
    Run in test mode without making changes (default: $true)
.PARAMETER UsersFile
    Optional CSV file with specific users to migrate (must have UserPrincipalName column)
.EXAMPLE
    .\07-Switch-User-Domains.ps1 -OldDomain "olddomain.com" -NewDomain "newdomain.com" -TestMode $true
.EXAMPLE
    .\07-Switch-User-Domains.ps1 -OldDomain "olddomain.com" -NewDomain "newdomain.com" -UsersFile "users.csv" -TestMode $false
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$true)]
    [string]$NewDomain,
    
    [Parameter(Mandatory=$false)]
    [bool]$TestMode = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$UsersFile = ""
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = "./Logs/UserDomainSwitch-$timestamp.log"

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

Write-Host "=== User Domain Migration ===" -ForegroundColor Cyan
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

# Connect to Microsoft Graph
Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Green
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome
Write-Log "Connected to Microsoft Graph"

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Green
Connect-ExchangeOnline -ShowBanner:$false
Write-Log "Connected to Exchange Online"

# Get users to migrate
Write-Host "`nIdentifying users to migrate..." -ForegroundColor Cyan
if ($UsersFile -and (Test-Path $UsersFile)) {
    Write-Log "Loading users from file: $UsersFile"
    $userList = Import-Csv $UsersFile
    $usersToMigrate = @()
    foreach ($user in $userList) {
        $mgUser = Get-MgUser -UserId $user.UserPrincipalName -ErrorAction SilentlyContinue
        if ($mgUser) {
            $usersToMigrate += $mgUser
        }
    }
} else {
    Write-Log "Querying all users with domain: $OldDomain"
    $allUsers = Get-MgUser -All -Property Id,UserPrincipalName,Mail,ProxyAddresses
    $usersToMigrate = $allUsers | Where-Object { 
        $_.UserPrincipalName -like "*@\$OldDomain" 
    }
}

totalUsers = ($usersToMigrate | Measure-Object).Count
Write-Host "Found $totalUsers users to migrate" -ForegroundColor Yellow
Write-Log "Found $totalUsers users to migrate"

if ($totalUsers -eq 0) {
    Write-Host "No users found to migrate. Exiting." -ForegroundColor Yellow
    exit
}

# Migration counters
$successCount = 0
$failCount = 0
$skippedCount = 0

# Process each user
$counter = 0
foreach ($user in $usersToMigrate) {
    $counter++
    $currentUPN = $user.UserPrincipalName
    $username = $currentUPN.Split('@')[0]
    $newUPN = "$username@$NewDomain"
    
    Write-Host "`n[$counter/$totalUsers] Processing: $currentUPN" -ForegroundColor Cyan
    Write-Log "Processing user: $currentUPN"
    
    try {
        if (-not $TestMode) {
            # Update UPN in Azure AD
            Write-Host "  Updating UPN to: $newUPN" -ForegroundColor Gray
            Update-MgUser -UserId $user.Id -UserPrincipalName $newUPN
            Write-Log "  Updated UPN: $currentUPN -> $newUPN"
            
            # Wait for synchronization
            Start-Sleep -Seconds 2
            
            # Update primary email in Exchange
            $mailbox = Get-Mailbox -Identity $newUPN -ErrorAction SilentlyContinue
            if ($mailbox) {
                Write-Host "  Updating email addresses (primary and all aliases)" -ForegroundColor Gray
                
                # Get current email addresses
                $emailAddresses = @($mailbox.EmailAddresses)
                
                # Replace ALL addresses with old domain to new domain
                $updatedAddresses = @()
                foreach ($addr in $emailAddresses) {
                    if ($addr -like "*@\$OldDomain") {
                        # Replace old domain with new domain, preserve prefix type (SMTP: vs smtp:)
                        $newAddr = $addr -replace "@\$OldDomain", "@\$NewDomain"
                        $updatedAddresses += $newAddr
                        Write-Host "    Converted: $addr -> $newAddr" -ForegroundColor DarkGray
                    } else {
                        # Keep addresses from other domains unchanged
                        $updatedAddresses += $addr
                    }
                }
                
                # Ensure new primary is set correctly (uppercase SMTP:)
                $newPrimarySMTP = "SMTP:$username@$NewDomain"
                $updatedAddresses = $updatedAddresses | Where-Object { $_ -ne $newPrimarySMTP }
                $updatedAddresses = @($newPrimarySMTP) + $updatedAddresses
                
                Set-Mailbox -Identity $newUPN -EmailAddresses $updatedAddresses -WindowsEmailAddress "$username@$NewDomain"
                Write-Log "  Updated email addresses for: $newUPN (primary + all aliases)"
            }
            
            Write-Host "  SUCCESS" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  TEST MODE: Would update UPN to: $newUPN" -ForegroundColor Yellow
            Write-Host "  TEST MODE: Would update primary email to: $username@$NewDomain" -ForegroundColor Yellow
            
            # Show what would be changed
            $mailbox = Get-Mailbox -Identity $currentUPN -ErrorAction SilentlyContinue
            if ($mailbox) {
                Write-Host "  TEST MODE: Current aliases to be converted:" -ForegroundColor Yellow
                foreach ($addr in $mailbox.EmailAddresses) {
                    if ($addr -like "*@\$OldDomain") {
                        $newAddr = $addr -replace "@\$OldDomain", "@\$NewDomain"
                        Write-Host "    $addr -> $newAddr" -ForegroundColor DarkYellow
                    }
                }
            }
            
            Write-Log "  TEST MODE: $currentUPN -> $newUPN"
            $successCount++
        }
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Log "  ERROR processing $currentUPN : $_"
        $failCount++
    }
}

# Summary
Write-Host "`n=== Migration Summary ===" -ForegroundColor Cyan
Write-Host "Total Users: $totalUsers" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Skipped: $skippedCount" -ForegroundColor Yellow

Write-Log "Migration Summary - Total: $totalUsers, Success: $successCount, Failed: $failCount, Skipped: $skippedCount"

# Disconnect
Disconnect-MgGraph | Out-Null
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`nLog file saved to: $logPath" -ForegroundColor Green
Write-Host "User domain migration complete!" -ForegroundColor Cyan
