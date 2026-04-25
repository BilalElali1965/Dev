# Setup Guide - M365 to SQL Database Exporter

This guide provides step-by-step instructions for setting up and configuring the M365-SQL-Exporter solution.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Azure AD App Registration](#azure-ad-app-registration)
3. [SQL Database Setup](#sql-database-setup)
4. [Configuration](#configuration)
5. [First Run](#first-run)
6. [Verification](#verification)

## Prerequisites

### Software Requirements
- **PowerShell**: Version 5.1 or later (PowerShell 7.x recommended)
  ```powershell
  $PSVersionTable.PSVersion
  ```

- **SQL Server**: One of the following:
  - SQL Server 2016 or later
  - Azure SQL Database
  - SQL Server Express (for testing)

- **PowerShell Modules** (auto-installed if missing):
  - ImportExcel (for Excel export functionality)

### Account Requirements
- **Microsoft 365**: Global Administrator or appropriate admin roles
- **Azure AD**: Application Administrator or Global Administrator
- **SQL Server**: Database creation and admin permissions

## Azure AD App Registration

### Step 1: Create App Registration

1. Sign in to the [Azure Portal](https://portal.azure.com)

2. Navigate to **Azure Active Directory** > **App registrations**

3. Click **New registration**

4. Configure the application:
   - **Name**: `M365-SQL-Exporter` (or your preferred name)
   - **Supported account types**: "Accounts in this organizational directory only"
   - **Redirect URI**: Leave blank
   - Click **Register**

5. Note the following values (you'll need them later):
   - **Application (client) ID**
   - **Directory (tenant) ID**

### Step 2: Create Client Secret

1. In your app registration, go to **Certificates & secrets**

2. Click **New client secret**

3. Configure:
   - **Description**: `M365-SQL-Exporter Secret`
   - **Expires**: Choose appropriate duration (12-24 months recommended)
   - Click **Add**

4. **Important**: Copy the **Value** immediately - it won't be shown again!

### Step 3: Grant API Permissions

1. In your app registration, go to **API permissions**

2. Click **Add a permission** > **Microsoft Graph** > **Application permissions**

3. Add the following permissions (see [API-PERMISSIONS.md](API-PERMISSIONS.md) for detailed list):

   **Azure AD Permissions:**
   - `User.Read.All` - Read all users
   - `Group.Read.All` - Read all groups
   - `Device.Read.All` - Read all devices
   - `Application.Read.All` - Read all applications
   - `Directory.Read.All` - Read directory data

   **Microsoft 365 Permissions:**
   - `Sites.Read.All` - Read all SharePoint sites
   - `Files.Read.All` - Read all files
   - `Team.ReadBasic.All` - Read all teams
   - `TeamSettings.Read.All` - Read team settings
   - `Tasks.Read.All` - Read all Planner tasks

   **Audit Permissions:**
   - `AuditLog.Read.All` - Read audit logs (optional, for sign-in activity)

4. Click **Grant admin consent for [Your Organization]**
   - This requires Global Administrator or Privileged Role Administrator
   - Status should show green checkmarks

### Step 4: Verify Permissions

1. Ensure all permissions show **Granted for [Your Organization]**

2. If any are "Not granted":
   - Contact your Global Administrator
   - Or use an account with appropriate privileges

## SQL Database Setup

### Option 1: Azure SQL Database (Recommended for Production)

1. **Create Azure SQL Database:**
   ```powershell
   # Using Azure CLI
   az sql server create --name myserver --resource-group myResourceGroup `
       --location eastus --admin-user sqladmin --admin-password 'YourPassword123!'
   
   az sql db create --resource-group myResourceGroup --server myserver `
       --name M365ExportDB --service-objective S0
   ```

2. **Configure Firewall:**
   - Add your IP address to firewall rules
   - Or enable "Allow Azure services and resources to access this server"

3. **Get Connection Details:**
   - Server name: `myserver.database.windows.net`
   - Database name: `M365ExportDB`
   - Username: `sqladmin`
   - Password: (your password)

### Option 2: SQL Server (On-Premises or VM)

1. **Create Database:**
   ```sql
   CREATE DATABASE M365ExportDB;
   GO
   
   USE M365ExportDB;
   GO
   ```

2. **Create Login and User (SQL Authentication):**
   ```sql
   CREATE LOGIN M365ExportUser WITH PASSWORD = 'YourStrongPassword123!';
   GO
   
   USE M365ExportDB;
   GO
   
   CREATE USER M365ExportUser FOR LOGIN M365ExportUser;
   GO
   
   ALTER ROLE db_owner ADD MEMBER M365ExportUser;
   GO
   ```

3. **Enable TCP/IP** (if needed):
   - SQL Server Configuration Manager
   - Enable TCP/IP protocol
   - Restart SQL Server service

### Option 3: Auto-Create Database (Recommended)

The solution can automatically create the database if:
- `AutoCreateDatabase` is set to `true` in `config.json` (default)
- You provide credentials with database creation permissions
- Connection to SQL Server master database is successful

## Configuration

### Step 1: Create Credentials File

1. Copy the template:
   ```powershell
   Copy-Item Config\credentials.template.json Config\credentials.json
   ```

2. Edit `Config\credentials.json` with your values:
   ```json
   {
     "AzureAD": {
       "TenantId": "your-tenant-id-here",
       "ClientId": "your-client-id-here",
       "ClientSecret": "your-client-secret-here"
     },
     "Database": {
       "ServerName": "myserver.database.windows.net",
       "DatabaseName": "M365ExportDB",
       "UseWindowsAuthentication": false,
       "Username": "sqladmin",
       "Password": "YourPassword123!"
     }
   }
   ```

3. **Verify the file is in .gitignore** (it should be by default)

### Step 2: Configure Export Settings (Optional)

Edit `Config\config.json` to customize:

```json
{
  "ExportSettings": {
    "DefaultExportMode": "Incremental",
    "BatchSize": 100,
    "PageSize": 999,
    "EnableParallelProcessing": true
  },
  "M365Components": {
    "AzureAD": {
      "Enabled": true,
      "IncludeSignInActivity": true
    },
    "Teams": {
      "Enabled": true
    },
    "SharePointOnline": {
      "Enabled": true
    }
  }
}
```

### Step 3: Review Compliance Settings

If you need compliance features, review and configure:

```json
{
  "ComplianceSettings": {
    "GDPR": {
      "Enabled": true,
      "DataRetentionDays": 365,
      "EnableAutoCleanup": true
    },
    "HIPAA": {
      "Enabled": true,
      "EnableAccessLogging": true
    },
    "SOC2": {
      "Enabled": true,
      "EnableChangeTracking": true
    }
  }
}
```

## First Run

### Step 1: Test Configuration

Run the validation script:
```powershell
cd M365-SQL-Exporter
.\Modules\Validate-Config.ps1
```

Or run the main script with verbose output:
```powershell
.\Scripts\Export-M365ToSQL.ps1 -Verbose
```

### Step 2: Run Initial Export

Start with a full export to populate all data:
```powershell
.\Scripts\Export-M365ToSQL.ps1 -ExportMode Full
```

**What to expect:**
- Validation of configuration and credentials
- Authentication to Microsoft Graph API
- Database connection and schema creation
- Export of each enabled M365 component
- Progress indicators for each operation
- Summary report upon completion

### Step 3: Review Results

1. **Check Export History:**
   ```sql
   SELECT * FROM ExportHistory ORDER BY StartTime DESC;
   ```

2. **Verify Data:**
   ```sql
   SELECT COUNT(*) FROM AAD_Users;
   SELECT COUNT(*) FROM AAD_Groups;
   SELECT COUNT(*) FROM Teams_Teams;
   ```

3. **Review Audit Logs:**
   ```sql
   SELECT TOP 100 * FROM AuditLog ORDER BY Timestamp DESC;
   ```

## Verification

### Test Authentication

```powershell
# Import the auth module
. .\Modules\Auth-GraphAPI.ps1

# Initialize authentication
Initialize-GraphAuth -TenantId "your-tenant-id" `
    -ClientId "your-client-id" `
    -ClientSecret "your-client-secret"

# Test connection
Test-GraphConnection
```

Expected output:
```
Testing Graph API connectivity...
✓ Successfully connected to Microsoft Graph API
  Tenant: Your Organization Name
  Tenant ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### Test Database Connection

```powershell
# Import database module
. .\Modules\Database-Functions.ps1

# Initialize connection
Initialize-DatabaseConnection -ServerName "your-server.database.windows.net" `
    -DatabaseName "M365ExportDB" `
    -UseWindowsAuth $false `
    -Username "sqladmin" `
    -Password "YourPassword123!"

# Test connection
Test-DatabaseConnection
```

Expected output:
```
Testing database connectivity...
✓ Successfully connected to SQL Server
  Server Version: Microsoft SQL Azure (RTM) - 12.0.2000.8
```

### Test Individual Components

Export a single component to test:
```powershell
.\Scripts\Export-M365ToSQL.ps1 -Components @("AzureAD") -Verbose
```

## Troubleshooting Setup

### Common Issues

#### 1. "Failed to obtain access token"
**Cause**: Invalid credentials or insufficient permissions

**Solution**:
- Verify Tenant ID, Client ID, and Client Secret
- Ensure admin consent is granted for all API permissions
- Check if client secret has expired

#### 2. "Failed to connect to database"
**Cause**: Connection string or firewall issues

**Solution**:
- Verify server name, database name, username, password
- Check firewall rules (especially for Azure SQL)
- Test connection using SQL Server Management Studio
- Ensure SQL Server allows SQL authentication (if not using Windows Auth)

#### 3. "Insufficient privileges to query users/groups"
**Cause**: Missing API permissions or consent

**Solution**:
- Review API permissions in Azure Portal
- Ensure "Grant admin consent" is completed
- Wait a few minutes for permissions to propagate
- Try refreshing the token with `-ForceRefresh`

#### 4. "ImportExcel module not found"
**Cause**: Module not installed

**Solution**:
```powershell
Install-Module -Name ImportExcel -Scope CurrentUser -Force
```

### Getting Help

If you encounter issues:

1. **Enable verbose logging**:
   ```powershell
   .\Scripts\Export-M365ToSQL.ps1 -Verbose
   ```

2. **Check audit logs**:
   ```sql
   SELECT * FROM AuditLog WHERE Category = 'Error' ORDER BY Timestamp DESC;
   ```

3. **Review documentation**:
   - [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
   - [API-PERMISSIONS.md](API-PERMISSIONS.md)

## Next Steps

After successful setup:

1. **Schedule Regular Exports**: Set up Windows Task Scheduler or Azure Automation
2. **Configure Incremental Exports**: Use for daily/hourly updates
3. **Set Up Monitoring**: Monitor export history and audit logs
4. **Export to Excel/CSV**: Share data with stakeholders
5. **Create Reports**: Use sample queries for insights

## Security Best Practices

✅ **Never commit credentials.json to version control**  
✅ **Rotate client secrets regularly** (Azure AD app)  
✅ **Use strong passwords** for SQL Server  
✅ **Limit API permissions** to only what's needed  
✅ **Monitor audit logs** for unusual activity  
✅ **Enable MFA** for admin accounts  
✅ **Review access regularly** to Azure AD app  

---

**Next**: [API-PERMISSIONS.md](API-PERMISSIONS.md) - Complete list of required permissions
