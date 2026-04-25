<#
.SYNOPSIS
    Audit Logging Module for M365-SQL-Exporter

.DESCRIPTION
    Provides comprehensive audit logging capabilities for compliance
    (GDPR, HIPAA, SOC2) including tracking all operations, API calls,
    and data access.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

# Module-level variables
$script:SessionId = [System.Guid]::NewGuid().ToString()
$script:ExecutedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$script:AuditEnabled = $true

<#
.SYNOPSIS
    Writes an audit log entry

.PARAMETER Category
    Audit category (e.g., Authentication, DataAccess, Export, API)

.PARAMETER Action
    Specific action performed

.PARAMETER EntityType
    Type of entity affected

.PARAMETER EntityId
    ID of entity affected

.PARAMETER Details
    Additional details about the action

.EXAMPLE
    Write-AuditLog -Category "Authentication" -Action "GraphAPILogin" -Details "Successful authentication"
#>
function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [string]$EntityType = $null,

        [Parameter(Mandatory = $false)]
        [string]$EntityId = $null,

        [Parameter(Mandatory = $false)]
        [string]$Details = $null
    )

    try {
        if (-not $script:AuditEnabled) {
            return
        }

        $timestamp = Get-Date
        $sourceIP = "LocalHost" # Can be enhanced to get actual IP

        # Log to database
        $query = @"
INSERT INTO AuditLog (Timestamp, Category, Action, EntityType, EntityId, Details, ExecutedBy, SourceIP, SessionId)
VALUES (@Timestamp, @Category, @Action, @EntityType, @EntityId, @Details, @ExecutedBy, @SourceIP, @SessionId)
"@

        $parameters = @{
            Timestamp  = $timestamp
            Category   = $Category
            Action     = $Action
            EntityType = $EntityType
            EntityId   = $EntityId
            Details    = $Details
            ExecutedBy = $script:ExecutedBy
            SourceIP   = $sourceIP
            SessionId  = $script:SessionId
        }

        # Import database module if not already loaded
        if (-not (Get-Command "Invoke-SqlNonQuery" -ErrorAction SilentlyContinue)) {
            $modulePath = Join-Path $PSScriptRoot "Database-Functions.ps1"
            if (Test-Path $modulePath) {
                . $modulePath
            }
        }

        Invoke-SqlNonQuery -Query $query -Parameters $parameters | Out-Null

        # Also log to file for redundancy
        $logPath = Join-Path $PSScriptRoot "..\Logs\Audit"
        if (-not (Test-Path $logPath)) {
            New-Item -Path $logPath -ItemType Directory -Force | Out-Null
        }

        $logFile = Join-Path $logPath "audit-$(Get-Date -Format 'yyyy-MM-dd').log"
        $logEntry = "[$timestamp] [$Category] [$Action] User: $script:ExecutedBy, Entity: $EntityType/$EntityId, Details: $Details"
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8

        Write-Verbose "Audit log entry created: $Category - $Action"
    }
    catch {
        # Don't fail the operation if audit logging fails, but warn
        Write-Warning "Failed to write audit log: $_"
    }
}

<#
.SYNOPSIS
    Writes an API request audit log

.PARAMETER Endpoint
    API endpoint called

.PARAMETER Method
    HTTP method used

.PARAMETER StatusCode
    Response status code

.PARAMETER Duration
    Request duration in milliseconds

.EXAMPLE
    Write-ApiAuditLog -Endpoint "/users" -Method "GET" -StatusCode 200 -Duration 250
#>
function Write-ApiAuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $false)]
        [int]$StatusCode = 0,

        [Parameter(Mandatory = $false)]
        [int]$Duration = 0
    )

    $details = "Method: $Method, Endpoint: $Endpoint, StatusCode: $StatusCode, Duration: ${Duration}ms"
    Write-AuditLog -Category "API" -Action "GraphAPIRequest" -EntityType "Endpoint" -EntityId $Endpoint -Details $details
}

<#
.SYNOPSIS
    Writes a data access audit log

.PARAMETER DataType
    Type of data accessed

.PARAMETER RecordCount
    Number of records accessed

.PARAMETER Operation
    Operation performed (Read, Insert, Update, Delete)

.EXAMPLE
    Write-DataAccessLog -DataType "Users" -RecordCount 100 -Operation "Read"
#>
function Write-DataAccessLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataType,

        [Parameter(Mandatory = $true)]
        [int]$RecordCount,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Read', 'Insert', 'Update', 'Delete', 'Export')]
        [string]$Operation
    )

    $details = "Operation: $Operation, RecordCount: $RecordCount, DataType: $DataType"
    Write-AuditLog -Category "DataAccess" -Action "DatabaseOperation" -EntityType $DataType -Details $details
}

<#
.SYNOPSIS
    Writes an export operation audit log

.PARAMETER ComponentName
    M365 component being exported

.PARAMETER ExportMode
    Export mode (Full or Incremental)

.PARAMETER Status
    Export status (Started, Completed, Failed)

.PARAMETER RecordCount
    Number of records exported

.PARAMETER ErrorMessage
    Error message if failed

.EXAMPLE
    Write-ExportAuditLog -ComponentName "Users" -ExportMode "Full" -Status "Completed" -RecordCount 500
#>
function Write-ExportAuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Incremental')]
        [string]$ExportMode,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Started', 'InProgress', 'Completed', 'Failed', 'PartialFailure')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [int]$RecordCount = 0,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = $null
    )

    $details = "Component: $ComponentName, Mode: $ExportMode, Status: $Status, Records: $RecordCount"
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $details += ", Error: $ErrorMessage"
    }

    Write-AuditLog -Category "Export" -Action "M365Export" -EntityType $ComponentName -Details $details
}

<#
.SYNOPSIS
    Starts an export session and logs it

.PARAMETER ExportMode
    Export mode (Full or Incremental)

.PARAMETER Components
    List of components to export

.EXAMPLE
    Start-ExportSession -ExportMode "Full" -Components @("Users", "Groups")
#>
function Start-ExportSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Full', 'Incremental')]
        [string]$ExportMode,

        [Parameter(Mandatory = $true)]
        [array]$Components
    )

    $details = "ExportMode: $ExportMode, Components: $($Components -join ', '), SessionId: $script:SessionId"
    Write-AuditLog -Category "Session" -Action "ExportSessionStarted" -Details $details

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Export Session Started" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Session ID: $script:SessionId" -ForegroundColor Gray
    Write-Host "User: $script:ExecutedBy" -ForegroundColor Gray
    Write-Host "Export Mode: $ExportMode" -ForegroundColor Gray
    Write-Host "Components: $($Components -join ', ')" -ForegroundColor Gray
    Write-Host "Started: $(Get-Date)" -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Ends an export session and logs it

.PARAMETER Status
    Overall export session status

.PARAMETER TotalRecordsExported
    Total records exported

.PARAMETER Duration
    Session duration

.EXAMPLE
    Stop-ExportSession -Status "Completed" -TotalRecordsExported 1500 -Duration (New-TimeSpan -Minutes 15)
#>
function Stop-ExportSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Completed', 'Failed', 'PartialSuccess')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [int]$TotalRecordsExported = 0,

        [Parameter(Mandatory = $false)]
        [TimeSpan]$Duration = (New-TimeSpan)
    )

    $details = "Status: $Status, TotalRecords: $TotalRecordsExported, Duration: $($Duration.ToString()), SessionId: $script:SessionId"
    Write-AuditLog -Category "Session" -Action "ExportSessionEnded" -Details $details

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Export Session Ended" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Session ID: $script:SessionId" -ForegroundColor Gray
    Write-Host "Status: $Status" -ForegroundColor Gray
    Write-Host "Total Records: $TotalRecordsExported" -ForegroundColor Gray
    Write-Host "Duration: $($Duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    Write-Host "Ended: $(Get-Date)" -ForegroundColor Gray
    Write-Host "========================================`n" -ForegroundColor Cyan
}

<#
.SYNOPSIS
    Retrieves audit logs with optional filtering

.PARAMETER Category
    Filter by category

.PARAMETER StartDate
    Filter by start date

.PARAMETER EndDate
    Filter by end date

.PARAMETER Action
    Filter by action

.EXAMPLE
    Get-AuditLogs -Category "Export" -StartDate (Get-Date).AddDays(-7)
#>
function Get-AuditLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Category = $null,

        [Parameter(Mandatory = $false)]
        [DateTime]$StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [DateTime]$EndDate = (Get-Date),

        [Parameter(Mandatory = $false)]
        [string]$Action = $null
    )

    try {
        $query = "SELECT * FROM AuditLog WHERE Timestamp >= @StartDate AND Timestamp <= @EndDate"
        
        $parameters = @{
            StartDate = $StartDate
            EndDate   = $EndDate
        }

        if (-not [string]::IsNullOrWhiteSpace($Category)) {
            $query += " AND Category = @Category"
            $parameters['Category'] = $Category
        }

        if (-not [string]::IsNullOrWhiteSpace($Action)) {
            $query += " AND Action = @Action"
            $parameters['Action'] = $Action
        }

        $query += " ORDER BY Timestamp DESC"

        # Import database module if not already loaded
        if (-not (Get-Command "Invoke-SqlQuery" -ErrorAction SilentlyContinue)) {
            $modulePath = Join-Path $PSScriptRoot "Database-Functions.ps1"
            if (Test-Path $modulePath) {
                . $modulePath
            }
        }

        $results = Invoke-SqlQuery -Query $query -Parameters $parameters
        return $results
    }
    catch {
        Write-Error "Failed to retrieve audit logs: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Exports audit logs to a file

.PARAMETER OutputPath
    Output file path

.PARAMETER Format
    Export format (CSV or JSON)

.PARAMETER StartDate
    Filter by start date

.PARAMETER EndDate
    Filter by end date

.EXAMPLE
    Export-AuditLogs -OutputPath "C:\Exports\audit.csv" -Format CSV
#>
function Export-AuditLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('CSV', 'JSON')]
        [string]$Format = 'CSV',

        [Parameter(Mandatory = $false)]
        [DateTime]$StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [DateTime]$EndDate = (Get-Date)
    )

    try {
        Write-Host "Exporting audit logs..." -ForegroundColor Cyan

        $logs = Get-AuditLogs -StartDate $StartDate -EndDate $EndDate

        if ($null -eq $logs -or $logs.Rows.Count -eq 0) {
            Write-Warning "No audit logs found for the specified date range"
            return $false
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        if ($Format -eq 'CSV') {
            $logs | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }
        elseif ($Format -eq 'JSON') {
            $logs | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
        }

        Write-Host "✓ Audit logs exported successfully to: $OutputPath" -ForegroundColor Green
        Write-Host "  Total records: $($logs.Rows.Count)" -ForegroundColor Gray
        return $true
    }
    catch {
        Write-Error "Failed to export audit logs: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Generates a compliance report

.PARAMETER ComplianceStandard
    Compliance standard (GDPR, HIPAA, SOC2)

.PARAMETER OutputPath
    Output file path

.PARAMETER StartDate
    Report start date

.PARAMETER EndDate
    Report end date

.EXAMPLE
    New-ComplianceReport -ComplianceStandard "GDPR" -OutputPath "C:\Reports\gdpr-report.html"
#>
function New-ComplianceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GDPR', 'HIPAA', 'SOC2')]
        [string]$ComplianceStandard,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [DateTime]$StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false)]
        [DateTime]$EndDate = (Get-Date)
    )

    try {
        Write-Host "Generating $ComplianceStandard compliance report..." -ForegroundColor Cyan

        $logs = Get-AuditLogs -StartDate $StartDate -EndDate $EndDate

        # Generate report content
        $reportContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>$ComplianceStandard Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #0066cc; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #0066cc; color: white; }
        .summary { background-color: #f0f0f0; padding: 15px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>$ComplianceStandard Compliance Report</h1>
    <div class="summary">
        <h2>Report Summary</h2>
        <p><strong>Period:</strong> $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))</p>
        <p><strong>Generated:</strong> $(Get-Date)</p>
        <p><strong>Total Audit Entries:</strong> $($logs.Rows.Count)</p>
    </div>
    <h2>Audit Log Details</h2>
    <table>
        <tr>
            <th>Timestamp</th>
            <th>Category</th>
            <th>Action</th>
            <th>User</th>
            <th>Details</th>
        </tr>
"@

        foreach ($log in $logs.Rows) {
            $reportContent += @"
        <tr>
            <td>$($log.Timestamp)</td>
            <td>$($log.Category)</td>
            <td>$($log.Action)</td>
            <td>$($log.ExecutedBy)</td>
            <td>$($log.Details)</td>
        </tr>
"@
        }

        $reportContent += @"
    </table>
</body>
</html>
"@

        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        $reportContent | Out-File -FilePath $OutputPath -Encoding UTF8

        Write-Host "✓ Compliance report generated successfully: $OutputPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to generate compliance report: $_"
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Write-AuditLog',
    'Write-ApiAuditLog',
    'Write-DataAccessLog',
    'Write-ExportAuditLog',
    'Start-ExportSession',
    'Stop-ExportSession',
    'Get-AuditLogs',
    'Export-AuditLogs',
    'New-ComplianceReport'
)
