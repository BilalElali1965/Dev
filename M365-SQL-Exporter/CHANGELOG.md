# Changelog

All notable changes to the M365-SQL-Exporter project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-07

### Added
- Initial release of M365-SQL-Exporter
- Microsoft Graph API authentication module with automatic token refresh
- SQL database connection and schema management
- Comprehensive audit logging for compliance (GDPR, HIPAA, SOC2)
- Configuration validation system
- Azure AD data collectors:
  - Users (with sign-in activity and licenses)
  - Groups (all types)
  - Devices (registered and managed)
  - Service Principals
- Microsoft 365 service collectors:
  - Microsoft Teams (teams, channels, members)
  - SharePoint Online (sites, lists, libraries)
  - OneDrive for Business (drives and storage metrics)
  - Planner (plans, buckets, tasks)
- Main export script with Full and Incremental modes
- SQL to Excel export functionality
- SQL to CSV export functionality with compression
- Auto-schema creation for SQL database
- Retry logic and error handling for API throttling
- Progress tracking and status indicators
- Export history tracking
- Comprehensive documentation:
  - README.md - Project overview
  - SETUP.md - Detailed setup guide
  - API-PERMISSIONS.md - Complete permissions list
  - COMPLIANCE.md - Compliance documentation
  - TROUBLESHOOTING.md - Common issues
  - CHANGELOG.md - Version history
- SQL schema creation script
- Sample SQL queries for reporting
- Configuration templates
- .gitignore for sensitive files

### Security
- Secure credential storage (externalized from code)
- TLS/SSL for all API communications
- Input validation and sanitization
- Rate limiting and throttling protection
- Session-based access tracking
- Audit trail for all operations

### Compliance
- GDPR compliance features:
  - Data minimization options
  - Retention policies
  - Right to erasure support
  - Data portability
- HIPAA compliance features:
  - Access logging
  - Audit trails
  - Integrity checks
  - Session timeouts
- SOC2 compliance features:
  - Change tracking
  - Monitoring capabilities
  - Comprehensive logging

### Configuration
- Configurable export modes (Full/Incremental)
- Component-based export selection
- Batch size and parallelism settings
- Compliance feature toggles
- Audit logging preferences
- Excel and CSV export options

## [Unreleased]

### Planned Features
- Delta query support for incremental exports
- Exchange Online mailbox and email export
- Power BI workspace and report export
- Additional M365 services:
  - Yammer/Viva Engage
  - OneNote notebooks
  - Forms
  - Stream videos
  - To Do tasks
  - Bookings
- Email/webhook notifications
- Advanced filtering and search
- Custom reporting dashboards
- Automated scheduling templates
- Performance optimization for large tenants (100k+ users)
- Multi-language support
- PowerShell module packaging

### Known Issues
- Exchange Online email content export not included (due to volume)
- Power BI export requires additional admin permissions
- Some Graph API endpoints have rate limiting
- Delta queries not available for all endpoints
- Large file content export may require streaming implementation

## Version History

### Version Numbering
- **MAJOR** version: Incompatible API changes
- **MINOR** version: New functionality (backward compatible)
- **PATCH** version: Bug fixes (backward compatible)

### Support Policy
- **Current version (1.0.x)**: Full support, security updates, bug fixes
- **Previous major version**: Security updates only for 6 months
- **Older versions**: No longer supported

## Migration Guide

### Future Migrations
When upgrading between versions, follow the migration guide for each version:

#### From 0.x to 1.0
Not applicable - initial release

## Security Updates

### Reporting Security Issues
To report security vulnerabilities:
1. Do NOT create a public GitHub issue
2. Email security details to: [security contact email]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Security Changelog
Security-related changes will be documented here with CVE numbers when applicable.

## Deprecation Notices

No deprecations in version 1.0.0.

Future deprecations will be announced here with:
- Feature being deprecated
- Reason for deprecation
- Replacement/alternative
- Timeline for removal

## Contributors

### Core Team
- M365-SQL-Exporter Development Team

### Special Thanks
- Microsoft Graph API team for comprehensive documentation
- PowerShell community for best practices
- ImportExcel module contributors

## Release Notes

### 1.0.0 - Initial Release

This is the first production-ready release of M365-SQL-Exporter, a comprehensive solution for exporting Microsoft 365 data to SQL Server.

**Highlights:**
- Enterprise-grade quality with comprehensive error handling
- Full compliance support (GDPR, HIPAA, SOC2)
- Secure credential management
- Automatic database schema creation
- Excel and CSV export capabilities
- Detailed audit logging
- Extensive documentation

**What's Included:**
- 7 PowerShell modules (8,000+ lines of code)
- 3 export scripts
- SQL schema and sample queries
- Complete documentation suite
- Configuration templates

**Tested With:**
- PowerShell 5.1, 7.0, 7.1, 7.2
- SQL Server 2016, 2017, 2019, 2022
- Azure SQL Database
- Microsoft Graph API v1.0 and beta

**Requirements:**
- PowerShell 5.1+
- SQL Server 2016+ or Azure SQL Database
- Azure AD App Registration
- Microsoft Graph API permissions

See [SETUP.md](Docs/SETUP.md) for installation instructions.

---

**For questions or feedback:** Open an issue on GitHub  
**Documentation:** See `/Docs` directory  
**License:** MIT License
