# M365 to SQL Database Exporter

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-green.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

A comprehensive, production-ready PowerShell solution for exporting Microsoft 365 data to SQL Server with full compliance features, audit logging, and export capabilities to Excel and CSV formats.

## 🌟 Features

### Comprehensive M365 Data Export
- **Azure Active Directory**: Users, groups, devices, service principals, applications
- **Microsoft Teams**: Teams, channels, members, settings
- **SharePoint Online**: Sites, lists, libraries, permissions
- **OneDrive for Business**: Drives, files, folders, permissions, storage metrics
- **Planner**: Plans, buckets, tasks with full details
- **Extensible**: Easy to add more M365 services

### Enterprise-Grade Capabilities
- ✅ **Full and Incremental Export Modes**: Optimize performance with delta synchronization
- ✅ **Auto-Schema Creation**: Automatically creates SQL database and tables
- ✅ **Audit Logging**: Comprehensive audit trail for all operations
- ✅ **Compliance Features**: GDPR, HIPAA, and SOC2 compliance support
- ✅ **Excel Export**: Export SQL data to formatted Excel workbooks
- ✅ **CSV Export**: Export SQL data to CSV with compression options
- ✅ **Error Handling**: Robust retry logic and error recovery
- ✅ **Progress Tracking**: Real-time progress indicators and ETAs
- ✅ **Security**: Secure credential management, no hardcoded secrets

## 📋 Prerequisites

- **PowerShell**: Version 5.1 or later (PowerShell 7+ recommended)
- **SQL Server**: SQL Server 2016+ or Azure SQL Database
- **Azure AD App Registration**: With appropriate Microsoft Graph API permissions
- **ImportExcel Module**: For Excel export functionality (auto-installed if missing)

## 🚀 Quick Start

### 1. Clone or Download
```powershell
git clone https://github.com/YourOrg/M365-SQL-Exporter.git
cd M365-SQL-Exporter
```

### 2. Configure Credentials
Copy the template and fill in your credentials:
```powershell
Copy-Item Config\credentials.template.json Config\credentials.json
# Edit Config\credentials.json with your values
```

### 3. Run Export
```powershell
# Full export of all enabled components
.\Scripts\Export-M365ToSQL.ps1 -ExportMode Full

# Incremental export (default)
.\Scripts\Export-M365ToSQL.ps1

# Export specific components
.\Scripts\Export-M365ToSQL.ps1 -Components @("AzureAD", "Teams")
```

### 4. Export to Excel/CSV
```powershell
# Export to Excel
.\Scripts\Export-SQLToExcel.ps1

# Export to CSV with compression
.\Scripts\Export-SQLToCSV.ps1 -CreateZip
```

## 📁 Project Structure

```
M365-SQL-Exporter/
├── Config/
│   ├── config.json                  # Main configuration
│   └── credentials.template.json    # Credentials template
├── Docs/
│   ├── SETUP.md                     # Detailed setup guide
│   ├── API-PERMISSIONS.md           # Required API permissions
│   ├── COMPLIANCE.md                # Compliance documentation
│   ├── ARCHITECTURE.md              # Solution architecture
│   └── TROUBLESHOOTING.md           # Common issues and solutions
├── Modules/
│   ├── Auth-GraphAPI.ps1            # Authentication module
│   ├── Database-Functions.ps1       # Database operations
│   ├── Audit-Logging.ps1            # Audit logging
│   ├── Validate-Config.ps1          # Configuration validation
│   ├── Collector-AzureAD.ps1        # Azure AD data collectors
│   └── Collector-M365Services.ps1   # M365 services collectors
├── Scripts/
│   ├── Export-M365ToSQL.ps1         # Main export script
│   ├── Export-SQLToExcel.ps1        # SQL to Excel export
│   └── Export-SQLToCSV.ps1          # SQL to CSV export
├── SQL/
│   ├── schema-creation.sql          # Database schema
│   └── sample-queries.sql           # Useful reporting queries
└── README.md                        # This file
```

## 🔧 Configuration

### Main Configuration (`Config/config.json`)
Customize export settings, enable/disable components, and configure compliance features:
- Export batch sizes and parallelism
- Component-specific settings
- Compliance options (GDPR, HIPAA, SOC2)
- Audit logging preferences
- Excel/CSV export options

### Credentials (`Config/credentials.json`)
Store sensitive information securely:
- Azure AD tenant and app registration details
- SQL Server connection information
- Optional notification settings

**⚠️ Important**: Never commit `credentials.json` to version control!

## 📊 Exported Data

The solution creates optimized SQL tables for each M365 component:

### Azure AD Tables
- `AAD_Users` - User accounts with sign-in activity and licenses
- `AAD_Groups` - All group types with member counts
- `AAD_Devices` - Registered and managed devices
- `AAD_ServicePrincipals` - Service principals and applications

### Microsoft 365 Services Tables
- `Teams_Teams` - Microsoft Teams and settings
- `SharePoint_Sites` - SharePoint site collections
- `OneDrive_Drives` - OneDrive accounts with storage metrics
- `Planner_Plans` - Planner plans
- `Planner_Tasks` - Planner tasks with assignments

### System Tables
- `ExportHistory` - Tracks all export operations
- `AuditLog` - Comprehensive audit trail
- `Configuration` - System configuration storage

## 🔐 Security & Compliance

### Security Features
- ✅ Secure credential storage (externalized secrets)
- ✅ TLS/SSL for all API communications
- ✅ Input validation and sanitization
- ✅ Rate limiting and throttling
- ✅ Session-based access tracking

### Compliance Support
- **GDPR**: Data minimization, retention policies, right to erasure
- **HIPAA**: Access logging, audit trails, integrity checks
- **SOC2**: Change tracking, monitoring, comprehensive logging

See [COMPLIANCE.md](Docs/COMPLIANCE.md) for detailed compliance documentation.

## 📈 Usage Examples

### Full Export
Export all data from scratch:
```powershell
.\Scripts\Export-M365ToSQL.ps1 -ExportMode Full
```

### Incremental Export
Export only changes since last run:
```powershell
.\Scripts\Export-M365ToSQL.ps1 -ExportMode Incremental
```

### Export Specific Components
```powershell
# Export only Azure AD users and groups
.\Scripts\Export-M365ToSQL.ps1 -Components @("AzureAD")

# Export Teams and SharePoint
.\Scripts\Export-M365ToSQL.ps1 -Components @("Teams", "SharePoint")
```

### Export to Excel
```powershell
# Export all tables to Excel
.\Scripts\Export-SQLToExcel.ps1

# Export specific tables
.\Scripts\Export-SQLToExcel.ps1 -TableNames @("AAD_Users", "AAD_Groups")
```

### Export to CSV with Compression
```powershell
.\Scripts\Export-SQLToCSV.ps1 -CreateZip
```

## 📖 Documentation

Comprehensive documentation is available in the `Docs/` directory:

- **[SETUP.md](Docs/SETUP.md)** - Detailed setup and configuration guide
- **[API-PERMISSIONS.md](Docs/API-PERMISSIONS.md)** - Complete list of required Microsoft Graph API permissions
- **[COMPLIANCE.md](Docs/COMPLIANCE.md)** - Compliance features and best practices
- **[ARCHITECTURE.md](Docs/ARCHITECTURE.md)** - Solution architecture and design
- **[TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🔍 Monitoring & Reporting

### View Export History
```sql
SELECT * FROM ExportHistory ORDER BY StartTime DESC;
```

### Check Audit Logs
```sql
SELECT * FROM AuditLog WHERE Category = 'Export' ORDER BY Timestamp DESC;
```

### Use Sample Queries
Pre-built queries are available in `SQL/sample-queries.sql` for:
- User activity analysis
- Storage usage reports
- Group membership summaries
- Device compliance status
- Planner task tracking

## ⚠️ Known Limitations

1. **Exchange Online**: Email content export is not included due to volume and complexity. Email metadata can be added with additional development.
2. **Power BI**: Disabled by default. Requires Power BI admin permissions.
3. **Rate Limiting**: Microsoft Graph API has throttling limits. The solution implements automatic retry with exponential backoff.
4. **Delta Queries**: Not all Graph endpoints support delta queries. The solution uses timestamp-based filtering as a fallback.

## 🛠️ Troubleshooting

Common issues and solutions:

### Authentication Errors
- Verify Azure AD app registration credentials
- Ensure required API permissions are granted and admin-consented
- Check token expiration and refresh settings

### Database Connection Issues
- Verify SQL Server connection string
- Check firewall rules for Azure SQL Database
- Ensure database user has appropriate permissions

### Missing Data
- Check component is enabled in `config.json`
- Verify API permissions are granted
- Review audit logs for errors

See [TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md) for more details.

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Microsoft Graph API documentation
- PowerShell community
- ImportExcel module contributors

## 📞 Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check the [TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md) guide
- Review existing documentation

---

**Version**: 1.0.0  
**Last Updated**: 2026-02-07  
**Maintainer**: M365-SQL-Exporter Team
