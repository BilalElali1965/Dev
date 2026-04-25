<#
.SYNOPSIS
    SQL to Excel Export Script for M365-SQL-Exporter

.DESCRIPTION
    Exports SQL database tables to Excel format with proper formatting.

.PARAMETER ConfigPath
    Path to configuration file

.PARAMETER CredentialsPath
    Path to credentials file

.PARAMETER OutputPath
    Custom output path (optional)

.PARAMETER TableNames
    Specific tables to export (optional, default: all tables)

.EXAMPLE
    .\Export-SQLToExcel.ps1

.NOTES
    Version: 1.0.0
    Requires: ImportExcel module (Install-Module ImportExcel)
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
    [string[]]$TableNames = @()
)

# Import required modules
$modulePath = Join-Path $PSScriptRoot "..\Modules"
. (Join-Path $modulePath "Validate-Config.ps1")
. (Join-Path $modulePath "Database-Functions.ps1")
. (Join-Path $modulePath "Audit-Logging.ps1")

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SQL to Excel Export" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Check if ImportExcel module is available
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Warning "ImportExcel module not found. Attempting to install..."
        try {
            Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
            Write-Host "✓ ImportExcel module installed successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install ImportExcel module. Please install manually: Install-Module ImportExcel"
            exit 1
        }
    }

    Import-Module ImportExcel -ErrorAction Stop

    # Load configuration
    $config = Get-ConfigurationSettings -ConfigPath $ConfigPath
    $credentials = Get-CredentialSettings -CredentialsPath $CredentialsPath

    # Determine output path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $PSScriptRoot "..\Exports\Excel\Export_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
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

            # Create Excel file
            $excelFile = Join-Path $OutputPath "$tableName.xlsx"

            # Convert DataTable to array of objects for Export-Excel
            $exportData = @()
            foreach ($row in $data.Rows) {
                $obj = [ordered]@{}
                foreach ($column in $data.Columns) {
                    $obj[$column.ColumnName] = $row[$column.ColumnName]
                }
                $exportData += [PSCustomObject]$obj
            }

            # Export to Excel with formatting
            $exportData | Export-Excel -Path $excelFile `
                -AutoSize `
                -FreezeTopRow `
                -BoldTopRow `
                -AutoFilter `
                -WorksheetName $tableName

            Write-Host "  ✓ Exported to: $excelFile" -ForegroundColor Green
            
            $totalRecords += $rowCount
            $exportedTables++

            # Log export
            Write-AuditLog -Category "Export" -Action "ExcelExport" -EntityType $tableName -Details "Records: $rowCount, File: $excelFile"
        }
        catch {
            Write-Error "Failed to export table $tableName : $_"
        }
    }

    # Create summary file
    $summaryFile = Join-Path $OutputPath "EXPORT_SUMMARY.txt"
    $summaryContent = @"
M365-SQL-Exporter - Excel Export Summary
=========================================
Export Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Output Path: $OutputPath

Tables Exported: $exportedTables
Total Records: $totalRecords

Exported Tables:
$($TableNames | ForEach-Object { "  - $_" } | Out-String)
=========================================
"@
    $summaryContent | Out-File -FilePath $summaryFile -Encoding UTF8

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Excel Export Completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Tables Exported: $exportedTables" -ForegroundColor Cyan
    Write-Host "Total Records: $totalRecords" -ForegroundColor Cyan
    Write-Host "Output Path: $OutputPath" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Green

    # Log completion
    Write-AuditLog -Category "Export" -Action "ExcelExportCompleted" -Details "Tables: $exportedTables, Records: $totalRecords"

    exit 0
}
catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "✗ Excel Export Failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red

    Write-AuditLog -Category "Export" -Action "ExcelExportFailed" -Details "Error: $($_.Exception.Message)"

    exit 1
}
