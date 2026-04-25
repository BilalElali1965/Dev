# Troubleshooting Guide

Common issues and solutions for the M365-SQL-Exporter.

## Table of Contents
- [Authentication Issues](#authentication-issues)
- [Database Connection Issues](#database-connection-issues)
- [Data Export Issues](#data-export-issues)
- [Performance Issues](#performance-issues)
- [Excel/CSV Export Issues](#excelcsv-export-issues)
- [General Errors](#general-errors)

## Authentication Issues

### Issue: "Failed to obtain access token"

**Symptoms**:
```
Failed to obtain access token: The remote server returned an error: (401) Unauthorized.
```

**Possible Causes**:
1. Incorrect Tenant ID, Client ID, or Client Secret
2. Client secret expired
3. App registration deleted or disabled

**Solutions**:

1. **Verify credentials**:
   ```powershell
   # Check your credentials.json file
   Get-Content Config\credentials.json | ConvertFrom-Json | Select-Object -ExpandProperty AzureAD
   ```

2. **Check client secret expiration**:
   - Azure Portal > App registrations > Your app
   - Certificates & secrets
   - Check expiration date
   - Create new secret if expired

3. **Verify app registration exists**:
   - Azure Portal > App registrations
   - Search for your app name
   - If missing, recreate following SETUP.md

### Issue: "Insufficient privileges to complete the operation"

**Symptoms**:
```
Insufficient privileges to complete the operation
```

**Possible Causes**:
1. Missing API permissions
2. Admin consent not granted
3. Permissions not yet propagated

**Solutions**:

1. **Verify permissions granted**:
   - Azure Portal > App registrations > Your app
   - API permissions
   - Ensure all required permissions are listed
   - Check "Status" column shows "Granted"

2. **Grant admin consent**:
   - Click "Grant admin consent for [Organization]"
   - Wait 5-10 minutes for propagation

3. **Force token refresh**:
   ```powershell
   Get-GraphAccessToken -ForceRefresh
   ```

### Issue: "Access is denied"

**Symptoms**:
```
Access is denied. Check credentials and try again.
```

**Solutions**:
1. Ensure using Application permissions (not Delegated)
2. Verify correct Microsoft Graph (not Azure AD Graph)
3. Check tenant ID matches your organization

## Database Connection Issues

### Issue: "A network-related or instance-specific error"

**Symptoms**:
```
A network-related or instance-specific error occurred while establishing a connection to SQL Server
```

**Possible Causes**:
1. SQL Server not running
2. Firewall blocking connection
3. Incorrect server name or port
4. TCP/IP not enabled

**Solutions**:

1. **Verify SQL Server is running**:
   ```powershell
   # Check SQL Server service
   Get-Service -Name MSSQLSERVER
   ```

2. **Test connectivity**:
   ```powershell
   # Test port 1433
   Test-NetConnection -ComputerName "server.database.windows.net" -Port 1433
   ```

3. **Check Azure SQL firewall** (if using Azure):
   - Azure Portal > SQL Server > Networking
   - Add your IP address to allowed list
   - Or enable "Allow Azure services"

4. **Enable TCP/IP** (on-premises SQL):
   - SQL Server Configuration Manager
   - SQL Server Network Configuration
   - Enable TCP/IP protocol
   - Restart SQL Server service

### Issue: "Login failed for user"

**Symptoms**:
```
Login failed for user 'username'
```

**Solutions**:

1. **Verify credentials**:
   ```json
   {
     "Database": {
       "Username": "correct_username",
       "Password": "correct_password"
     }
   }
   ```

2. **Check SQL authentication mode**:
   - SQL Server must allow SQL Server and Windows Authentication
   - SSMS > Server Properties > Security
   - Select "SQL Server and Windows Authentication mode"
   - Restart SQL Server

3. **Test connection manually**:
   ```powershell
   $server = "server.database.windows.net"
   $database = "M365ExportDB"
   $username = "sqladmin"
   $password = "YourPassword"
   
   $conn = New-Object System.Data.SqlClient.SqlConnection
   $conn.ConnectionString = "Server=$server;Database=$database;User Id=$username;Password=$password;"
   $conn.Open()
   Write-Host "Connection successful!"
   $conn.Close()
   ```

### Issue: "Cannot open database requested by the login"

**Symptoms**:
```
Cannot open database "M365ExportDB" requested by the login. The login failed.
```

**Solutions**:

1. **Verify database exists**:
   ```sql
   SELECT name FROM sys.databases WHERE name = 'M365ExportDB';
   ```

2. **Create database**:
   - Set `AutoCreateDatabase: true` in config.json
   - Or manually create: `CREATE DATABASE M365ExportDB;`

3. **Check user permissions**:
   ```sql
   USE M365ExportDB;
   EXEC sp_helpuser;
   ```

## Data Export Issues

### Issue: "No users/groups/devices found"

**Symptoms**:
```
WARNING: No users found
```

**Possible Causes**:
1. API permissions not granted
2. No data exists in M365 tenant
3. API endpoint changed

**Solutions**:

1. **Test API access directly**:
   ```powershell
   . .\Modules\Auth-GraphAPI.ps1
   Initialize-GraphAuth -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz"
   $users = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/users?`$top=5"
   $users.value
   ```

2. **Check permissions**:
   - See [API-PERMISSIONS.md](API-PERMISSIONS.md)
   - Ensure admin consent granted

3. **Enable verbose logging**:
   ```powershell
   .\Scripts\Export-M365ToSQL.ps1 -Verbose
   ```

### Issue: "API throttling detected"

**Symptoms**:
```
API throttling detected. Waiting 60 seconds before retry...
```

**This is normal behavior** - the solution automatically handles throttling.

**If throttling occurs frequently**:

1. **Reduce parallelism**:
   ```json
   {
     "ExportSettings": {
       "EnableParallelProcessing": false,
       "BatchSize": 50
     }
   }
   ```

2. **Increase delays**:
   ```json
   {
     "GraphAPISettings": {
       "ThrottleDelaySeconds": 120
     }
   }
   ```

3. **Schedule exports during off-peak hours**

### Issue: "Request timed out"

**Symptoms**:
```
The operation has timed out
```

**Solutions**:

1. **Increase timeouts**:
   ```json
   {
     "DatabaseSettings": {
       "CommandTimeout": 600
     }
   }
   ```

2. **Reduce batch size**:
   ```json
   {
     "ExportSettings": {
       "BatchSize": 50,
       "PageSize": 500
     }
   }
   ```

3. **Export components separately**:
   ```powershell
   .\Scripts\Export-M365ToSQL.ps1 -Components @("AzureAD")
   .\Scripts\Export-M365ToSQL.ps1 -Components @("Teams")
   ```

## Performance Issues

### Issue: Export taking too long

**Symptoms**:
- Export runs for hours
- No progress updates

**Solutions**:

1. **Use incremental export**:
   ```powershell
   .\Scripts\Export-M365ToSQL.ps1 -ExportMode Incremental
   ```

2. **Enable parallel processing**:
   ```json
   {
     "ExportSettings": {
       "EnableParallelProcessing": true,
       "MaxParallelJobs": 5
     }
   }
   ```

3. **Disable unnecessary components**:
   ```json
   {
     "M365Components": {
       "ExchangeOnline": {
         "Enabled": false,
         "ExportEmails": false
       }
     }
   }
   ```

4. **Optimize SQL Server**:
   - Add indexes to frequently queried columns
   - Increase database service tier (Azure SQL)
   - Use SSD storage

### Issue: High memory usage

**Solutions**:

1. **Reduce batch size**:
   ```json
   {
     "ExportSettings": {
       "BatchSize": 50
     }
   }
   ```

2. **Disable parallel processing**:
   ```json
   {
     "ExportSettings": {
       "EnableParallelProcessing": false
     }
   }
   ```

3. **Process components one at a time**

## Excel/CSV Export Issues

### Issue: "ImportExcel module not found"

**Symptoms**:
```
The term 'Export-Excel' is not recognized
```

**Solution**:
```powershell
Install-Module -Name ImportExcel -Scope CurrentUser -Force
```

### Issue: Excel file exceeds row limit

**Symptoms**:
```
WARNING: Table exceeds Excel row limit (1,048,576 rows)
```

**Solutions**:

1. **Use CSV export instead**:
   ```powershell
   .\Scripts\Export-SQLToCSV.ps1
   ```

2. **Split large tables**:
   - Export in chunks
   - Use SQL queries to filter data

3. **Configure row limit**:
   ```json
   {
     "ExcelExportSettings": {
       "MaxRowsPerSheet": 1000000
     }
   }
   ```

### Issue: CSV encoding issues

**Symptoms**:
- Special characters appear garbled
- Unicode characters display incorrectly

**Solution**:
Already configured for UTF-8 with BOM. If issues persist:
```powershell
# Check encoding
Get-Content "export.csv" -Encoding UTF8
```

## General Errors

### Issue: "Configuration file not found"

**Symptoms**:
```
✗ Configuration file not found: Config\config.json
```

**Solution**:
```powershell
# Verify files exist
Test-Path Config\config.json
Test-Path Config\credentials.json

# If missing, copy templates
Copy-Item Config\credentials.template.json Config\credentials.json
```

### Issue: "Table already exists" during schema creation

**This is normal** - the solution uses `IF NOT EXISTS` checks.

If issues persist:
```sql
-- Drop and recreate (WARNING: deletes data)
DROP TABLE AAD_Users;
-- Then run export again
```

### Issue: PowerShell execution policy

**Symptoms**:
```
...ps1 cannot be loaded because running scripts is disabled on this system
```

**Solution**:
```powershell
# Check current policy
Get-ExecutionPolicy

# Set policy for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run with bypass
PowerShell.exe -ExecutionPolicy Bypass -File .\Scripts\Export-M365ToSQL.ps1
```

## Debugging Tips

### Enable Verbose Output
```powershell
.\Scripts\Export-M365ToSQL.ps1 -Verbose
```

### Check Audit Logs
```sql
SELECT TOP 100 *
FROM AuditLog
WHERE Category = 'Error'
ORDER BY Timestamp DESC;
```

### Test Individual Components
```powershell
# Test authentication
. .\Modules\Auth-GraphAPI.ps1
Initialize-GraphAuth -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz"
Test-GraphConnection

# Test database
. .\Modules\Database-Functions.ps1
Initialize-DatabaseConnection -ServerName "server" -DatabaseName "db" -UseWindowsAuth $false -Username "user" -Password "pass"
Test-DatabaseConnection

# Test specific export
.\Scripts\Export-M365ToSQL.ps1 -Components @("AzureAD") -Verbose
```

### Review Export History
```sql
SELECT *
FROM ExportHistory
WHERE Status = 'Failed'
ORDER BY StartTime DESC;
```

## Getting More Help

If issues persist:

1. **Check Documentation**:
   - [SETUP.md](SETUP.md) - Setup instructions
   - [API-PERMISSIONS.md](API-PERMISSIONS.md) - Permission requirements
   - [COMPLIANCE.md](COMPLIANCE.md) - Compliance features

2. **Enable Detailed Logging**:
   ```json
   {
     "GeneralSettings": {
       "LogLevel": "Debug",
       "EnableDetailedErrorMessages": true
     }
   }
   ```

3. **Check Logs**:
   - `Logs/` directory
   - `Logs/Audit/` directory
   - SQL audit logs table

4. **Report Issues**:
   - Include error messages
   - Include relevant configuration (remove secrets!)
   - Include PowerShell version
   - Include SQL Server version

## Common SQL Queries for Troubleshooting

**Failed exports**:
```sql
SELECT * FROM ExportHistory WHERE Status = 'Failed' ORDER BY StartTime DESC;
```

**Error audit logs**:
```sql
SELECT * FROM AuditLog WHERE Details LIKE '%error%' ORDER BY Timestamp DESC;
```

**Last successful export per component**:
```sql
SELECT
    ComponentName,
    MAX(EndTime) AS LastSuccessfulExport,
    MAX(RecordsExported) AS RecordsExported
FROM ExportHistory
WHERE Status = 'Completed'
GROUP BY ComponentName;
```

---

**Need more help?** Contact your system administrator or Microsoft 365 support.
