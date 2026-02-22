<#
.SYNOPSIS
    Microsoft Teams Data Collector for M365-SQL-Exporter

.DESCRIPTION
    Collects Microsoft Teams data including teams, channels, members, and settings.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
#>

#Requires -Version 5.1

<#
.SYNOPSIS
    Exports Teams to database
#>
function Export-TeamsData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting Microsoft Teams..." -ForegroundColor Cyan

        # Create Teams table
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Teams_Teams')
BEGIN
    CREATE TABLE Teams_Teams (
        Id NVARCHAR(100) PRIMARY KEY,
        DisplayName NVARCHAR(255),
        Description NVARCHAR(MAX),
        Visibility NVARCHAR(50),
        IsArchived BIT,
        CreatedDateTime DATETIME2,
        WebUrl NVARCHAR(500),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_Teams_Teams_DisplayName ON Teams_Teams(DisplayName);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get all teams
        $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')"
        Write-Verbose "Fetching teams from Graph API..."
        $teams = Get-GraphAllPages -Uri $uri

        if ($null -eq $teams -or $teams.Count -eq 0) {
            Write-Warning "No teams found"
            return 0
        }

        Write-Host "  Retrieved $($teams.Count) teams" -ForegroundColor Gray

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE Teams_Teams" -Connection $Connection | Out-Null

        # Prepare data
        $exportData = @()
        foreach ($team in $teams) {
            # Get team details
            $teamDetails = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/teams/$($team.id)" -Method GET
            
            $teamObj = [PSCustomObject]@{
                Id              = $team.id
                DisplayName     = $team.displayName
                Description     = $team.description
                Visibility      = $team.visibility
                IsArchived      = if ($teamDetails) { $teamDetails.isArchived } else { $false }
                CreatedDateTime = $team.createdDateTime
                WebUrl          = if ($teamDetails) { $teamDetails.webUrl } else { $null }
                ExportedAt      = Get-Date
            }
            $exportData += $teamObj
        }

        $recordCount = Export-DataToTable -TableName "Teams_Teams" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount teams to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export Teams data: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports SharePoint sites to database
#>
function Export-SharePointSites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting SharePoint Sites..." -ForegroundColor Cyan

        # Create table
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SharePoint_Sites')
BEGIN
    CREATE TABLE SharePoint_Sites (
        Id NVARCHAR(100) PRIMARY KEY,
        Name NVARCHAR(255),
        DisplayName NVARCHAR(255),
        WebUrl NVARCHAR(500),
        Description NVARCHAR(MAX),
        CreatedDateTime DATETIME2,
        LastModifiedDateTime DATETIME2,
        SiteCollectionHostname NVARCHAR(255),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_SharePoint_Sites_Name ON SharePoint_Sites(Name);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get sites
        $uri = "https://graph.microsoft.com/v1.0/sites?`$select=id,name,displayName,webUrl,description,createdDateTime,lastModifiedDateTime,siteCollection"
        Write-Verbose "Fetching SharePoint sites from Graph API..."
        $sites = Get-GraphAllPages -Uri $uri

        if ($null -eq $sites -or $sites.Count -eq 0) {
            Write-Warning "No SharePoint sites found"
            return 0
        }

        Write-Host "  Retrieved $($sites.Count) sites" -ForegroundColor Gray

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE SharePoint_Sites" -Connection $Connection | Out-Null

        # Prepare data
        $exportData = @()
        foreach ($site in $sites) {
            $siteObj = [PSCustomObject]@{
                Id                      = $site.id
                Name                    = $site.name
                DisplayName             = $site.displayName
                WebUrl                  = $site.webUrl
                Description             = $site.description
                CreatedDateTime         = $site.createdDateTime
                LastModifiedDateTime    = $site.lastModifiedDateTime
                SiteCollectionHostname  = if ($site.siteCollection) { $site.siteCollection.hostname } else { $null }
                ExportedAt              = Get-Date
            }
            $exportData += $siteObj
        }

        $recordCount = Export-DataToTable -TableName "SharePoint_Sites" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount SharePoint sites to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export SharePoint sites: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports OneDrive drives to database
#>
function Export-OneDriveDrives {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting OneDrive Drives..." -ForegroundColor Cyan

        # Create table
        $createTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'OneDrive_Drives')
BEGIN
    CREATE TABLE OneDrive_Drives (
        Id NVARCHAR(100) PRIMARY KEY,
        Name NVARCHAR(255),
        DriveType NVARCHAR(50),
        OwnerUserPrincipalName NVARCHAR(255),
        OwnerDisplayName NVARCHAR(255),
        CreatedDateTime DATETIME2,
        LastModifiedDateTime DATETIME2,
        WebUrl NVARCHAR(500),
        QuotaTotal BIGINT,
        QuotaUsed BIGINT,
        QuotaRemaining BIGINT,
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_OneDrive_Drives_OwnerUserPrincipalName ON OneDrive_Drives(OwnerUserPrincipalName);
END
"@
        Invoke-SqlNonQuery -Query $createTableQuery -Connection $Connection | Out-Null

        # Get all users first
        $users = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,displayName"
        
        if ($null -eq $users -or $users.Count -eq 0) {
            Write-Warning "No users found"
            return 0
        }

        Write-Host "  Processing OneDrive drives for $($users.Count) users..." -ForegroundColor Gray

        # Prepare data
        $exportData = @()
        $driveCount = 0
        
        foreach ($user in $users) {
            try {
                $drive = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/users/$($user.id)/drive" -Method GET
                
                if ($null -ne $drive) {
                    $driveCount++
                    $driveObj = [PSCustomObject]@{
                        Id                      = $drive.id
                        Name                    = $drive.name
                        DriveType               = $drive.driveType
                        OwnerUserPrincipalName  = $user.userPrincipalName
                        OwnerDisplayName        = $user.displayName
                        CreatedDateTime         = $drive.createdDateTime
                        LastModifiedDateTime    = $drive.lastModifiedDateTime
                        WebUrl                  = $drive.webUrl
                        QuotaTotal              = if ($drive.quota) { $drive.quota.total } else { 0 }
                        QuotaUsed               = if ($drive.quota) { $drive.quota.used } else { 0 }
                        QuotaRemaining          = if ($drive.quota) { $drive.quota.remaining } else { 0 }
                        ExportedAt              = Get-Date
                    }
                    $exportData += $driveObj
                }
            }
            catch {
                Write-Verbose "Could not get drive for user $($user.userPrincipalName)"
            }
        }

        if ($exportData.Count -eq 0) {
            Write-Warning "No OneDrive drives found"
            return 0
        }

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE OneDrive_Drives" -Connection $Connection | Out-Null

        $recordCount = Export-DataToTable -TableName "OneDrive_Drives" -Data $exportData -Connection $Connection

        Write-Host "✓ Exported $recordCount OneDrive drives to database" -ForegroundColor Green
        return $recordCount
    }
    catch {
        Write-Error "Failed to export OneDrive drives: $_"
        return -1
    }
}

<#
.SYNOPSIS
    Exports Planner plans and tasks to database
#>
function Export-PlannerData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        Write-Host "`nExporting Planner Plans..." -ForegroundColor Cyan

        # Create Plans table
        $createPlansTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Planner_Plans')
BEGIN
    CREATE TABLE Planner_Plans (
        Id NVARCHAR(100) PRIMARY KEY,
        Title NVARCHAR(255),
        OwnerGroupId NVARCHAR(100),
        CreatedDateTime DATETIME2,
        CreatedByUserId NVARCHAR(100),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_Planner_Plans_Title ON Planner_Plans(Title);
END
"@
        Invoke-SqlNonQuery -Query $createPlansTableQuery -Connection $Connection | Out-Null

        # Create Tasks table
        $createTasksTableQuery = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Planner_Tasks')
BEGIN
    CREATE TABLE Planner_Tasks (
        Id NVARCHAR(100) PRIMARY KEY,
        PlanId NVARCHAR(100),
        BucketId NVARCHAR(100),
        Title NVARCHAR(255),
        PercentComplete INT,
        Priority INT,
        DueDateTime DATETIME2 NULL,
        CreatedDateTime DATETIME2,
        CompletedDateTime DATETIME2 NULL,
        AssignedToUserIds NVARCHAR(MAX),
        ExportedAt DATETIME2 DEFAULT GETDATE()
    );
    CREATE INDEX IX_Planner_Tasks_PlanId ON Planner_Tasks(PlanId);
    CREATE INDEX IX_Planner_Tasks_Title ON Planner_Tasks(Title);
END
"@
        Invoke-SqlNonQuery -Query $createTasksTableQuery -Connection $Connection | Out-Null

        # Get all groups to find plans
        $groups = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/groups?`$select=id,displayName"
        
        Write-Host "  Processing Planner plans for $($groups.Count) groups..." -ForegroundColor Gray

        $allPlans = @()
        $allTasks = @()
        
        foreach ($group in $groups) {
            try {
                $plans = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)/planner/plans"
                
                if ($null -ne $plans -and $plans.Count -gt 0) {
                    foreach ($plan in $plans) {
                        $planObj = [PSCustomObject]@{
                            Id                = $plan.id
                            Title             = $plan.title
                            OwnerGroupId      = $group.id
                            CreatedDateTime   = $plan.createdDateTime
                            CreatedByUserId   = if ($plan.createdBy) { $plan.createdBy.user.id } else { $null }
                            ExportedAt        = Get-Date
                        }
                        $allPlans += $planObj

                        # Get tasks for this plan
                        $tasks = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/planner/plans/$($plan.id)/tasks"
                        
                        if ($null -ne $tasks -and $tasks.Count -gt 0) {
                            foreach ($task in $tasks) {
                                $taskObj = [PSCustomObject]@{
                                    Id                  = $task.id
                                    PlanId              = $task.planId
                                    BucketId            = $task.bucketId
                                    Title               = $task.title
                                    PercentComplete     = $task.percentComplete
                                    Priority            = $task.priority
                                    DueDateTime         = $task.dueDateTime
                                    CreatedDateTime     = $task.createdDateTime
                                    CompletedDateTime   = $task.completedDateTime
                                    AssignedToUserIds   = if ($task.assignments) { ($task.assignments.PSObject.Properties.Name -join '; ') } else { $null }
                                    ExportedAt          = Get-Date
                                }
                                $allTasks += $taskObj
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Could not get plans for group $($group.displayName)"
            }
        }

        # Clear existing data
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE Planner_Plans" -Connection $Connection | Out-Null
        Invoke-SqlNonQuery -Query "TRUNCATE TABLE Planner_Tasks" -Connection $Connection | Out-Null

        # Export plans
        $planCount = 0
        if ($allPlans.Count -gt 0) {
            $planCount = Export-DataToTable -TableName "Planner_Plans" -Data $allPlans -Connection $Connection
        }

        # Export tasks
        $taskCount = 0
        if ($allTasks.Count -gt 0) {
            $taskCount = Export-DataToTable -TableName "Planner_Tasks" -Data $allTasks -Connection $Connection
        }

        Write-Host "✓ Exported $planCount plans and $taskCount tasks to database" -ForegroundColor Green
        return ($planCount + $taskCount)
    }
    catch {
        Write-Error "Failed to export Planner data: $_"
        return -1
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Export-TeamsData',
    'Export-SharePointSites',
    'Export-OneDriveDrives',
    'Export-PlannerData'
)
