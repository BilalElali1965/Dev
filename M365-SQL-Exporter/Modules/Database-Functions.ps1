<#
.SYNOPSIS
    SQL Database Functions Module for M365-SQL-Exporter

.DESCRIPTION
    Handles all SQL database operations including connection management,
    schema creation, data insertion, and transaction handling.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

# Module-level variables
$script:ConnectionString = $null
$script:Connection = $null

<#
.SYNOPSIS
    Initializes database connection

.PARAMETER ServerName
    SQL Server name or IP address

.PARAMETER DatabaseName
    Database name

.PARAMETER UseWindowsAuth
    Use Windows Authentication

.PARAMETER Username
    SQL username (if not using Windows Auth)

.PARAMETER Password
    SQL password (if not using Windows Auth)

.EXAMPLE
    Initialize-DatabaseConnection -ServerName "localhost" -DatabaseName "M365ExportDB" -UseWindowsAuth
#>
function Initialize-DatabaseConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $false)]
        [bool]$UseWindowsAuth = $false,

        [Parameter(Mandatory = $false)]
        [string]$Username = "",

        [Parameter(Mandatory = $false)]
        [string]$Password = ""
    )

    try {
        Write-Verbose "Initializing database connection..."

        if ($UseWindowsAuth) {
            $script:ConnectionString = "Server=$ServerName;Database=$DatabaseName;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=30;"
        }
        else {
            if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
                throw "Username and Password are required when not using Windows Authentication"
            }
            $script:ConnectionString = "Server=$ServerName;Database=$DatabaseName;User Id=$Username;Password=$Password;TrustServerCertificate=True;Connection Timeout=30;"
        }

        Write-Verbose "Database connection initialized successfully"
        return $true
    }
    catch {
        Write-Error "Failed to initialize database connection: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Opens a database connection

.EXAMPLE
    $conn = Open-DatabaseConnection
#>
function Open-DatabaseConnection {
    [CmdletBinding()]
    param()

    try {
        if ([string]::IsNullOrWhiteSpace($script:ConnectionString)) {
            throw "Connection string not initialized. Call Initialize-DatabaseConnection first."
        }

        $connection = New-Object System.Data.SqlClient.SqlConnection($script:ConnectionString)
        $connection.Open()
        
        Write-Verbose "Database connection opened successfully"
        return $connection
    }
    catch {
        Write-Error "Failed to open database connection: $_"
        Write-Error "Error details: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Closes a database connection

.PARAMETER Connection
    The connection to close

.EXAMPLE
    Close-DatabaseConnection -Connection $conn
#>
function Close-DatabaseConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Data.SqlClient.SqlConnection]$Connection
    )

    try {
        if ($null -ne $Connection -and $Connection.State -eq 'Open') {
            $Connection.Close()
            $Connection.Dispose()
            Write-Verbose "Database connection closed successfully"
        }
    }
    catch {
        Write-Warning "Error closing database connection: $_"
    }
}

<#
.SYNOPSIS
    Executes a non-query SQL command

.PARAMETER Query
    SQL query to execute

.PARAMETER Connection
    Database connection (optional, will create new if not provided)

.PARAMETER Parameters
    Hashtable of parameters

.EXAMPLE
    Invoke-SqlNonQuery -Query "CREATE TABLE Test (Id INT)" -Connection $conn
#>
function Invoke-SqlNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [System.Data.SqlClient.SqlConnection]$Connection = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    $closeConnection = $false
    try {
        if ($null -eq $Connection) {
            $Connection = Open-DatabaseConnection
            $closeConnection = $true
        }

        if ($null -eq $Connection) {
            throw "Failed to establish database connection"
        }

        $command = $Connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 300

        # Add parameters
        foreach ($key in $Parameters.Keys) {
            $param = $command.Parameters.AddWithValue("@$key", $Parameters[$key])
            if ($null -eq $Parameters[$key]) {
                $param.Value = [DBNull]::Value
            }
        }

        $rowsAffected = $command.ExecuteNonQuery()
        Write-Verbose "Query executed successfully. Rows affected: $rowsAffected"
        
        return $rowsAffected
    }
    catch {
        Write-Error "Failed to execute SQL query: $_"
        Write-Error "Query: $Query"
        return -1
    }
    finally {
        if ($closeConnection -and $null -ne $Connection) {
            Close-DatabaseConnection -Connection $Connection
        }
    }
}

<#
.SYNOPSIS
    Executes a SQL query and returns results

.PARAMETER Query
    SQL query to execute

.PARAMETER Connection
    Database connection (optional)

.PARAMETER Parameters
    Hashtable of parameters

.EXAMPLE
    $results = Invoke-SqlQuery -Query "SELECT * FROM Users" -Connection $conn
#>
function Invoke-SqlQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $false)]
        [System.Data.SqlClient.SqlConnection]$Connection = $null,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )

    $closeConnection = $false
    try {
        if ($null -eq $Connection) {
            $Connection = Open-DatabaseConnection
            $closeConnection = $true
        }

        if ($null -eq $Connection) {
            throw "Failed to establish database connection"
        }

        $command = $Connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 300

        # Add parameters
        foreach ($key in $Parameters.Keys) {
            $param = $command.Parameters.AddWithValue("@$key", $Parameters[$key])
            if ($null -eq $Parameters[$key]) {
                $param.Value = [DBNull]::Value
            }
        }

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null

        Write-Verbose "Query executed successfully. Rows returned: $($dataset.Tables[0].Rows.Count)"
        return $dataset.Tables[0]
    }
    catch {
        Write-Error "Failed to execute SQL query: $_"
        Write-Error "Query: $Query"
        return $null
    }
    finally {
        if ($closeConnection -and $null -ne $Connection) {
            Close-DatabaseConnection -Connection $Connection
        }
    }
}

<#
.SYNOPSIS
    Tests database connectivity

.EXAMPLE
    Test-DatabaseConnection
#>
function Test-DatabaseConnection {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Testing database connectivity..." -ForegroundColor Cyan
        
        $connection = Open-DatabaseConnection
        if ($null -eq $connection) {
            Write-Host "✗ Failed to connect to database" -ForegroundColor Red
            return $false
        }

        # Test query
        $result = Invoke-SqlQuery -Query "SELECT @@VERSION AS Version" -Connection $connection
        
        if ($null -ne $result -and $result.Rows.Count -gt 0) {
            Write-Host "✓ Successfully connected to SQL Server" -ForegroundColor Green
            Write-Host "  Server Version: $($result.Rows[0].Version.Split("`n")[0])" -ForegroundColor Gray
            Close-DatabaseConnection -Connection $connection
            return $true
        }
        else {
            Write-Host "✗ Failed to query database" -ForegroundColor Red
            Close-DatabaseConnection -Connection $connection
            return $false
        }
    }
    catch {
        Write-Host "✗ Database connection test failed: $_" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Creates the database if it doesn't exist

.PARAMETER ServerName
    SQL Server name

.PARAMETER DatabaseName
    Database name to create

.PARAMETER UseWindowsAuth
    Use Windows Authentication

.PARAMETER Username
    SQL username

.PARAMETER Password
    SQL password

.EXAMPLE
    New-DatabaseIfNotExists -ServerName "localhost" -DatabaseName "M365ExportDB" -UseWindowsAuth $true
#>
function New-DatabaseIfNotExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,

        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,

        [Parameter(Mandatory = $false)]
        [bool]$UseWindowsAuth = $false,

        [Parameter(Mandatory = $false)]
        [string]$Username = "",

        [Parameter(Mandatory = $false)]
        [string]$Password = ""
    )

    try {
        Write-Host "Checking if database '$DatabaseName' exists..." -ForegroundColor Cyan

        # Connect to master database
        if ($UseWindowsAuth) {
            $masterConnString = "Server=$ServerName;Database=master;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=30;"
        }
        else {
            $masterConnString = "Server=$ServerName;Database=master;User Id=$Username;Password=$Password;TrustServerCertificate=True;Connection Timeout=30;"
        }

        $connection = New-Object System.Data.SqlClient.SqlConnection($masterConnString)
        $connection.Open()

        # Check if database exists
        $checkQuery = "SELECT database_id FROM sys.databases WHERE name = @DatabaseName"
        $command = $connection.CreateCommand()
        $command.CommandText = $checkQuery
        $command.Parameters.AddWithValue("@DatabaseName", $DatabaseName) | Out-Null
        
        $result = $command.ExecuteScalar()

        if ($null -eq $result) {
            Write-Host "  Database does not exist. Creating..." -ForegroundColor Yellow
            
            $createQuery = "CREATE DATABASE [$DatabaseName]"
            $command.CommandText = $createQuery
            $command.ExecuteNonQuery() | Out-Null
            
            Write-Host "✓ Database '$DatabaseName' created successfully" -ForegroundColor Green
        }
        else {
            Write-Host "✓ Database '$DatabaseName' already exists" -ForegroundColor Green
        }

        $connection.Close()
        $connection.Dispose()
        return $true
    }
    catch {
        Write-Error "Failed to create database: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Creates core schema tables

.EXAMPLE
    Initialize-DatabaseSchema
#>
function Initialize-DatabaseSchema {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Initializing database schema..." -ForegroundColor Cyan

        $connection = Open-DatabaseConnection
        if ($null -eq $connection) {
            throw "Failed to establish database connection"
        }

        # Create ExportHistory table
        $exportHistoryTable = @"
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
END
"@

        # Create AuditLog table
        $auditLogTable = @"
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
END
"@

        # Create Configuration table
        $configTable = @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Configuration')
BEGIN
    CREATE TABLE Configuration (
        ConfigKey NVARCHAR(100) PRIMARY KEY,
        ConfigValue NVARCHAR(MAX) NULL,
        Description NVARCHAR(500) NULL,
        LastModified DATETIME2 DEFAULT GETDATE()
    );
END
"@

        # Execute table creation
        Invoke-SqlNonQuery -Query $exportHistoryTable -Connection $connection | Out-Null
        Write-Host "  ✓ ExportHistory table created/verified" -ForegroundColor Gray

        Invoke-SqlNonQuery -Query $auditLogTable -Connection $connection | Out-Null
        Write-Host "  ✓ AuditLog table created/verified" -ForegroundColor Gray

        Invoke-SqlNonQuery -Query $configTable -Connection $connection | Out-Null
        Write-Host "  ✓ Configuration table created/verified" -ForegroundColor Gray

        Close-DatabaseConnection -Connection $connection

        Write-Host "✓ Database schema initialized successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to initialize database schema: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Bulk inserts data into a table

.PARAMETER TableName
    Target table name

.PARAMETER Data
    Array of objects to insert

.PARAMETER Connection
    Database connection (optional)

.EXAMPLE
    Export-DataToTable -TableName "Users" -Data $userArray
#>
function Export-DataToTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $true)]
        [array]$Data,

        [Parameter(Mandatory = $false)]
        [System.Data.SqlClient.SqlConnection]$Connection = $null
    )

    $closeConnection = $false
    try {
        if ($Data.Count -eq 0) {
            Write-Verbose "No data to export to table '$TableName'"
            return 0
        }

        if ($null -eq $Connection) {
            $Connection = Open-DatabaseConnection
            $closeConnection = $true
        }

        if ($null -eq $Connection) {
            throw "Failed to establish database connection"
        }

        Write-Verbose "Exporting $($Data.Count) records to table '$TableName'..."

        # Create DataTable
        $dataTable = New-Object System.Data.DataTable

        # Get columns from first object
        $firstItem = $Data[0]
        $properties = $firstItem.PSObject.Properties

        foreach ($prop in $properties) {
            $column = New-Object System.Data.DataColumn
            $column.ColumnName = $prop.Name
            $dataTable.Columns.Add($column) | Out-Null
        }

        # Add rows
        foreach ($item in $Data) {
            $row = $dataTable.NewRow()
            foreach ($prop in $properties) {
                $value = $item.($prop.Name)
                if ($null -eq $value) {
                    $row[$prop.Name] = [DBNull]::Value
                }
                else {
                    $row[$prop.Name] = $value
                }
            }
            $dataTable.Rows.Add($row)
        }

        # Bulk copy
        $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy($Connection)
        $bulkCopy.DestinationTableName = $TableName
        $bulkCopy.BatchSize = 1000
        $bulkCopy.BulkCopyTimeout = 300

        $bulkCopy.WriteToServer($dataTable)
        $bulkCopy.Close()

        Write-Verbose "Successfully exported $($Data.Count) records to '$TableName'"
        return $Data.Count
    }
    catch {
        Write-Error "Failed to export data to table '$TableName': $_"
        return -1
    }
    finally {
        if ($closeConnection -and $null -ne $Connection) {
            Close-DatabaseConnection -Connection $Connection
        }
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-DatabaseConnection',
    'Open-DatabaseConnection',
    'Close-DatabaseConnection',
    'Invoke-SqlNonQuery',
    'Invoke-SqlQuery',
    'Test-DatabaseConnection',
    'New-DatabaseIfNotExists',
    'Initialize-DatabaseSchema',
    'Export-DataToTable'
)
