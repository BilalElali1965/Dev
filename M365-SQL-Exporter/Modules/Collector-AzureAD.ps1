<#
.SYNOPSIS
    Azure AD Data Collector for M365-SQL-Exporter

.DESCRIPTION
    Collects Azure Active Directory data including users, groups, devices,
    service principals, applications, administrative units, and roles.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

<#
.SYNOPSIS
    Exports Azure AD Users to database

.PARAMETER Connection
    Database connection

.PARAMETER IncludeSignInActivity
    Include sign-in activity data

.PARAMETER IncludeLicenseDetails
    Include license assignment details

.EXAMPLE
    Export-AzureADUsers -Connection $conn -IncludeSignInActivity $true
#>
function Export-AzureADUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeSignInActivity = $true,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeLicenseDetails = $true
    )

    try {
        Write-Host "`nExporting Azure AD Users..." -ForegroundColor Cyan

        # Create table if not exists
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AAD_Users')
BEGIN
    CREATE TABLE AAD_Users (
        Id NVARCHAR(100) PRIMARY KEY,
        DisplayName NVARCHAR(255),
        UserPrincipalName NVARCHAR(255),
        Mail NVARCHAR(255),
        JobTitle NVARCHAR(255),
        Department NVARCHAR(255),
        OfficeLocation NVARCHAR(255),
        MobilePhone NVARCHAR(50),
        BusinessPhones NVARCHAR(500),
        AccountEnabled BIT,
        UserType NVARCHAR(50),
        CreatedDateTime DATETIME2,
        LastSignInDateTime DATETIME2 NULL,
        LastNonInteractiveSignInDateTime DATETIME2 NULL,
        AssignedLicenses NVARCHAR(MAX),
        ProxyAddresses NVARCHAR(MAX),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_AAD_Users_UserPrincipalName ON AAD_Users(UserPrincipalName);
    CREATE INDEX IX_AAD_Users_DisplayName ON AAD_Users(DisplayName);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get users with sign-in activity if requested
        if ($IncludeSignInActivity) {
            $uri = "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,mail,jobTitle,department,officeLocation,mobilePhone,businessPhones,accountEnabled,userType,createdDateTime,signInActivity,assignedLicenses,proxyAddresses"
        }
        else {
            $uri = "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,mail,jobTitle,department,officeLocation,mobilePhone,businessPhones,accountEnabled,userType,createdDateTime,assignedLicenses,proxyAddresses"
        }

        Write-Verbose "Fetching users from Graph API..."
        $users = Get-GraphAllPages -Uri $uri

        if ($null -eq $users -or $users.Count -eq 0) {
            Write-Warning "No users found"
            return 0
        }

        Write-Host "  Retrieved $($users.Count) users from Azure AD" -ForegroundColor Gray

        # Clear existing data (for full export)
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE AAD_Users" -Connection $Connection | Out-Null

        # Prepare data for export
        $exportData = @()
        foreach ($user in $users) {
            $userObj = [PSCustomObject]@{
                Id                                 = $user.id
                DisplayName                        = $user.displayName
                UserPrincipalName                  = $user.userPrincipalName
                Mail                               = $user.mail
                JobTitle                           = $user.jobTitle
                Department                         = $user.department
                OfficeLocation                     = $user.officeLocation
                MobilePhone                        = $user.mobilePhone
                BusinessPhones                     = if ($user.businessPhones) { $user.businessPhones -join '; ' } else { $null }
                AccountEnabled                     = $user.accountEnabled
                UserType                           = $user.userType
                CreatedDateTime                    = $user.createdDateTime
                LastSignInDateTime                 = if ($user.signInActivity) { $user.signInActivity.lastSignInDateTime } else { $null }
                LastNonInteractiveSignInDateTime   = if ($user.signInActivity) { $user.signInActivity.lastNonInteractiveSignInDateTime } else { $null }
                AssignedLicenses                   = if ($user.assignedLicenses) { ($user.assignedLicenses | ConvertTo-Json -Compress) } else { $null }
                ProxyAddresses                     = if ($user.proxyAddresses) { $user.proxyAddresses -join '; ' } else { $null }
                ExportedAt                         = Get-Date
            }
            $exportData += $userObj
        }

        # Bulk insert
        $recordCount = Export-DataToTable -TableName "AAD_Users" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount users to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export Azure AD users: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports Azure AD Groups to database

.PARAMETER Connection
    Database connection

.EXAMPLE
    Export-AzureADGroups -Connection $conn
#>
function Export-AzureADGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting Azure AD Groups..." -ForegroundColor Cyan

        # Create table if not exists
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AAD_Groups')
BEGIN
    CREATE TABLE AAD_Groups (
        Id NVARCHAR(100) PRIMARY KEY,
        DisplayName NVARCHAR(255),
        Description NVARCHAR(MAX),
        MailEnabled BIT,
        SecurityEnabled BIT,
        MailNickname NVARCHAR(255),
        Mail NVARCHAR(255),
        GroupTypes NVARCHAR(500),
        Visibility NVARCHAR(50),
        CreatedDateTime DATETIME2,
        MemberCount INT NULL,
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_AAD_Groups_DisplayName ON AAD_Groups(DisplayName);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get groups
        $uri = "https://graph.microsoft.com/v1.0/groups?`$select=id,displayName,description,mailEnabled,securityEnabled,mailNickname,mail,groupTypes,visibility,createdDateTime"
        Write-Verbose "Fetching groups from Graph API..."
        $groups = Get-GraphAllPages -Uri $uri

        if ($null -eq $groups -or $groups.Count -eq 0) {
            Write-Warning "No groups found"
            return 0
        }

        Write-Host "  Retrieved $($groups.Count) groups from Azure AD" -ForegroundColor Gray

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE AAD_Groups" -Connection $Connection | Out-Null

        # Prepare data for export
        $exportData = @()
        $groupIndex = 0
        foreach ($group in $groups) {
            $groupIndex++
            if ($groupIndex % 10 -eq 0) {
                Write-Progress -Activity "Processing groups" -Status "$groupIndex of $($groups.Count)" -PercentComplete (($groupIndex / $groups.Count) * 100)
            }

            # Get member count
            $memberCount = $null
            try {
                $memberUri = "https://graph.microsoft.com/v1.0/groups/$($group.id)/members/`$count"
                $memberCountResponse = Invoke-GraphRequest -Uri $memberUri -Method GET
                $memberCount = $memberCountResponse
            }
            catch {
                Write-Verbose "Could not get member count for group $($group.displayName)"
            }

            $groupObj = [PSCustomObject]@{
                Id              = $group.id
                DisplayName     = $group.displayName
                Description     = $group.description
                MailEnabled     = $group.mailEnabled
                SecurityEnabled = $group.securityEnabled
                MailNickname    = $group.mailNickname
                Mail            = $group.mail
                GroupTypes      = if ($group.groupTypes) { $group.groupTypes -join '; ' } else { $null }
                Visibility      = $group.visibility
                CreatedDateTime = $group.createdDateTime
                MemberCount     = $memberCount
                ExportedAt      = Get-Date
            }
            $exportData += $groupObj
        }
        Write-Progress -Activity "Processing groups" -Completed

        # Bulk insert
        $recordCount = Export-DataToTable -TableName "AAD_Groups" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount groups to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export Azure AD groups: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports Azure AD Devices to database

.PARAMETER Connection
    Database connection

.EXAMPLE
    Export-AzureADDevices -Connection $conn
#>
function Export-AzureADDevices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting Azure AD Devices..." -ForegroundColor Cyan

        # Create table if not exists
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AAD_Devices')
BEGIN
    CREATE TABLE AAD_Devices (
        Id NVARCHAR(100) PRIMARY KEY,
        DisplayName NVARCHAR(255),
        DeviceId NVARCHAR(100),
        OperatingSystem NVARCHAR(100),
        OperatingSystemVersion NVARCHAR(100),
        IsCompliant BIT,
        IsManaged BIT,
        TrustType NVARCHAR(50),
        AccountEnabled BIT,
        ApproximateLastSignInDateTime DATETIME2 NULL,
        RegistrationDateTime DATETIME2,
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_AAD_Devices_DisplayName ON AAD_Devices(DisplayName);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get devices
        $uri = "https://graph.microsoft.com/v1.0/devices?`$select=id,displayName,deviceId,operatingSystem,operatingSystemVersion,isCompliant,isManaged,trustType,accountEnabled,approximateLastSignInDateTime,registrationDateTime"
        Write-Verbose "Fetching devices from Graph API..."
        $devices = Get-GraphAllPages -Uri $uri

        if ($null -eq $devices -or $devices.Count -eq 0) {
            Write-Warning "No devices found"
            return 0
        }

        Write-Host "  Retrieved $($devices.Count) devices from Azure AD" -ForegroundColor Gray

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE AAD_Devices" -Connection $Connection | Out-Null

        # Prepare data for export
        $exportData = @()
        foreach ($device in $devices) {
            $deviceObj = [PSCustomObject]@{
                Id                             = $device.id
                DisplayName                    = $device.displayName
                DeviceId                       = $device.deviceId
                OperatingSystem                = $device.operatingSystem
                OperatingSystemVersion         = $device.operatingSystemVersion
                IsCompliant                    = $device.isCompliant
                IsManaged                      = $device.isManaged
                TrustType                      = $device.trustType
                AccountEnabled                 = $device.accountEnabled
                ApproximateLastSignInDateTime  = $device.approximateLastSignInDateTime
                RegistrationDateTime           = $device.registrationDateTime
                ExportedAt                     = Get-Date
            }
            $exportData += $deviceObj
        }

        # Bulk insert
        $recordCount = Export-DataToTable -TableName "AAD_Devices" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount devices to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export Azure AD devices: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports Azure AD Service Principals to database

.PARAMETER Connection
    Database connection

.EXAMPLE
    Export-AzureADServicePrincipals -Connection $conn
#>
function Export-AzureADServicePrincipals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting Azure AD Service Principals..." -ForegroundColor Cyan

        # Create table if not exists
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AAD_ServicePrincipals')
BEGIN
    CREATE TABLE AAD_ServicePrincipals (
        Id NVARCHAR(100) PRIMARY KEY,
        AppId NVARCHAR(100),
        DisplayName NVARCHAR(255),
        ServicePrincipalType NVARCHAR(100),
        AccountEnabled BIT,
        AppRoleAssignmentRequired BIT,
        Homepage NVARCHAR(500),
        PublisherName NVARCHAR(255),
        SignInAudience NVARCHAR(100),
        Tags NVARCHAR(MAX),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_AAD_ServicePrincipals_DisplayName ON AAD_ServicePrincipals(DisplayName);
    CREATE INDEX IX_AAD_ServicePrincipals_AppId ON AAD_ServicePrincipals(AppId);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get service principals
        $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=id,appId,displayName,servicePrincipalType,accountEnabled,appRoleAssignmentRequired,homepage,publisherName,signInAudience,tags"
        Write-Verbose "Fetching service principals from Graph API..."
        $servicePrincipals = Get-GraphAllPages -Uri $uri

        if ($null -eq $servicePrincipals -or $servicePrincipals.Count -eq 0) {
            Write-Warning "No service principals found"
            return 0
        }

        Write-Host "  Retrieved $($servicePrincipals.Count) service principals from Azure AD" -ForegroundColor Gray

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE AAD_ServicePrincipals" -Connection $Connection | Out-Null

        # Prepare data for export
        $exportData = @()
        foreach ($sp in $servicePrincipals) {
            $spObj = [PSCustomObject]@{
                Id                          = $sp.id
                AppId                       = $sp.appId
                DisplayName                 = $sp.displayName
                ServicePrincipalType        = $sp.servicePrincipalType
                AccountEnabled              = $sp.accountEnabled
                AppRoleAssignmentRequired   = $sp.appRoleAssignmentRequired
                Homepage                    = $sp.homepage
                PublisherName               = $sp.publisherName
                SignInAudience              = $sp.signInAudience
                Tags                        = if ($sp.tags) { $sp.tags -join '; ' } else { $null }
                ExportedAt                  = Get-Date
            }
            $exportData += $spObj
        }

        # Bulk insert
        $recordCount = Export-DataToTable -TableName "AAD_ServicePrincipals" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount service principals to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export Azure AD service principals: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports all Azure AD components

.PARAMETER Connection
    Database connection

.PARAMETER IncludeSignInActivity
    Include sign-in activity for users

.EXAMPLE
    Export-AllAzureADData -Connection $conn
#>
function Export-AllAzureADData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection,

        [Parameter(Mandatory = $false)]
        [bool]$IncludeSignInActivity = $true
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure AD Data Export" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $totalRecords = 0

    # Export Users
    $userCount = Export-AzureADUsers -Connection $Connection -IncludeSignInActivity $IncludeSignInActivity
    if ($userCount -gt 0) { $totalRecords += $userCount }

    # Export Groups
    $groupCount = Export-AzureADGroups -Connection $Connection
    if ($groupCount -gt 0) { $totalRecords += $groupCount }

    # Export Devices
    $deviceCount = Export-AzureADDevices -Connection $Connection
    if ($deviceCount -gt 0) { $totalRecords += $deviceCount }

    # Export Service Principals
    $spCount = Export-AzureADServicePrincipals -Connection $Connection
    if ($spCount -gt 0) { $totalRecords += $spCount }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Azure AD Export Complete" -ForegroundColor Cyan
    Write-Host "Total Records: $totalRecords" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    return $totalRecords
}

# Export module functions
Export-ModuleMember -Function @(
    'Export-AzureADUsers',
    'Export-AzureADGroups',
    'Export-AzureADDevices',
    'Export-AzureADServicePrincipals',
    'Export-AllAzureADData'
)
