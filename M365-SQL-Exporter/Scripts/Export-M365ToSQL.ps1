<#
.SYNOPSIS
    Main Export Script for M365-SQL-Exporter

.DESCRIPTION
    Orchestrates the export of Microsoft 365 data to SQL database with support
    for full and incremental export modes, compliance features, and audit logging.

.PARAMETER ExportMode
    Export mode: Full or Incremental

.PARAMETER Components
    Specific components to export (default: all enabled components)

.PARAMETER ConfigPath
    Path to configuration file

.PARAMETER CredentialsPath
    Path to credentials file

.EXAMPLE
    .\Export-M365ToSQL.ps1 -ExportMode Full

.EXAMPLE
    .\Export-M365ToSQL.ps1 -ExportMode Incremental -Components @("Users", "Groups")

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Full', 'Incremental')]
    [string]$ExportMode = 'Incremental',

    [Parameter(Mandatory = $false)]
    [string[]]$Components = @(),

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\Config\config.json",

    [Parameter(Mandatory = $false)]
    [string]$CredentialsPath = "$PSScriptRoot\..\Config\credentials.json"
)

# Start timing
$scriptStartTime = Get-Date

# Import modules
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "M365 to SQL Exporter" -ForegroundColor Cyan
Write-Host "Version 1.0.0" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Loading modules..." -ForegroundColor Cyan

$modulePath = Join-Path $PSScriptRoot "..\Modules"
. (Join-Path $modulePath "Validate-Config.ps1")
. (Join-Path $modulePath "Auth-GraphAPI.ps1")
. (Join-Path $modulePath "Database-Functions.ps1")
. (Join-Path $modulePath "Audit-Logging.ps1")
. (Join-Path $modulePath "Collector-AzureAD.ps1")
. (Join-Path $modulePath "Collector-M365Services.ps1")

Write-Host "✓ Modules loaded successfully`n" -ForegroundColor Green

try {
    # Validate prerequisites
    if (-not (Test-AllPrerequisites -ConfigPath $ConfigPath -CredentialsPath $CredentialsPath)) {
        throw "Prerequisites validation failed. Please check your configuration."
    }

    # Load configuration
    $config = Get-ConfigurationSettings -ConfigPath $ConfigPath
    $credentials = Get-CredentialSettings -CredentialsPath $CredentialsPath

    # Initialize Graph API authentication
    Write-Host "Authenticating to Microsoft Graph API..." -ForegroundColor Cyan
    $authSuccess = Initialize-GraphAuth -TenantId $credentials.AzureAD.TenantId `
        -ClientId $credentials.AzureAD.ClientId `
        -ClientSecret $credentials.AzureAD.ClientSecret

    if (-not $authSuccess) {
        throw "Failed to initialize Graph API authentication"
    }

    # Test Graph API connection
    if (-not (Test-GraphConnection)) {
        throw "Failed to connect to Microsoft Graph API"
    }

    # Initialize database connection
    Write-Host "`nInitializing database connection..." -ForegroundColor Cyan
    
    # Create database if needed
    if ($config.DatabaseSettings.AutoCreateDatabase) {
        $dbCreated = New-DatabaseIfNotExists -ServerName $credentials.Database.ServerName `
            -DatabaseName $credentials.Database.DatabaseName `
            -UseWindowsAuth $credentials.Database.UseWindowsAuthentication `
            -Username $credentials.Database.Username `
            -Password $credentials.Database.Password
        
        if (-not $dbCreated) {
            throw "Failed to create database"
        }
    }

    # Initialize database connection
    $dbInitSuccess = Initialize-DatabaseConnection -ServerName $credentials.Database.ServerName `
        -DatabaseName $credentials.Database.DatabaseName `
        -UseWindowsAuth $credentials.Database.UseWindowsAuthentication `
        -Username $credentials.Database.Username `
        -Password $credentials.Database.Password

    if (-not $dbInitSuccess) {
        throw "Failed to initialize database connection"
    }

    # Test database connection
    if (-not (Test-DatabaseConnection)) {
        throw "Failed to connect to database"
    }

    # Initialize database schema
    if ($config.DatabaseSettings.AutoCreateSchema) {
        if (-not (Initialize-DatabaseSchema)) {
            throw "Failed to initialize database schema"
        }
    }

    # Open persistent database connection
    $dbConnection = Open-DatabaseConnection
    if ($null -eq $dbConnection) {
        throw "Failed to open database connection"
    }

    # Determine components to export
    $componentsToExport = @()
    
    if ($Components.Count -eq 0) {
        # Export all enabled components
        if ($config.M365Components.AzureAD.Enabled) { $componentsToExport += "AzureAD" }
        if ($config.M365Components.Teams.Enabled) { $componentsToExport += "Teams" }
        if ($config.M365Components.SharePointOnline.Enabled) { $componentsToExport += "SharePoint" }
        if ($config.M365Components.OneDrive.Enabled) { $componentsToExport += "OneDrive" }
        if ($config.M365Components.Planner.Enabled) { $componentsToExport += "Planner" }
    }
    else {
        $componentsToExport = $Components
    }

    # Start export session
    Start-ExportSession -ExportMode $ExportMode -Components $componentsToExport

    # Log export start
    Write-AuditLog -Category "Export" -Action "ExportStarted" -Details "Export Mode: $ExportMode, Components: $($componentsToExport -join ', ')"

    # Track total records
    $totalRecordsExported = 0

    # Export each component
    foreach ($component in $componentsToExport) {
        Write-Host "`n----------------------------------------" -ForegroundColor Cyan
        Write-Host "Exporting: $component" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Cyan
        
        $componentStartTime = Get-Date
        $recordsExported = 0

        try {
            Write-ExportAuditLog -ComponentName $component -ExportMode $ExportMode -Status "Started"

            switch ($component) {
                "AzureAD" {
                    $recordsExported = Export-AllAzureADData -Connection $dbConnection `
                        -IncludeSignInActivity $config.M365Components.AzureAD.IncludeSignInActivity
                }
                "Teams" {
                    $recordsExported = Export-TeamsData -Connection $dbConnection
                }
                "SharePoint" {
                    $recordsExported = Export-SharePointSites -Connection $dbConnection
                }
                "OneDrive" {
                    $recordsExported = Export-OneDriveDrives -Connection $dbConnection
                }
                "Planner" {
                    $recordsExported = Export-PlannerData -Connection $dbConnection
                }
                default {
                    Write-Warning "Unknown component: $component"
                }
            }

            $componentDuration = (Get-Date) - $componentStartTime
            
            if ($recordsExported -ge 0) {
                $totalRecordsExported += $recordsExported
                Write-Host "✓ Component export completed in $($componentDuration.ToString('mm\:ss'))" -ForegroundColor Green
                Write-ExportAuditLog -ComponentName $component -ExportMode $ExportMode -Status "Completed" -RecordCount $recordsExported
                
                # Log to ExportHistory table
                $exportHistoryQuery = @"
INSERT INTO ExportHistory (ComponentName, ExportMode, StartTime, EndTime, Status, RecordsExported, ExecutedBy)
VALUES (@ComponentName, @ExportMode, @StartTime, @EndTime, @Status, @RecordsExported, @ExecutedBy)
"@
                $exportHistoryParams = @{
                    ComponentName    = $component
                    ExportMode       = $ExportMode
                    StartTime        = $componentStartTime
                    EndTime          = Get-Date
                    Status           = "Completed"
                    RecordsExported  = $recordsExported
                    ExecutedBy       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                }
                Invoke-SqlNonQuery -Query $exportHistoryQuery -Parameters $exportHistoryParams -Connection $dbConnection | Out-Null
            }
            else {
                Write-Warning "Component export failed or returned no data"
                Write-ExportAuditLog -ComponentName $component -ExportMode $ExportMode -Status "Failed" -ErrorMessage "Export returned -1"
            }
        }
        catch {
            Write-Error "Error exporting $component : $_"
            Write-ExportAuditLog -ComponentName $component -ExportMode $ExportMode -Status "Failed" -ErrorMessage $_.Exception.Message
            
            # Log failure to ExportHistory
            $exportHistoryQuery = @"
INSERT INTO ExportHistory (ComponentName, ExportMode, StartTime, EndTime, Status, RecordsExported, ErrorMessage, ExecutedBy)
VALUES (@ComponentName, @ExportMode, @StartTime, @EndTime, @Status, @RecordsExported, @ErrorMessage, @ExecutedBy)
"@
            $exportHistoryParams = @{
                ComponentName    = $component
                ExportMode       = $ExportMode
                StartTime        = $componentStartTime
                EndTime          = Get-Date
                Status           = "Failed"
                RecordsExported  = 0
                ErrorMessage     = $_.Exception.Message
                ExecutedBy       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            Invoke-SqlNonQuery -Query $exportHistoryQuery -Parameters $exportHistoryParams -Connection $dbConnection | Out-Null
        }
    }

    # Close database connection
    Close-DatabaseConnection -Connection $dbConnection

    # Calculate total duration
    $totalDuration = (Get-Date) - $scriptStartTime

    # End export session
    Stop-ExportSession -Status "Completed" -TotalRecordsExported $totalRecordsExported -Duration $totalDuration

    # Log export completion
    Write-AuditLog -Category "Export" -Action "ExportCompleted" -Details "Total Records: $totalRecordsExported, Duration: $($totalDuration.ToString())"

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Export Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Total Records Exported: $totalRecordsExported" -ForegroundColor Cyan
    Write-Host "Total Duration: $($totalDuration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Green

    exit 0
}
catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "✗ Export Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red

    # Log failure
    Write-AuditLog -Category "Export" -Action "ExportFailed" -Details "Error: $($_.Exception.Message)"
    
    # End export session with failure
    $totalDuration = (Get-Date) - $scriptStartTime
    Stop-ExportSession -Status "Failed" -TotalRecordsExported 0 -Duration $totalDuration

    exit 1
}
