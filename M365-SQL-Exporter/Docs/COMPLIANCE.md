# Compliance Documentation

This document describes the compliance features of the M365-SQL-Exporter solution and how to use them to meet GDPR, HIPAA, and SOC2 requirements.

## Overview

The M365-SQL-Exporter is designed with compliance in mind, providing features to help organizations meet regulatory requirements for data protection, privacy, and security.

## Supported Compliance Standards

- **GDPR** (General Data Protection Regulation)
- **HIPAA** (Health Insurance Portability and Accountability Act)
- **SOC2** (Service Organization Control 2)

## GDPR Compliance

### Data Protection Principles

#### 1. Lawfulness, Fairness, and Transparency
- **Audit Logging**: All data access is logged with timestamps and user information
- **Transparency**: Clear documentation of data collected and processing activities

#### 2. Purpose Limitation
- **Configurable Components**: Only enable and export data needed for your purpose
- **Data Minimization**: Option to exclude unnecessary fields

#### 3. Data Minimization
```json
{
  "ComplianceSettings": {
    "GDPR": {
      "Enabled": true,
      "EnableDataMinimization": true,
      "PseudonymizeFields": ["EmailAddress", "DisplayName"]
    }
  }
}
```

**Features**:
- Export only necessary M365 components
- Exclude sensitive fields from export
- Pseudonymization options for PII

#### 4. Accuracy
- **Real-time Export**: Data exported directly from Microsoft 365 source
- **Audit Trail**: Track when data was exported and any modifications

#### 5. Storage Limitation
```json
{
  "ComplianceSettings": {
    "GDPR": {
      "DataRetentionDays": 365,
      "EnableAutoCleanup": true
    }
  }
}
```

**Features**:
- Configurable data retention periods
- Automatic cleanup of old exports
- Deletion capabilities for right to erasure

#### 6. Integrity and Confidentiality
- **Encryption**: TLS/SSL for all API communications
- **Secure Storage**: Credentials stored separately from code
- **Access Controls**: Database-level security
- **Integrity Checks**: Checksums for exported data (optional)

### GDPR Rights Support

#### Right to Access
Export user data for subject access requests:
```sql
-- Export all data for a specific user
SELECT * FROM AAD_Users WHERE UserPrincipalName = 'user@domain.com';
SELECT * FROM OneDrive_Drives WHERE OwnerUserPrincipalName = 'user@domain.com';
```

#### Right to Erasure (Right to be Forgotten)
Delete user data from exports:
```sql
-- Delete user data
DELETE FROM AAD_Users WHERE UserPrincipalName = 'user@domain.com';
DELETE FROM OneDrive_Drives WHERE OwnerUserPrincipalName = 'user@domain.com';

-- Log deletion for compliance
INSERT INTO AuditLog (Category, Action, EntityType, EntityId, Details, ExecutedBy)
VALUES ('GDPR', 'RightToErasure', 'User', 'user@domain.com', 'Data deleted per GDPR request', SYSTEM_USER);
```

#### Right to Portability
Export user data in machine-readable format:
```powershell
# Export specific user data to CSV
.\Scripts\Export-SQLToCSV.ps1 -TableNames @("AAD_Users") `
    -WhereClause "UserPrincipalName = 'user@domain.com'"
```

### Data Processing Documentation

The solution logs all data processing activities:
```sql
SELECT
    Category,
    Action,
    EntityType,
    COUNT(*) AS ProcessingCount,
    MIN(Timestamp) AS FirstProcessing,
    MAX(Timestamp) AS LastProcessing
FROM AuditLog
WHERE Category IN ('Export', 'DataAccess')
GROUP BY Category, Action, EntityType;
```

## HIPAA Compliance

### Administrative Safeguards

#### Access Management
- **Audit Logging**: All data access logged with user identity
- **Session Tracking**: Unique session IDs for each export operation
- **Automatic Session Timeout**: Configurable timeout (default: 30 minutes)

```json
{
  "ComplianceSettings": {
    "HIPAA": {
      "Enabled": true,
      "SessionTimeoutMinutes": 30
    }
  }
}
```

#### Audit Controls
- **Comprehensive Audit Trail**: All operations logged
- **Access Logs**: Who accessed what data and when
- **Modification Tracking**: Changes to configurations and data

View access logs:
```sql
SELECT
    ExecutedBy,
    Action,
    EntityType,
    EntityId,
    Timestamp,
    Details
FROM AuditLog
WHERE Category = 'DataAccess'
ORDER BY Timestamp DESC;
```

### Physical Safeguards

#### Facility Access Controls
- **Database Security**: SQL Server authentication and authorization
- **Network Security**: Firewall rules and IP restrictions (Azure SQL)

#### Workstation Security
- **Credential Protection**: No hardcoded secrets
- **Secure Configuration**: Credentials file excluded from version control

### Technical Safeguards

#### Access Control
```sql
-- Create read-only user for reporting
CREATE USER ReportingUser WITH PASSWORD = 'SecurePassword123!';
GRANT SELECT ON AAD_Users TO ReportingUser;
GRANT SELECT ON ExportHistory TO ReportingUser;
GRANT SELECT ON AuditLog TO ReportingUser;
```

#### Audit Controls
```json
{
  "AuditSettings": {
    "EnableAuditLogging": true,
    "AuditLogRetentionDays": 730,
    "LogAPIRequests": true,
    "LogDatabaseOperations": true,
    "LogDataAccess": true
  }
}
```

#### Integrity Controls
```json
{
  "ComplianceSettings": {
    "HIPAA": {
      "EnableIntegrityChecks": true,
      "RequireSecureTransmission": true
    }
  }
}
```

**Features**:
- Checksums for data integrity verification
- TLS/SSL for all transmissions
- Validation of exported data

#### Transmission Security
- **TLS 1.2+**: All Microsoft Graph API calls use TLS
- **Encrypted Database Connections**: SQL Server encryption

### HIPAA Breach Notification

Monitor for unusual access patterns:
```sql
-- Detect unusual access volumes
SELECT
    ExecutedBy,
    Category,
    COUNT(*) AS AccessCount,
    CAST(Timestamp AS DATE) AS AccessDate
FROM AuditLog
WHERE Category = 'DataAccess'
  AND Timestamp >= DATEADD(DAY, -7, GETDATE())
GROUP BY ExecutedBy, Category, CAST(Timestamp AS DATE)
HAVING COUNT(*) > 1000
ORDER BY AccessCount DESC;
```

## SOC2 Compliance

### Security Principle

#### Access Controls
- **Authentication**: Azure AD app authentication with client credentials
- **Authorization**: Role-based database access
- **Audit Logging**: All security events logged

#### Network Security
- **Encrypted Communications**: TLS/SSL for all API calls
- **Firewall Rules**: Database-level IP restrictions
- **Secure Credentials**: External credential storage

### Availability Principle

#### Error Handling
- **Retry Logic**: Automatic retry for transient failures
- **Exponential Backoff**: Rate limiting protection
- **Checkpoint/Resume**: Continue from last successful point

#### Monitoring
```sql
-- Monitor export success rate
SELECT
    ComponentName,
    COUNT(*) AS TotalExports,
    SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) AS SuccessfulExports,
    SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) AS FailedExports,
    (SUM(CASE WHEN Status = 'Completed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS SuccessRate
FROM ExportHistory
WHERE StartTime >= DATEADD(DAY, -30, GETDATE())
GROUP BY ComponentName;
```

### Confidentiality Principle

#### Data Encryption
- **In Transit**: TLS/SSL encryption
- **At Rest**: Database-level encryption (configure in SQL Server)

#### Access Restrictions
- **Least Privilege**: Minimal permissions granted
- **Segregation of Duties**: Separate read-only and write users

```sql
-- Read-only user for compliance auditors
CREATE USER ComplianceAuditor WITH PASSWORD = 'SecurePassword123!';
GRANT SELECT ON AuditLog TO ComplianceAuditor;
GRANT SELECT ON ExportHistory TO ComplianceAuditor;
-- No access to actual M365 data
```

### Processing Integrity Principle

#### Data Validation
- **Schema Validation**: Automatic table creation with proper data types
- **Referential Integrity**: Foreign key relationships where applicable
- **Data Type Enforcement**: Proper SQL data types for each field

#### Change Management
```json
{
  "ComplianceSettings": {
    "SOC2": {
      "Enabled": true,
      "EnableChangeTracking": true,
      "EnableMonitoring": true
    }
  }
}
```

Track configuration changes:
```sql
SELECT
    ConfigKey,
    ConfigValue,
    LastModified
FROM Configuration
ORDER BY LastModified DESC;
```

### Privacy Principle (if applicable)

#### Data Collection Notice
- Document what data is collected
- Purpose of data collection
- Retention period
- Who has access

#### User Consent (if applicable)
- Configure data minimization
- Allow opt-out of certain data types
- Provide data deletion capabilities

## Compliance Reporting

### Generate Compliance Reports

```powershell
# Generate GDPR compliance report
. .\Modules\Audit-Logging.ps1
New-ComplianceReport -ComplianceStandard "GDPR" `
    -OutputPath "C:\Reports\GDPR-Report-$(Get-Date -Format 'yyyyMMdd').html" `
    -StartDate (Get-Date).AddDays(-30)

# Generate HIPAA audit report
New-ComplianceReport -ComplianceStandard "HIPAA" `
    -OutputPath "C:\Reports\HIPAA-Report-$(Get-Date -Format 'yyyyMMdd').html" `
    -StartDate (Get-Date).AddDays(-90)

# Export audit logs
Export-AuditLogs -OutputPath "C:\Reports\AuditLogs.csv" `
    -Format CSV `
    -StartDate (Get-Date).AddDays(-365)
```

### Audit Queries

**Data Access Summary**:
```sql
SELECT
    CAST(Timestamp AS DATE) AS Date,
    Category,
    COUNT(*) AS AccessCount,
    COUNT(DISTINCT ExecutedBy) AS UniqueUsers
FROM AuditLog
WHERE Timestamp >= DATEADD(DAY, -30, GETDATE())
GROUP BY CAST(Timestamp AS DATE), Category
ORDER BY Date DESC;
```

**Export History**:
```sql
SELECT
    ComponentName,
    ExportMode,
    Status,
    RecordsExported,
    ExecutedBy,
    StartTime,
    EndTime,
    DATEDIFF(SECOND, StartTime, EndTime) AS DurationSeconds
FROM ExportHistory
WHERE StartTime >= DATEADD(DAY, -90, GETDATE())
ORDER BY StartTime DESC;
```

**Failed Operations**:
```sql
SELECT
    ComponentName,
    Status,
    ErrorMessage,
    ExecutedBy,
    StartTime
FROM ExportHistory
WHERE Status = 'Failed'
  AND StartTime >= DATEADD(DAY, -30, GETDATE())
ORDER BY StartTime DESC;
```

## Best Practices

### 1. Regular Audits
- Review audit logs monthly
- Investigate unusual access patterns
- Generate compliance reports quarterly

### 2. Access Control
- Use principle of least privilege
- Create separate database users for different roles
- Review and revoke unnecessary access

### 3. Data Retention
- Configure appropriate retention periods
- Enable auto-cleanup for old data
- Document retention policies

### 4. Security
- Rotate credentials regularly (every 6-12 months)
- Use strong passwords
- Enable MFA for admin accounts
- Keep audit logs for required period (typically 6-7 years)

### 5. Documentation
- Maintain data processing records
- Document compliance procedures
- Keep export logs and audit trails
- Update privacy policies as needed

### 6. Incident Response
- Monitor for security events
- Have a breach notification plan
- Maintain contact information for compliance officers
- Test incident response procedures

## Compliance Checklist

### GDPR
- [ ] Data processing documented
- [ ] Retention policies configured
- [ ] Auto-cleanup enabled
- [ ] Audit logging enabled
- [ ] Procedure for right to erasure
- [ ] Procedure for data portability
- [ ] Privacy notice updated

### HIPAA
- [ ] Access controls implemented
- [ ] Audit logs enabled and retained
- [ ] Session timeouts configured
- [ ] Integrity checks enabled
- [ ] Secure transmission verified
- [ ] Breach notification procedure documented
- [ ] Regular security assessments scheduled

### SOC2
- [ ] Change tracking enabled
- [ ] Monitoring configured
- [ ] Access controls documented
- [ ] Error handling tested
- [ ] Audit logs retained
- [ ] Encryption verified
- [ ] Incident response plan documented

## Resources

- [GDPR Official Text](https://gdpr-info.eu/)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [SOC2 Compliance Guide](https://www.aicpa.org/soc4so)
- [Microsoft 365 Compliance](https://docs.microsoft.com/en-us/microsoft-365/compliance/)

---

**Last Updated**: 2026-02-07  
**Next**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
