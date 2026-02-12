<#
.SYNOPSIS
    Backup Microsoft Teams configuration
.DESCRIPTION
    Exports all Teams, channels, members, and settings
.PARAMETER OldDomain
    The domain to backup (e.g., olddomain.com)
.PARAMETER ExportPath
    Path to export backup files
.EXAMPLE
    .\06-Backup-Teams.ps1 -OldDomain "olddomain.com" -ExportPath "C:\M365Migration\Backup"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$OldDomain,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\Backup\Teams"
)

# Create export directory
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

Write-Host "=== Microsoft Teams Backup ===" -ForegroundColor Cyan
Write-Host "Domain: $OldDomain" -ForegroundColor Yellow
Write-Host "Export Path: $ExportPath" -ForegroundColor Yellow
Write-Host ""

# Connect to Microsoft Teams
Write-Host "Connecting to Microsoft Teams..." -ForegroundColor Green
try {
    Connect-MicrosoftTeams
    Write-Host "  Connected successfully" -ForegroundColor Green
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    exit
}

# 1. Export All Teams
Write-Host "[1/5] Exporting all teams..." -ForegroundColor Cyan
$allTeams = Get-Team
$teamsExport = $allTeams | Select-Object GroupId,DisplayName,Description,Visibility,MailNickName,Archived
$teamsExport | Export-Csv -Path (Join-Path $ExportPath "AllTeams-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($allTeams.Count) teams" -ForegroundColor Green

# 2. Export Team Members
Write-Host "[2/5] Exporting team members..." -ForegroundColor Cyan
$teamMembers = @()
foreach ($team in $allTeams) {
    try {
        $members = Get-TeamUser -GroupId $team.GroupId
        foreach ($member in $members) {
            $teamMembers += [PSCustomObject]@{
                TeamName = $team.DisplayName
                TeamGroupId = $team.GroupId
                UserName = $member.Name
                UserUPN = $member.User
                Role = $member.Role
            }
        }
    } catch {
        Write-Host "  Warning: Could not retrieve members for $($team.DisplayName)" -ForegroundColor Yellow
    }
}
$teamMembers | Export-Csv -Path (Join-Path $ExportPath "TeamMembers-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($teamMembers.Count) team member assignments" -ForegroundColor Green

# 3. Export Team Channels
Write-Host "[3/5] Exporting team channels..." -ForegroundColor Cyan
$teamChannels = @()
foreach ($team in $allTeams) {
    try {
        $channels = Get-TeamChannel -GroupId $team.GroupId
        foreach ($channel in $channels) {
            $teamChannels += [PSCustomObject]@{
                TeamName = $team.DisplayName
                TeamGroupId = $team.GroupId
                ChannelId = $channel.Id
                ChannelDisplayName = $channel.DisplayName
                ChannelDescription = $channel.Description
                MembershipType = $channel.MembershipType
            }
        }
    } catch {
        Write-Host "  Warning: Could not retrieve channels for $($team.DisplayName)" -ForegroundColor Yellow
    }
}
$teamChannels | Export-Csv -Path (Join-Path $ExportPath "TeamChannels-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($teamChannels.Count) team channels" -ForegroundColor Green

# 4. Export Guest Users in Teams
Write-Host "[4/5] Exporting guest users..." -ForegroundColor Cyan
$guestUsers = @()
foreach ($team in $allTeams) {
    try {
        $members = Get-TeamUser -GroupId $team.GroupId -Role Guest
        foreach ($member in $members) {
            $guestUsers += [PSCustomObject]@{
                TeamName = $team.DisplayName
                TeamGroupId = $team.GroupId
                GuestName = $member.Name
                GuestUPN = $member.User
            }
        }
    } catch {
        Write-Host "  Warning: Could not retrieve guests for $($team.DisplayName)" -ForegroundColor Yellow
    }
}
$guestUsers | Export-Csv -Path (Join-Path $ExportPath "GuestUsers-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Exported $($guestUsers.Count) guest user assignments" -ForegroundColor Green

# 5. Export Teams with Old Domain
Write-Host "[5/5] Identifying teams using old domain..." -ForegroundColor Cyan
$teamsWithDomain = @()
foreach ($team in $allTeams) {
    $mailNickname = $team.MailNickName
    # Teams email is typically groupId@domain
    $teamMembers = Get-TeamUser -GroupId $team.GroupId | Where-Object { $_.User -like "*@${OldDomain}" }
    
    if ($teamMembers) {
        $teamsWithDomain += [PSCustomObject]@{
            TeamName = $team.DisplayName
            TeamGroupId = $team.GroupId
            MailNickName = $team.MailNickName
            MembersWithDomain = ($teamMembers | Measure-Object).Count
        }
    }
}
$teamsWithDomain | Export-Csv -Path (Join-Path $ExportPath "TeamsWithOldDomain-$timestamp.csv") -NoTypeInformation -Encoding UTF8
Write-Host "  Identified $($teamsWithDomain.Count) teams with members using old domain" -ForegroundColor Green

# Disconnect
Disconnect-MicrosoftTeams

Write-Host "`nMicrosoft Teams backup complete!" -ForegroundColor Cyan
Write-Host "Files saved to: $ExportPath" -ForegroundColor Green
