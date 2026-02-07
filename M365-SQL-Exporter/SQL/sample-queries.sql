-- ================================================================
-- M365-SQL-Exporter Sample Queries
-- Version: 1.0.0
-- Description: Useful queries for reporting and analysis
-- ================================================================

USE M365ExportDB;
GO

-- ================================================================
-- Export History Queries
-- ================================================================

-- View recent exports
SELECT TOP 10
    ComponentName,
    ExportMode,
    StartTime,
    EndTime,
    DATEDIFF(SECOND, StartTime, EndTime) AS DurationSeconds,
    Status,
    RecordsExported,
    ExecutedBy
FROM ExportHistory
ORDER BY StartTime DESC;
GO

-- Export summary by component
SELECT
    ComponentName,
    COUNT(*) AS ExportCount,
    SUM(RecordsExported) AS TotalRecords,
    AVG(DATEDIFF(SECOND, StartTime, EndTime)) AS AvgDurationSeconds,
    MAX(EndTime) AS LastExportTime
FROM ExportHistory
WHERE Status = 'Completed'
GROUP BY ComponentName
ORDER BY ComponentName;
GO

-- Failed exports
SELECT
    ComponentName,
    StartTime,
    ErrorMessage,
    ExecutedBy
FROM ExportHistory
WHERE Status = 'Failed'
ORDER BY StartTime DESC;
GO

-- ================================================================
-- Audit Log Queries
-- ================================================================

-- Recent audit entries
SELECT TOP 100
    Timestamp,
    Category,
    Action,
    EntityType,
    Details,
    ExecutedBy
FROM AuditLog
ORDER BY Timestamp DESC;
GO

-- Audit summary by category
SELECT
    Category,
    COUNT(*) AS EntryCount,
    MIN(Timestamp) AS FirstEntry,
    MAX(Timestamp) AS LastEntry
FROM AuditLog
GROUP BY Category
ORDER BY EntryCount DESC;
GO

-- API requests audit
SELECT
    Timestamp,
    Details,
    ExecutedBy
FROM AuditLog
WHERE Category = 'API' AND Action = 'GraphAPIRequest'
ORDER BY Timestamp DESC;
GO

-- ================================================================
-- Azure AD User Queries
-- ================================================================

-- Active users summary
SELECT
    COUNT(*) AS TotalUsers,
    SUM(CASE WHEN AccountEnabled = 1 THEN 1 ELSE 0 END) AS ActiveUsers,
    SUM(CASE WHEN AccountEnabled = 0 THEN 1 ELSE 0 END) AS DisabledUsers
FROM AAD_Users;
GO

-- Users by department
SELECT
    Department,
    COUNT(*) AS UserCount
FROM AAD_Users
WHERE Department IS NOT NULL
GROUP BY Department
ORDER BY UserCount DESC;
GO

-- Users without recent sign-in (potential inactive accounts)
SELECT
    UserPrincipalName,
    DisplayName,
    Department,
    LastSignInDateTime,
    AccountEnabled
FROM AAD_Users
WHERE LastSignInDateTime < DATEADD(DAY, -90, GETDATE())
   OR LastSignInDateTime IS NULL
ORDER BY LastSignInDateTime;
GO

-- Licensed users
SELECT
    UserPrincipalName,
    DisplayName,
    AssignedLicenses
FROM AAD_Users
WHERE AssignedLicenses IS NOT NULL AND AssignedLicenses != '[]'
ORDER BY DisplayName;
GO

-- ================================================================
-- Azure AD Group Queries
-- ================================================================

-- Groups summary
SELECT
    CASE
        WHEN GroupTypes LIKE '%Unified%' THEN 'Microsoft 365 Group'
        WHEN SecurityEnabled = 1 AND MailEnabled = 0 THEN 'Security Group'
        WHEN SecurityEnabled = 0 AND MailEnabled = 1 THEN 'Distribution Group'
        ELSE 'Other'
    END AS GroupType,
    COUNT(*) AS GroupCount
FROM AAD_Groups
GROUP BY
    CASE
        WHEN GroupTypes LIKE '%Unified%' THEN 'Microsoft 365 Group'
        WHEN SecurityEnabled = 1 AND MailEnabled = 0 THEN 'Security Group'
        WHEN SecurityEnabled = 0 AND MailEnabled = 1 THEN 'Distribution Group'
        ELSE 'Other'
    END;
GO

-- Largest groups by member count
SELECT TOP 20
    DisplayName,
    MemberCount,
    GroupTypes,
    CreatedDateTime
FROM AAD_Groups
WHERE MemberCount IS NOT NULL
ORDER BY MemberCount DESC;
GO

-- Empty groups
SELECT
    DisplayName,
    Mail,
    CreatedDateTime
FROM AAD_Groups
WHERE MemberCount = 0 OR MemberCount IS NULL
ORDER BY DisplayName;
GO

-- ================================================================
-- Device Queries
-- ================================================================

-- Devices by operating system
SELECT
    OperatingSystem,
    COUNT(*) AS DeviceCount,
    SUM(CASE WHEN IsCompliant = 1 THEN 1 ELSE 0 END) AS CompliantDevices,
    SUM(CASE WHEN IsManaged = 1 THEN 1 ELSE 0 END) AS ManagedDevices
FROM AAD_Devices
GROUP BY OperatingSystem
ORDER BY DeviceCount DESC;
GO

-- Non-compliant devices
SELECT
    DisplayName,
    OperatingSystem,
    OperatingSystemVersion,
    IsManaged,
    ApproximateLastSignInDateTime
FROM AAD_Devices
WHERE IsCompliant = 0
ORDER BY DisplayName;
GO

-- Devices not seen recently
SELECT
    DisplayName,
    OperatingSystem,
    ApproximateLastSignInDateTime,
    RegistrationDateTime
FROM AAD_Devices
WHERE ApproximateLastSignInDateTime < DATEADD(DAY, -90, GETDATE())
   OR ApproximateLastSignInDateTime IS NULL
ORDER BY ApproximateLastSignInDateTime;
GO

-- ================================================================
-- Microsoft Teams Queries
-- ================================================================

-- Teams summary
SELECT
    COUNT(*) AS TotalTeams,
    SUM(CASE WHEN IsArchived = 1 THEN 1 ELSE 0 END) AS ArchivedTeams,
    SUM(CASE WHEN IsArchived = 0 THEN 1 ELSE 0 END) AS ActiveTeams
FROM Teams_Teams;
GO

-- Teams by visibility
SELECT
    Visibility,
    COUNT(*) AS TeamCount
FROM Teams_Teams
GROUP BY Visibility
ORDER BY TeamCount DESC;
GO

-- Recently created teams
SELECT TOP 10
    DisplayName,
    Description,
    Visibility,
    CreatedDateTime,
    WebUrl
FROM Teams_Teams
ORDER BY CreatedDateTime DESC;
GO

-- ================================================================
-- SharePoint Queries
-- ================================================================

-- SharePoint sites summary
SELECT
    COUNT(*) AS TotalSites,
    COUNT(DISTINCT SiteCollectionHostname) AS UniqueSiteCollections
FROM SharePoint_Sites;
GO

-- Recently modified sites
SELECT TOP 10
    DisplayName,
    WebUrl,
    LastModifiedDateTime,
    CreatedDateTime
FROM SharePoint_Sites
ORDER BY LastModifiedDateTime DESC;
GO

-- ================================================================
-- OneDrive Queries
-- ================================================================

-- OneDrive storage summary
SELECT
    COUNT(*) AS TotalDrives,
    SUM(QuotaUsed) / 1024.0 / 1024.0 / 1024.0 AS TotalUsedGB,
    AVG(QuotaUsed) / 1024.0 / 1024.0 / 1024.0 AS AvgUsedGB,
    MAX(QuotaUsed) / 1024.0 / 1024.0 / 1024.0 AS MaxUsedGB
FROM OneDrive_Drives;
GO

-- Top OneDrive users by storage
SELECT TOP 20
    OwnerDisplayName,
    OwnerUserPrincipalName,
    QuotaUsed / 1024.0 / 1024.0 / 1024.0 AS UsedGB,
    QuotaTotal / 1024.0 / 1024.0 / 1024.0 AS TotalGB,
    (QuotaUsed * 100.0 / NULLIF(QuotaTotal, 0)) AS PercentUsed
FROM OneDrive_Drives
ORDER BY QuotaUsed DESC;
GO

-- ================================================================
-- Planner Queries
-- ================================================================

-- Planner summary
SELECT
    COUNT(DISTINCT p.Id) AS TotalPlans,
    COUNT(t.Id) AS TotalTasks,
    SUM(CASE WHEN t.PercentComplete = 100 THEN 1 ELSE 0 END) AS CompletedTasks,
    SUM(CASE WHEN t.PercentComplete < 100 THEN 1 ELSE 0 END) AS IncompleteTasks
FROM Planner_Plans p
LEFT JOIN Planner_Tasks t ON p.Id = t.PlanId;
GO

-- Overdue tasks
SELECT
    p.Title AS PlanTitle,
    t.Title AS TaskTitle,
    t.DueDateTime,
    t.PercentComplete,
    t.Priority
FROM Planner_Tasks t
INNER JOIN Planner_Plans p ON t.PlanId = p.Id
WHERE t.DueDateTime < GETDATE()
  AND t.PercentComplete < 100
ORDER BY t.DueDateTime;
GO

-- Task completion rate by plan
SELECT
    p.Title AS PlanTitle,
    COUNT(t.Id) AS TotalTasks,
    SUM(CASE WHEN t.PercentComplete = 100 THEN 1 ELSE 0 END) AS CompletedTasks,
    (SUM(CASE WHEN t.PercentComplete = 100 THEN 1 ELSE 0 END) * 100.0 / COUNT(t.Id)) AS CompletionRate
FROM Planner_Plans p
LEFT JOIN Planner_Tasks t ON p.Id = t.PlanId
GROUP BY p.Title
HAVING COUNT(t.Id) > 0
ORDER BY CompletionRate DESC;
GO

-- ================================================================
-- Compliance and Security Queries
-- ================================================================

-- Data retention check (identify old exports)
SELECT
    ComponentName,
    COUNT(*) AS OldExportCount,
    MIN(StartTime) AS OldestExport
FROM ExportHistory
WHERE StartTime < DATEADD(DAY, -365, GETDATE())
GROUP BY ComponentName;
GO

-- User access audit (who performed exports)
SELECT
    ExecutedBy,
    COUNT(*) AS ExportCount,
    MIN(Timestamp) AS FirstAccess,
    MAX(Timestamp) AS LastAccess
FROM AuditLog
WHERE Category = 'Export'
GROUP BY ExecutedBy
ORDER BY ExportCount DESC;
GO

PRINT 'Sample queries loaded successfully!';
GO
