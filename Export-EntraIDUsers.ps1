<#
.SYNOPSIS
    Export Entra ID (Azure AD) users to CSV with comprehensive attributes.
.DESCRIPTION
    This script exports user data from Microsoft Entra ID including:
    - Source, Employment Status, Display Name, Last/First Name
    - UPN, Title, Department, Manager
    - Email, Phone, Physical Address
    - Language Preference, Account Status, Blocked Credentials
    - Account Type, Mailbox Type, Assigned Licenses
    - OneDrive Status
.PARAMETER OutputPath
    The path where the CSV file will be saved. Default: EntraIDUsers_YYYYMMDD_HHMMSS.csv
.EXAMPLE
    .\Export-EntraIDUsers.ps1
    .\Export-EntraIDUsers.ps1 -OutputPath "C:\Exports\Users.csv"
.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions needed: User.Read.All, Directory.Read.All, Organization.Read.All, Files.Read.All
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "EntraIDUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Check if Microsoft Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Error "Microsoft.Graph module is not installed. Please run: Install-Module Microsoft.Graph -Scope CurrentUser"
    exit
}

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    # Connect to Microsoft Graph with required permissions
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Organization.Read.All", "Files.Read.All" -NoWelcome
    Write-Host "Connected successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit
}

Write-Host "Retrieving users from Entra ID..." -ForegroundColor Cyan

# Get all users with extended properties
$users = Get-MgUser -All -Property @(
    'Id',
    'UserPrincipalName',
    'DisplayName',
    'GivenName',
    'Surname',
    'Mail',
    'JobTitle',
    'Department',
    'OfficeLocation',
    'StreetAddress',
    'City',
    'State',
    'PostalCode',
    'Country',
    'MobilePhone',
    'BusinessPhones',
    'PreferredLanguage',
    'AccountEnabled',
    'OnPremisesSyncEnabled',
    'EmployeeType',
    'UserType',
    'AssignedLicenses'
)

Write-Host "Found $($users.Count) users. Processing data..." -ForegroundColor Cyan

# Get all available SKUs once (more efficient than individual lookups)
Write-Host "Retrieving license SKU information..." -ForegroundColor Cyan
$allSkus = Get-MgSubscribedSku -All
$skuHashTable = @{}
foreach ($sku in $allSkus) {
    $skuHashTable[$sku.SkuId] = $sku.SkuPartNumber
}

# License SKU friendly names mapping
$licenseNames = @{
    'O365_BUSINESS_ESSENTIALS' = 'Office 365 Business Essentials'
    'O365_BUSINESS_PREMIUM' = 'Office 365 Business Premium'
    'DESKLESSPACK' = 'Office 365 F3'
    'DESKLESSWOFFPACK' = 'Office 365 F3'
    'ENTERPRISEPACK' = 'Office 365 E3'
    'ENTERPRISEPREMIUM' = 'Office 365 E5'
    'ENTERPRISEPREMIUM_NOPSTNCONF' = 'Office 365 E5 Without Audio Conferencing'
    'SPE_E3' = 'Microsoft 365 E3'
    'SPE_E5' = 'Microsoft 365 E5'
    'MICROSOFT365_F1' = 'Microsoft 365 F1'
    'MICROSOFT365_F3' = 'Microsoft 365 F3'
    'EXCHANGESTANDARD' = 'Exchange Online Plan 1'
    'EXCHANGEENTERPRISE' = 'Exchange Online Plan 2'
    'POWER_BI_STANDARD' = 'Power BI Free'
    'POWER_BI_PRO' = 'Power BI Pro'
    'PROJECTPROFESSIONAL' = 'Project Plan 3'
    'PROJECTESSENTIALS' = 'Project Plan 1'
    'VISIOCLIENT' = 'Visio Plan 2'
    'TEAMS_EXPLORATORY' = 'Microsoft Teams Exploratory'
    'STREAM' = 'Microsoft Stream'
    'AAD_PREMIUM' = 'Azure Active Directory Premium P1'
    'AAD_PREMIUM_P2' = 'Azure Active Directory Premium P2'
    'INTUNE_A' = 'Microsoft Intune'
    'FLOW_FREE' = 'Microsoft Power Automate Free'
    'POWERAPPS_VIRAL' = 'Microsoft Power Apps Plan 2 Trial'
}

# Create export array
$exportData = @()
$counter = 0

foreach ($user in $users) {
    $counter++
    Write-Progress -Activity "Processing users" -Status "Processing $counter of $($users.Count)" -PercentComplete (($counter / $users.Count) * 100)
    
    # Get manager information
    $manager = $null
    try {
        $manager = Get-MgUserManager -UserId $user.Id -ErrorAction SilentlyContinue
    }
    catch {
        # Manager not set
    }
    
    # Determine source (Cloud vs On-Premises Synced)
    $source = if ($user.OnPremisesSyncEnabled -eq $true) { "On-Premises Synced" } else { "Cloud" }
    
    # Get assigned licenses using hash table lookup
    $assignedLicenses = @()
    if ($user.AssignedLicenses -and $user.AssignedLicenses.Count -gt 0) {
        foreach ($license in $user.AssignedLicenses) {
            if ($skuHashTable.ContainsKey($license.SkuId)) {
                $skuPartNumber = $skuHashTable[$license.SkuId]
                $friendlyName = if ($licenseNames.ContainsKey($skuPartNumber)) { 
                    $licenseNames[$skuPartNumber] 
                } else { 
                    $skuPartNumber 
                }
                $assignedLicenses += $friendlyName
            }
        }
    }
    $licenseString = if ($assignedLicenses.Count -gt 0) { $assignedLicenses -join "; " } else { "No Licenses" }
    
    # Determine mailbox type
    $mailboxType = "No Mailbox"
    if ($user.Mail) {
        if ($user.UserType -eq "Guest") {
            $mailboxType = "Guest Mailbox"
        } else {
            $mailboxType = "User Mailbox"
        }
    }
    
    # Check OneDrive status
    $hasOneDrive = "No"
    try {
        $drive = Get-MgUserDrive -UserId $user.Id -ErrorAction SilentlyContinue
        if ($drive) {
            $hasOneDrive = "Yes"
        }
    } catch {
        # OneDrive not provisioned or accessible
    }
    
    # Construct physical address
    $physicalAddress = @()
    if ($user.StreetAddress) { $physicalAddress += $user.StreetAddress }
    if ($user.City) { $physicalAddress += $user.City }
    if ($user.State) { $physicalAddress += $user.State }
    if ($user.PostalCode) { $physicalAddress += $user.PostalCode }
    if ($user.Country) { $physicalAddress += $user.Country }
    $addressString = if ($physicalAddress.Count -gt 0) { $physicalAddress -join ", " } else { "" }
    
    # Account status
    $accountStatus = if ($user.AccountEnabled) { "Enabled" } else { "Disabled" }
    
    # Blocked credentials (approximation based on account status)
    $blockedCredentials = if (-not $user.AccountEnabled) { "Yes" } else { "No" }
    
    # Phone number (prioritize mobile, then business)
    $phoneNumber = if ($user.MobilePhone) { 
        $user.MobilePhone 
    } elseif ($user.BusinessPhones.Count -gt 0) { 
        $user.BusinessPhones[0] 
    } else { 
        "" 
    }
    
    # Create export object
    $exportData += [PSCustomObject]@{
        'Source' = $source
        'Employment Status' = if ($user.EmployeeType) { $user.EmployeeType } else { "Not Set" }
        'Display Name' = $user.DisplayName
        'Last Name' = $user.Surname
        'First Name' = $user.GivenName
        'UPN' = $user.UserPrincipalName
        'Title' = $user.JobTitle
        'Department' = $user.Department
        'Manager' = if ($manager) { $manager.AdditionalProperties.displayName } else { "" }
        'Email Address' = $user.Mail
        'Phone Number' = $phoneNumber
        'Physical Delivery Address' = $addressString
        'Language Preference' = $user.PreferredLanguage
        'Account Status' = $accountStatus
        'Blocked Credentials' = $blockedCredentials
        'Account Type' = $user.UserType
        'Mailbox Type' = $mailboxType
        'Has OneDrive' = $hasOneDrive
        'Assigned Licenses' = $licenseString
    }
}

Write-Progress -Activity "Processing users" -Completed

# Export to CSV
Write-Host "Exporting to CSV..." -ForegroundColor Cyan
try {
    $exportData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Host "Export completed successfully!" -ForegroundColor Green
    Write-Host "File saved to: $OutputPath" -ForegroundColor Green
    Write-Host "Total users exported: $($exportData.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to export CSV: $_"
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph | Out-Null
Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Cyan
