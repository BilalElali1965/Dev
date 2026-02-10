# M365 Shared Mailbox Migration Solution

A comprehensive PowerShell solution for exporting and importing M365 Shared Mailboxes with full configuration preservation including permissions, aliases, archive status, and litigation hold settings.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Export Instructions](#export-instructions)
- [Import Instructions](#import-instructions)
- [CSV File Format](#csv-file-format)
- [Examples](#examples)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This solution provides two PowerShell scripts for managing M365 Shared Mailbox migrations:

- **Export-M365SharedMailboxes.ps1**: Exports all shared mailboxes from your M365 tenant to a CSV file
- **Import-M365SharedMailboxes.ps1**: Imports shared mailboxes from the CSV file with full configuration

### Features
- ✅ Export all shared mailboxes with complete configuration
- ✅ Preserve mailbox permissions (owners, members, send on behalf)
- ✅ Maintain email aliases and routing configuration
- ✅ Capture archive and litigation hold settings
- ✅ WhatIf mode for safe testing before import
- ✅ Comprehensive error handling and logging
- ✅ Progress tracking for long operations
- ✅ Modern authentication with MFA support

## Prerequisites

### PowerShell Requirements
- **PowerShell 5.1** or higher (PowerShell 7+ recommended for better performance)
- Windows, macOS, or Linux (with PowerShell 7+)

To check your PowerShell version:
```powershell
$PSVersionTable.PSVersion
```

### Required Modules
- **ExchangeOnlineManagement** (v3.0.0 or higher)

### Required Permissions
Your account must have one of the following roles in Microsoft 365:
- Exchange Administrator
- Global Administrator
- Compliance Administrator (for litigation hold operations)

### Network Requirements
- Internet connectivity
- Access to Exchange Online endpoints
- Firewall rules allowing connections to `outlook.office365.com`

## Installation

### Step 1: Install PowerShell (if needed)

**Windows**: PowerShell 5.1 is pre-installed on Windows 10/11

**macOS/Linux**: Install PowerShell 7+
```bash
# macOS (using Homebrew)
brew install --cask powershell

# Ubuntu/Debian
sudo apt-get install -y powershell

# For other platforms, see: https://docs.microsoft.com/powershell/scripting/install/installing-powershell
```

### Step 2: Install ExchangeOnlineManagement Module

Open PowerShell as Administrator (Windows) or with sudo (macOS/Linux):

```powershell
# Install the module
Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber

# Verify installation
Get-Module -ListAvailable ExchangeOnlineManagement
```

### Step 3: Download the Scripts

Clone this repository or download the files:
```powershell
# Navigate to your desired directory
cd C:\Scripts  # Windows
# cd ~/Scripts  # macOS/Linux

# If using Git
git clone <repository-url>

# Or download the following files manually:
# - Export-M365SharedMailboxes.ps1
# - Import-M365SharedMailboxes.ps1
# - SharedMailboxes_Template.csv
```

### Step 4: Set Execution Policy (Windows)

Allow script execution (required on Windows):
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Quick Start

### Export Shared Mailboxes
```powershell
# Navigate to the script directory
cd C:\Scripts\M365-SharedMailbox-Migration

# Run the export script
.\Export-M365SharedMailboxes.ps1

# You'll be prompted to sign in to Exchange Online
# The export will be saved to: SharedMailboxes_Export_YYYYMMDD_HHMMSS.csv
```

### Import Shared Mailboxes (Preview)
```powershell
# First, test with WhatIf mode
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -WhatIf

# If the preview looks good, run the actual import
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv"
```

## Export Instructions

### Basic Export

The simplest way to export all shared mailboxes:

```powershell
.\Export-M365SharedMailboxes.ps1
```

This will:
1. Check for the required ExchangeOnlineManagement module
2. Connect to Exchange Online (you'll be prompted to sign in)
3. Retrieve all shared mailboxes in your tenant
4. Export them to `SharedMailboxes_Export_YYYYMMDD_HHMMSS.csv`
5. Create a log file with the same name but `.log` extension

### Export to a Specific Location

```powershell
.\Export-M365SharedMailboxes.ps1 -OutputPath "C:\Exports\MySharedMailboxes.csv"
```

### Export with Verbose Output

For detailed diagnostic information:

```powershell
.\Export-M365SharedMailboxes.ps1 -Verbose
```

### What Gets Exported

The export script captures:
- **Display Name**: The mailbox display name
- **Mailbox Type**: Always "SharedMailbox"
- **Email Address**: Primary SMTP address
- **UPN**: UserPrincipalName
- **Owners**: Users with FullAccess permissions
- **Members**: All users with mailbox permissions
- **Email Aliases**: All secondary SMTP addresses
- **Mailbox Size**: Current size with total item size
- **Send On Behalf**: Users granted SendOnBehalf permission
- **Require Sender Auth**: Whether sender authentication is required
- **Archive Status**: Whether archive is enabled
- **Legal Hold**: Litigation hold status
- **Litigation Duration**: Hold duration if applicable
- **Object ID**: Azure AD Object ID

### Output Files

After running the export, you'll find:
- **CSV File**: Contains all mailbox data (e.g., `SharedMailboxes_Export_20240210_120000.csv`)
- **Log File**: Detailed execution log (e.g., `SharedMailboxes_Export_20240210_120000.log`)

### Troubleshooting Export Issues

**Issue: "ExchangeOnlineManagement module not found"**
```powershell
Install-Module -Name ExchangeOnlineManagement -Force
```

**Issue: "Access denied" or "Insufficient permissions"**
- Verify you have Exchange Administrator or Global Administrator role
- Contact your M365 administrator for role assignment

**Issue: Connection timeout**
- Check your internet connection
- Verify firewall settings allow Exchange Online access
- Try disconnecting and reconnecting:
  ```powershell
  Disconnect-ExchangeOnline -Confirm:$false
  .\Export-M365SharedMailboxes.ps1
  ```

**Issue: "No shared mailboxes found"**
- This is normal if your tenant has no shared mailboxes
- Verify by running: `Get-Mailbox -RecipientTypeDetails SharedMailbox`

## Import Instructions

### Pre-Import Checklist

Before importing:
1. ✅ Review the CSV file for accuracy
2. ✅ Ensure user accounts referenced in permissions exist in the target tenant
3. ✅ Verify email domains are configured in the target tenant
4. ✅ Check for naming conflicts with existing mailboxes
5. ✅ Run in WhatIf mode first

### Import with WhatIf Mode (Recommended First Step)

**Always test with WhatIf before importing:**

```powershell
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -WhatIf
```

This shows what would happen without making any changes. Review the output carefully.

### Basic Import

```powershell
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv"
```

You'll be prompted to confirm before proceeding.

### Import Without Confirmation Prompts

```powershell
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -Force
```

### Skip Existing Mailboxes

If you want to import only new mailboxes and skip existing ones:

```powershell
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -SkipExisting
```

Default behavior (without `-SkipExisting`) is to update existing mailboxes with new settings.

### Import Process

The import script performs these steps for each mailbox:

1. **Validation**: Checks for required fields (Display Name, Email Address)
2. **Existence Check**: Determines if mailbox already exists
3. **Creation/Update**: Creates new mailbox or updates existing one
4. **Email Aliases**: Adds all secondary email addresses
5. **Permissions**: Grants FullAccess to members
6. **Send On Behalf**: Configures SendOnBehalf permissions
7. **Archive**: Enables archive if specified
8. **Litigation Hold**: Applies litigation hold settings if specified
9. **Authentication**: Sets RequireSenderAuthenticationEnabled flag

### Reviewing and Modifying the CSV

You can edit the CSV file before import to:
- Filter which mailboxes to import (delete rows)
- Change display names or email addresses
- Modify permissions or aliases
- Adjust settings like RequireSenderAuth

**Important**: Keep the header row intact and maintain the column structure.

### Import Output

After import, you'll see:
- **Summary Report**: Success/failure counts
- **Import Log**: Detailed log file (e.g., `SharedMailboxes_Export_20240210_120000_import.log`)

### Troubleshooting Import Issues

**Issue: "Mailbox already exists"**
- Use `-SkipExisting` to skip, or remove `-SkipExisting` to update settings
- Or delete the mailbox first: `Remove-Mailbox -Identity <email> -Confirm:$false`

**Issue: "User not found" when setting permissions**
- Ensure the user exists in the target tenant
- Update the CSV with correct user identities (UPN or email)
- Or remove the user from the permissions column

**Issue: "Domain not found" when adding aliases**
- Verify the domain is added to your M365 tenant
- Remove invalid aliases from the CSV
- Or add the domain first in M365 Admin Center

**Issue: "Cannot enable archive"**
- Verify your license supports archive mailboxes
- Check that Exchange Online Plan 2 or appropriate license is available

## CSV File Format

### Column Descriptions

| Column Name | Data Type | Description | Example |
|------------|-----------|-------------|---------|
| Source Display Name | String | Display name of the mailbox | "Sales Team" |
| Mailbox Type | String | Always "SharedMailbox" | "SharedMailbox" |
| Source Email Address | String | Primary SMTP address | "sales@contoso.com" |
| Source UPN | String | UserPrincipalName | "sales@contoso.com" |
| Source Owner | String | Users with owner/FullAccess (semicolon-separated) | "john@contoso.com; jane@contoso.com" |
| Source Members | String | All users with permissions (semicolon-separated) | "john@contoso.com; jane@contoso.com" |
| Source Email Alias(es) | String | Secondary email addresses (semicolon-separated) | "info@contoso.com; contact@contoso.com" |
| Current Mailbox Size | String | Total mailbox size | "1.5 GB (1,610,612,736 bytes)" |
| Grant Send On Behalf | String | Users with SendOnBehalf (semicolon-separated) | "manager@contoso.com" |
| Require Sender Auth | Boolean | Whether sender authentication is required | "True" or "False" |
| Archive Status | String | Archive mailbox status | "Enabled" or "Disabled" |
| Legal Hold | String | Litigation hold status | "Enabled" or "Disabled" |
| Litigation Duration | String | Hold duration in days | "Unlimited" or "365" |
| Source Object ID | String | Azure AD Object ID | "a1b2c3d4-e5f6-7890-abcd-ef1234567890" |

### Example CSV Rows

```csv
Source Display Name,Mailbox Type,Source Email Address,Source UPN,Source Owner,Source Members,Source Email Alias(es),Current Mailbox Size,Grant Send On Behalf,Require Sender Auth,Archive Status,Legal Hold,Litigation Duration,Source Object ID
Sales Team,SharedMailbox,sales@contoso.com,sales@contoso.com,john@contoso.com; jane@contoso.com,john@contoso.com; jane@contoso.com; bob@contoso.com,info@contoso.com; contact@contoso.com,1.5 GB (1610612736 bytes),manager@contoso.com,True,Enabled,Disabled,,a1b2c3d4-e5f6-7890-abcd-ef1234567890
Support Team,SharedMailbox,support@contoso.com,support@contoso.com,admin@contoso.com,admin@contoso.com; support1@contoso.com,help@contoso.com,500 MB (524288000 bytes),,False,Disabled,Enabled,Unlimited,b2c3d4e5-f6g7-8901-bcde-fg2345678901
```

### Manual CSV Editing Guidelines

When editing the CSV manually:

1. **Keep Headers**: Don't modify column names
2. **Use UTF-8 Encoding**: Save with UTF-8 encoding to preserve special characters
3. **Semicolon Separators**: Use semicolons to separate multiple values (emails, users)
4. **No Extra Commas**: Be careful not to add commas within fields
5. **Quote Values**: Excel may add quotes automatically - this is fine
6. **Boolean Values**: Use "True" or "False" for Require Sender Auth
7. **Empty Fields**: Leave fields empty if no value (don't use "N/A" or "null")

### Using the Template

A template file `SharedMailboxes_Template.csv` is provided with:
- Correct header structure
- Example rows showing proper formatting
- Comments explaining each field

## Examples

### Example 1: Basic Export and Import

```powershell
# Step 1: Export from source tenant
.\Export-M365SharedMailboxes.ps1

# Step 2: Download the CSV file (if exporting from a different tenant)
# Transfer SharedMailboxes_Export_20240210_120000.csv to target environment

# Step 3: Preview import
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -WhatIf

# Step 4: Import for real
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv"
```

### Example 2: Export to Custom Location with Verbose Logging

```powershell
.\Export-M365SharedMailboxes.ps1 -OutputPath "D:\Backups\M365\SharedMailboxes_$(Get-Date -Format 'yyyyMMdd').csv" -Verbose
```

### Example 3: Import Only New Mailboxes

```powershell
# Import but skip any mailboxes that already exist
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes.csv" -SkipExisting -Force
```

### Example 4: Selective Import (Edit CSV First)

```powershell
# Step 1: Export all mailboxes
.\Export-M365SharedMailboxes.ps1

# Step 2: Edit the CSV file to remove unwanted mailboxes
# Open SharedMailboxes_Export_20240210_120000.csv
# Delete rows for mailboxes you don't want to import
# Save the file

# Step 3: Import only the remaining mailboxes
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv" -WhatIf
.\Import-M365SharedMailboxes.ps1 -CsvPath ".\SharedMailboxes_Export_20240210_120000.csv"
```

### Example 5: Automated Export with Scheduled Task

Create a scheduled task to export shared mailboxes daily:

```powershell
# Create a scheduled script
$scriptPath = "C:\Scripts\M365-SharedMailbox-Migration\Export-M365SharedMailboxes.ps1"
$outputPath = "C:\Backups\SharedMailboxes_$(Get-Date -Format 'yyyyMMdd').csv"

# Create credentials file (one-time setup)
# Note: Store credentials securely - see Security Best Practices

# Schedule the task (Windows)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$scriptPath`" -OutputPath `"$outputPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "M365-SharedMailbox-Export" -Action $action -Trigger $trigger -Description "Daily export of M365 shared mailboxes"
```

### Example 6: Cross-Tenant Migration

```powershell
# Tenant A (Source) - Export
Connect-ExchangeOnline -UserPrincipalName admin@tenantA.com
.\Export-M365SharedMailboxes.ps1 -OutputPath "C:\Migration\TenantA_SharedMailboxes.csv"
Disconnect-ExchangeOnline -Confirm:$false

# Tenant B (Target) - Import with modifications
# Edit CSV to update email domains from tenantA.com to tenantB.com

Connect-ExchangeOnline -UserPrincipalName admin@tenantB.com
.\Import-M365SharedMailboxes.ps1 -CsvPath "C:\Migration\TenantA_SharedMailboxes.csv" -WhatIf
# Review WhatIf output
.\Import-M365SharedMailboxes.ps1 -CsvPath "C:\Migration\TenantA_SharedMailboxes.csv"
Disconnect-ExchangeOnline -Confirm:$false
```

## Security Best Practices

### Credential Management

**Don't hardcode credentials in scripts**. Use modern authentication with MFA when possible.

**For interactive sessions (recommended):**
```powershell
# Scripts prompt for credentials automatically
.\Export-M365SharedMailboxes.ps1
```

**For automation (use certificate-based auth):**
```powershell
# Set up certificate-based authentication
Connect-ExchangeOnline -CertificateThumbprint "thumbprint" -AppId "app-id" -Organization "contoso.com"
```

### Protecting Exported Data

**CSV files contain sensitive information**. Protect them:

1. **Encrypt the CSV file:**
   ```powershell
   # Windows: Use EFS or BitLocker
   # Or encrypt with password protection
   ```

2. **Store securely:**
   - Don't store in public folders or cloud storage
   - Use encrypted storage solutions
   - Delete files when no longer needed

3. **Limit access:**
   - Use file permissions to restrict access
   - Share only with authorized personnel

### Audit Logging

**Enable audit logging for compliance:**

```powershell
# Enable mailbox audit logging
Get-Mailbox -ResultSize Unlimited | Set-Mailbox -AuditEnabled $true

# Review audit logs
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -Operations New-Mailbox,Set-Mailbox
```

### Least Privilege Access

**Use appropriate admin roles:**
- Don't use Global Administrator for routine tasks
- Create dedicated service accounts for automation
- Use Azure AD Privileged Identity Management (PIM) for just-in-time access

### MFA and Conditional Access

**Enforce security policies:**
- Require MFA for admin accounts
- Use Conditional Access policies to restrict access
- Monitor sign-in logs for suspicious activity

### Regular Backups

**Backup your exports:**
```powershell
# Create timestamped backups
$backupPath = "C:\Backups\M365\$(Get-Date -Format 'yyyy-MM')"
New-Item -ItemType Directory -Path $backupPath -Force
.\Export-M365SharedMailboxes.ps1 -OutputPath "$backupPath\SharedMailboxes_$(Get-Date -Format 'yyyyMMdd').csv"
```

## Troubleshooting

### Common Issues and Solutions

#### Authentication Issues

**Problem**: "Authentication failed" or "Access token expired"

**Solution**:
```powershell
# Clear cached credentials
Disconnect-ExchangeOnline -Confirm:$false

# Reconnect
Connect-ExchangeOnline

# Run script again
.\Export-M365SharedMailboxes.ps1
```

#### Module Issues

**Problem**: "The term 'Connect-ExchangeOnline' is not recognized"

**Solution**:
```powershell
# Install the module
Install-Module -Name ExchangeOnlineManagement -Force

# Import the module
Import-Module ExchangeOnlineManagement

# Verify
Get-Command Connect-ExchangeOnline
```

#### Permission Issues

**Problem**: "Access denied" or "Insufficient permissions"

**Solution**:
- Verify you have Exchange Administrator role
- Check Azure AD role assignments
- Contact your Global Administrator

#### Performance Issues

**Problem**: Export or import taking too long

**Solution**:
- Run during off-peak hours
- Use PowerShell 7 for better performance
- Process in smaller batches by editing CSV
- Ensure good network connectivity

#### CSV Format Issues

**Problem**: "Invalid CSV file structure" or import errors

**Solution**:
- Verify CSV has all required columns
- Check for extra commas or quote marks
- Save with UTF-8 encoding
- Use the provided template as reference

### Getting Help

**Check the logs:**
```powershell
# Export log
Get-Content .\SharedMailboxes_Export_20240210_120000.log

# Import log
Get-Content .\SharedMailboxes_Export_20240210_120000_import.log
```

**Enable verbose output:**
```powershell
.\Export-M365SharedMailboxes.ps1 -Verbose
.\Import-M365SharedMailboxes.ps1 -CsvPath "file.csv" -Verbose
```

**Test connectivity:**
```powershell
# Test Exchange Online connection
Test-Connection outlook.office365.com

# Verify you can list mailboxes
Get-Mailbox -ResultSize 1
```

### Support Resources

- **Microsoft Exchange Online Documentation**: https://docs.microsoft.com/exchange/
- **PowerShell Gallery**: https://www.powershellgallery.com/packages/ExchangeOnlineManagement
- **Microsoft 365 Admin Center**: https://admin.microsoft.com

## License

This solution is provided as-is for use in M365 environments. Please review your organization's policies before use.

## Contributing

Contributions are welcome! Please ensure:
- Code follows PowerShell best practices
- Scripts are tested with PowerShell 5.1 and 7+
- Documentation is updated for new features
- Error handling is comprehensive

## Version History

- **v1.0.0** (2024-02-10): Initial release
  - Export script with full mailbox configuration
  - Import script with WhatIf mode
  - Comprehensive documentation
  - Template CSV file
