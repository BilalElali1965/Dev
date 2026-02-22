<#
.SYNOPSIS
    SQL to CSV Export Script for M365-SQL-Exporter

.DESCRIPTION
    Exports SQL database tables to CSV format with proper encoding.

.PARAMETER ConfigPath
    Path to configuration file

.PARAMETER CredentialsPath
    Path to credentials file

.PARAMETER OutputPath
    Custom output path (optional)

.PARAMETER TableNames
    Specific tables to export (optional, default: all tables)

.PARAMETER CreateZip
    Create a ZIP archive of exported files

.EXAMPLE
    .\Export-SQLToCSV.ps1

.EXAMPLE
    .\Export-SQLToCSV.ps1 -CreateZip

.NOTES
    Version: 1.0.0
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\Config\config.json",

    [Parameter(Mandatory = $false)]
    [string]$CredentialsPath = "$PSScriptRoot\..\Config\credentials.json",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [string[]]$TableNames = @(),

    [Parameter(Mandatory = $false)]
    [switch]$CreateZip
)

# Import required modules
$modulePath = Join-Path $PSScriptRoot "..\Modules"
. (Join-Path $modulePath "Validate-Config.ps1")
. (Join-Path $modulePath "Database-Functions.ps1")
. (Join-Path $modulePath "Audit-Logging.ps1")

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SQL to CSV Export" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Load configuration
    $config = Get-ConfigurationSettings -ConfigPath $ConfigPath
    $credentials = Get-CredentialSettings -CredentialsPath $CredentialsPath

    # Determine output path
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $PSScriptRoot "..\Exports\CSV\Export_$timestamp"
    }

    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Output path: $OutputPath`n" -ForegroundColor Gray

    # Initialize database connection
    $dbInitSuccess = Initialize-DatabaseConnection -ServerName $credentials.Database.ServerName `
        -DatabaseName $credentials.Database.DatabaseName `
        -UseWindowsAuth $credentials.Database.UseWindowsAuthentication `
        -Username $credentials.Database.Username `
        -Password $credentials.Database.Password

    if (-not $dbInitSuccess) {
        throw "Failed to initialize database connection"
    }

    # Get list of tables to export
    if ($TableNames.Count -eq 0) {
        Write-Host "Retrieving list of tables..." -ForegroundColor Cyan
        $tablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_NAME NOT IN ('ExportHistory', 'AuditLog', 'Configuration') ORDER BY TABLE_NAME"
        $tablesResult = Invoke-SqlQuery -Query $tablesQuery
        
        if ($null -eq $tablesResult -or $tablesResult.Rows.Count -eq 0) {
            Write-Warning "No tables found to export"
            exit 0
        }

        $TableNames = $tablesResult.Rows | ForEach-Object { $_.TABLE_NAME }
    }

    Write-Host "Found $($TableNames.Count) tables to export`n" -ForegroundColor Gray

    # Export each table
    $totalRecords = 0
    $exportedTables = 0
    $exportedFiles = @()

    foreach ($tableName in $TableNames) {
        try {
            Write-Host "Exporting table: $tableName..." -ForegroundColor Cyan

            # Get data from table
            $query = "SELECT * FROM [$tableName]"
            $data = Invoke-SqlQuery -Query $query

            if ($null -eq $data -or $data.Rows.Count -eq 0) {
                Write-Host "  ⚠ No data found in table" -ForegroundColor Yellow
                continue
            }

            $rowCount = $data.Rows.Count
            Write-Host "  Retrieved $rowCount records" -ForegroundColor Gray

            # Create CSV file
            $csvFile = Join-Path $OutputPath "$tableName.csv"

            # Convert DataTable to array of objects for Export-Csv
            $exportData = @()
            foreach ($row in $data.Rows) {
                $obj = [ordered]@{}
                foreach ($column in $data.Columns) {
                    $obj[$column.ColumnName] = $row[$column.ColumnName]
                }
                $exportData += [PSCustomObject]$obj
            }

            # Export to CSV with UTF-8 encoding
            $exportData | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

            Write-Host "  ✓ Exported to: $csvFile" -ForegroundColor Green
            
            $totalRecords += $rowCount
            $exportedTables++
            $exportedFiles += $csvFile

            # Log export
            Write-AuditLog -Category "Export" -Action "CSVExport" -EntityType $tableName -Details "Records: $rowCount, File: $csvFile"
        }
        catch {
            Write-Error "Failed to export table $tableName : $_"
        }
    }

    # Create manifest file
    $manifestFile = Join-Path $OutputPath "MANIFEST.txt"
    $manifestContent = @"
M365-SQL-Exporter - CSV Export Manifest
=========================================
Export Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Output Path: $OutputPath

Tables Exported: $exportedTables
Total Records: $totalRecords

Exported Files:
$($exportedFiles | ForEach-Object { "  - $(Split-Path $_ -Leaf)" } | Out-String)
=========================================
"@
    $manifestContent | Out-File -FilePath $manifestFile -Encoding UTF8

    # Create ZIP archive if requested
    if ($CreateZip) {
        Write-Host "`nCreating ZIP archive..." -ForegroundColor Cyan
        $zipFile = Join-Path (Split-Path $OutputPath -Parent) "M365Export_$timestamp.zip"
        
        try {
            Compress-Archive -Path "$OutputPath\*" -DestinationPath $zipFile -Force
            Write-Host "✓ ZIP archive created: $zipFile" -ForegroundColor Green
            
            # Log ZIP creation
            Write-AuditLog -Category "Export" -Action "ZIPCreated" -Details "File: $zipFile"
        }
        catch {
            Write-Warning "Failed to create ZIP archive: $_"
        }
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ CSV Export Completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Tables Exported: $exportedTables" -ForegroundColor Cyan
    Write-Host "Total Records: $totalRecords" -ForegroundColor Cyan
    Write-Host "Output Path: $OutputPath" -ForegroundColor Cyan
    if ($CreateZip -and (Test-Path $zipFile)) {
        Write-Host "ZIP Archive: $zipFile" -ForegroundColor Cyan
    }
    Write-Host "========================================`n" -ForegroundColor Green

    # Log completion
    Write-AuditLog -Category "Export" -Action "CSVExportCompleted" -Details "Tables: $exportedTables, Records: $totalRecords"

    exit 0
}
catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "✗ CSV Export Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red

    Write-AuditLog -Category "Export" -Action "CSVExportFailed" -Details "Error: $($_.Exception.Message)"

    exit 1
}
