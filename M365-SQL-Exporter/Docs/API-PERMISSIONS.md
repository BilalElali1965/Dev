# Microsoft Graph API Permissions

This document lists all Microsoft Graph API permissions required for the M365-SQL-Exporter solution.

## Permission Type

All permissions are **Application permissions** (not Delegated permissions) because the solution runs as a service/application without user interaction.

## Required Permissions

### Azure Active Directory

| Permission | Type | Justification |
|------------|------|---------------|
| `User.Read.All` | Application | Read all user profiles, including sign-in activity and license assignments |
| `Group.Read.All` | Application | Read all groups (Microsoft 365, Security, Distribution) and memberships |
| `Device.Read.All` | Application | Read all registered and managed devices |
| `Application.Read.All` | Application | Read all application registrations and service principals |
| `Directory.Read.All` | Application | Read directory data including administrative units and roles |
| `AuditLog.Read.All` | Application | Read audit logs and sign-in logs (for user sign-in activity) |

### Microsoft Teams

| Permission | Type | Justification |
|------------|------|---------------|
| `Team.ReadBasic.All` | Application | Read basic team information (name, description, settings) |
| `TeamSettings.Read.All` | Application | Read team settings and configurations |
| `Channel.ReadBasic.All` | Application | Read basic channel information |
| `ChannelSettings.Read.All` | Application | Read channel settings |
| `TeamMember.Read.All` | Application | Read team member information |

### SharePoint Online

| Permission | Type | Justification |
|------------|------|---------------|
| `Sites.Read.All` | Application | Read all SharePoint sites, lists, and document libraries |
| `Sites.FullControl.All` | Application | (Optional) Full control for advanced scenarios - use Sites.Read.All if possible |

### OneDrive for Business

| Permission | Type | Justification |
|------------|------|---------------|
| `Files.Read.All` | Application | Read all files in OneDrive for Business |

### Microsoft Planner

| Permission | Type | Justification |
|------------|------|---------------|
| `Tasks.Read.All` | Application | Read all Planner plans, buckets, and tasks |

### Exchange Online (Optional)

| Permission | Type | Justification |
|------------|------|---------------|
| `Mail.Read` | Application | Read mailbox contents (optional, disabled by default) |
| `Calendars.Read` | Application | Read calendar events |
| `Contacts.Read` | Application | Read contacts |
| `MailboxSettings.Read` | Application | Read mailbox settings and rules |

### Power BI (Optional)

| Permission | Type | Justification |
|------------|------|---------------|
| `Workspace.Read.All` | Application | Read all Power BI workspaces (requires Power BI admin role) |
| `Report.Read.All` | Application | Read all Power BI reports |
| `Dataset.Read.All` | Application | Read all Power BI datasets |

### Additional Services (Optional)

| Permission | Type | Justification |
|------------|------|---------------|
| `Notes.Read.All` | Application | Read OneNote notebooks |
| `Organization.Read.All` | Application | Read organization information |

## Permission Configuration

### Step-by-Step Guide

1. **Navigate to Azure Portal**
   - Go to [https://portal.azure.com](https://portal.azure.com)
   - Sign in with Global Administrator account

2. **Open App Registration**
   - Azure Active Directory > App registrations
   - Select your M365-SQL-Exporter app

3. **Add Permissions**
   - API permissions > Add a permission
   - Select "Microsoft Graph"
   - Select "Application permissions"
   - Search for and select each permission listed above
   - Click "Add permissions"

4. **Grant Admin Consent**
   - Click "Grant admin consent for [Your Organization]"
   - Confirm the action
   - Verify all permissions show "Granted" status

### PowerShell Method

You can also configure permissions using PowerShell:

```powershell
# Install AzureAD module if needed
Install-Module AzureAD

# Connect to Azure AD
Connect-AzureAD

# Get your app
$app = Get-AzureADApplication -Filter "DisplayName eq 'M365-SQL-Exporter'"

# Get Microsoft Graph Service Principal
$graphSP = Get-AzureADServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"

# Define required permissions
$requiredPermissions = @(
    "User.Read.All",
    "Group.Read.All",
    "Device.Read.All",
    "Application.Read.All",
    "Directory.Read.All",
    "AuditLog.Read.All",
    "Team.ReadBasic.All",
    "TeamSettings.Read.All",
    "Sites.Read.All",
    "Files.Read.All",
    "Tasks.Read.All"
)

# Add permissions
$resourceAccess = @()
foreach ($permission in $requiredPermissions) {
    $appRole = $graphSP.AppRoles | Where-Object { $_.Value -eq $permission }
    if ($appRole) {
        $resourceAccess += [PSCustomObject]@{
            Id = $appRole.Id
            Type = "Role"
        }
    }
}

# Update app
$requiredResourceAccess = @{
    ResourceAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
    ResourceAccess = $resourceAccess
}

Set-AzureADApplication -ObjectId $app.ObjectId -RequiredResourceAccess $requiredResourceAccess
```

## Minimal Permissions

For a minimal installation that only exports Azure AD data:

### Minimal Set
- `User.Read.All`
- `Group.Read.All`
- `Device.Read.All`
- `Directory.Read.All`

This minimal set allows exporting:
- Users
- Groups
- Devices
- Service Principals

## Permission Scopes by Component

### Azure AD Component
- `User.Read.All` - Users
- `Group.Read.All` - Groups
- `Device.Read.All` - Devices
- `Application.Read.All` - Service Principals
- `Directory.Read.All` - Directory objects
- `AuditLog.Read.All` - Sign-in activity (optional)

### Teams Component
- `Team.ReadBasic.All` - Teams
- `TeamSettings.Read.All` - Team settings
- `Channel.ReadBasic.All` - Channels (beta endpoint)
- `TeamMember.Read.All` - Members

### SharePoint Component
- `Sites.Read.All` - All sites and libraries

### OneDrive Component
- `Files.Read.All` - All drives and files

### Planner Component
- `Tasks.Read.All` - All plans and tasks

## Security Considerations

### Least Privilege Principle
Only grant permissions that are necessary for your use case:
- If you don't need Teams data, don't grant Teams permissions
- If you don't need sign-in activity, skip `AuditLog.Read.All`
- Review the configuration file to enable/disable components

### Regular Reviews
- Review granted permissions quarterly
- Remove unused permissions
- Rotate client secrets every 6-12 months
- Monitor audit logs for unusual activity

### Admin Consent
All application permissions require **admin consent**:
- Only Global Administrators or Privileged Role Administrators can grant consent
- Consent is required before the app can access any data
- Consent is tenant-wide and affects all users

## Verification

### Check Permissions in Portal
1. Azure Portal > Azure AD > App registrations
2. Select your app
3. API permissions
4. Verify all permissions show "Granted for [Organization]"

### Test Permissions via PowerShell
```powershell
# Import auth module
. .\Modules\Auth-GraphAPI.ps1

# Initialize auth
Initialize-GraphAuth -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz"

# Test user access
$users = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/users?`$top=1"
if ($users) { Write-Host "✓ User.Read.All working" -ForegroundColor Green }

# Test group access
$groups = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/groups?`$top=1"
if ($groups) { Write-Host "✓ Group.Read.All working" -ForegroundColor Green }

# Test device access
$devices = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/devices?`$top=1"
if ($devices) { Write-Host "✓ Device.Read.All working" -ForegroundColor Green }
```

## Common Permission Errors

### "Insufficient privileges to complete the operation"
**Cause**: Permission not granted or consent not provided

**Solution**:
- Verify permission is added in Azure Portal
- Ensure admin consent is granted (green checkmark)
- Wait 5-10 minutes for changes to propagate
- Clear token cache and re-authenticate

### "Access is denied"
**Cause**: App doesn't have required role

**Solution**:
- Check if permission is "Delegated" instead of "Application"
- Ensure correct permission name (case-sensitive)
- Verify tenant allows application permissions

### "Permission not found"
**Cause**: Permission name is incorrect or doesn't exist

**Solution**:
- Check Microsoft Graph documentation for correct permission name
- Some permissions may be in beta and not GA
- Use exact permission names from this document

## Resources

- [Microsoft Graph Permissions Reference](https://docs.microsoft.com/en-us/graph/permissions-reference)
- [Azure AD App Registration Documentation](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
- [Microsoft Graph Explorer](https://developer.microsoft.com/en-us/graph/graph-explorer) - Test API calls

## Updates and Changes

Microsoft periodically updates Graph API permissions. Check for:
- New permissions required for new features
- Deprecated permissions that need replacement
- Permission name changes

**Last Updated**: 2026-02-07  
**Graph API Version**: v1.0 (with selected beta endpoints)

---

**Next**: [COMPLIANCE.md](COMPLIANCE.md) - Compliance features and best practices
