-- ================================================================
-- M365-SQL-Exporter Database Schema Creation Script
-- Version: 1.0.0
-- Description: Creates all tables and indexes for M365 data export
-- ================================================================

-- Create database if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'M365ExportDB')
BEGIN
    CREATE DATABASE M365ExportDB;
END
GO

USE M365ExportDB;
GO

-- ================================================================
-- Core System Tables
-- ================================================================

-- Export History Table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'ExportHistory')
BEGIN
    CREATE TABLE ExportHistory (
        ExportId INT IDENTITY(1,1) PRIMARY KEY,
        ComponentName NVARCHAR(100) NOT NULL,
        ExportMode NVARCHAR(50) NOT NULL,
        StartTime DATETIME2 NOT NULL,
        EndTime DATETIME2 NULL,
        Status NVARCHAR(50) NOT NULL,
        RecordsExported INT NULL,
        ErrorMessage NVARCHAR(MAX) NULL,
        ExecutedBy NVARCHAR(255) NULL,
        CreatedAt DATETIME2 DEFAULT GETDATE()
    );
    
    CREATE INDEX IX_ExportHistory_ComponentName ON ExportHistory(ComponentName);
    CREATE INDEX IX_ExportHistory_StartTime ON ExportHistory(StartTime);
    CREATE INDEX IX_ExportHistory_Status ON ExportHistory(Status);
END
GO

-- Audit Log Table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditLog')
BEGIN
    CREATE TABLE AuditLog (
        AuditId BIGINT IDENTITY(1,1) PRIMARY KEY,
        Timestamp DATETIME2 DEFAULT GETDATE(),
        Category NVARCHAR(50) NOT NULL,
        Action NVARCHAR(100) NOT NULL,
        EntityType NVARCHAR(100) NULL,
        EntityId NVARCHAR(255) NULL,
        Details NVARCHAR(MAX) NULL,
        ExecutedBy NVARCHAR(255) NULL,
        SourceIP NVARCHAR(50) NULL,
        SessionId NVARCHAR(100) NULL
    );
    
    CREATE INDEX IX_AuditLog_Timestamp ON AuditLog(Timestamp);
    CREATE INDEX IX_AuditLog_Category ON AuditLog(Category);
    CREATE INDEX IX_AuditLog_Action ON AuditLog(Action);
    CREATE INDEX IX_AuditLog_SessionId ON AuditLog(SessionId);
END
GO

-- Configuration Table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Configuration')
BEGIN
    CREATE TABLE Configuration (
        ConfigKey NVARCHAR(100) PRIMARY KEY,
        ConfigValue NVARCHAR(MAX) NULL,
        Description NVARCHAR(500) NULL,
        LastModified DATETIME2 DEFAULT GETDATE()
    );
END
GO

-- ================================================================
-- Azure Active Directory Tables
-- ================================================================

-- AAD Users Table
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
    CREATE INDEX IX_AAD_Users_Department ON AAD_Users(Department);
END
GO

-- AAD Groups Table
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
    CREATE INDEX IX_AAD_Groups_GroupTypes ON AAD_Groups(GroupTypes);
END
GO

-- AAD Devices Table
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
    CREATE INDEX IX_AAD_Devices_OperatingSystem ON AAD_Devices(OperatingSystem);
END
GO

-- AAD Service Principals Table
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
GO

-- ================================================================
-- Microsoft Teams Tables
-- ================================================================

-- Teams Table
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
GO

-- ================================================================
-- SharePoint Online Tables
-- ================================================================

-- SharePoint Sites Table
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
    CREATE INDEX IX_SharePoint_Sites_DisplayName ON SharePoint_Sites(DisplayName);
END
GO

-- ================================================================
-- OneDrive for Business Tables
-- ================================================================

-- OneDrive Drives Table
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
GO

-- ================================================================
-- Planner Tables
-- ================================================================

-- Planner Plans Table
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
    CREATE INDEX IX_Planner_Plans_OwnerGroupId ON Planner_Plans(OwnerGroupId);
END
GO

-- Planner Tasks Table
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
    CREATE INDEX IX_Planner_Tasks_DueDateTime ON Planner_Tasks(DueDateTime);
END
GO

PRINT 'Database schema created successfully!';
GO
