# Architecture Documentation

This document describes the architecture, design principles, and data flow of the M365-SQL-Exporter solution.

## System Overview

The M365-SQL-Exporter is a PowerShell-based solution that extracts data from Microsoft 365 using the Microsoft Graph API and stores it in a SQL Server database for reporting, compliance, and analysis.

```
┌─────────────────┐
│  Microsoft 365  │
│   (Graph API)   │
└────────┬────────┘
         │ HTTPS/TLS
         │ (OAuth 2.0)
         ▼
┌─────────────────────────────────┐
│    M365-SQL-Exporter            │
│  ┌───────────────────────────┐  │
│  │   Auth Module             │  │
│  │   (Token Management)      │  │
│  └───────────┬───────────────┘  │
│              │                   │
│  ┌───────────▼───────────────┐  │
│  │   Main Export Script      │  │
│  │   (Orchestration)         │  │
│  └───────────┬───────────────┘  │
│              │                   │
│  ┌───────────▼───────────────┐  │
│  │   Data Collectors         │  │
│  │   (AAD, Teams, SPO, etc)  │  │
│  └───────────┬───────────────┘  │
│              │                   │
│  ┌───────────▼───────────────┐  │
│  │   Database Module         │  │
│  │   (SQL Operations)        │  │
│  └───────────┬───────────────┘  │
│              │                   │
│  ┌───────────▼───────────────┐  │
│  │   Audit Logging           │  │
│  │   (Compliance Tracking)   │  │
│  └───────────────────────────┘  │
└─────────────┬───────────────────┘
              │ SQL Protocol
              │ (Encrypted)
              ▼
     ┌────────────────┐
     │   SQL Server   │
     │   Database     │
     └────────┬───────┘
              │
              ▼
     ┌────────────────┐
     │ Excel/CSV      │
     │ Export         │
     └────────────────┘
```

## Components

### 1. Authentication Module (`Auth-GraphAPI.ps1`)

**Purpose**: Handles Microsoft Graph API authentication using OAuth 2.0 client credentials flow.

**Key Functions**:
- `Initialize-GraphAuth()` - Sets up credentials
- `Get-GraphAccessToken()` - Obtains and caches access tokens
- `Invoke-GraphRequest()` - Makes authenticated API calls
- `Get-GraphAllPages()` - Handles paginated responses
- `Test-GraphConnection()` - Validates connectivity

**Design Patterns**:
- **Singleton Pattern**: Single token cache per session
- **Retry Pattern**: Automatic retry with exponential backoff
- **Circuit Breaker**: Handles rate limiting gracefully

**Token Management**:
```
Token Lifecycle:
1. Request token from Azure AD
2. Cache token with expiry time
3. Reuse cached token if valid (5-min buffer)
4. Auto-refresh when expired
5. Handle 401 responses by refreshing
```

### 2. Database Module (`Database-Functions.ps1`)

**Purpose**: Manages all SQL Server database operations.

**Key Functions**:
- `Initialize-DatabaseConnection()` - Sets up connection string
- `Open-DatabaseConnection()` - Opens SQL connection
- `Invoke-SqlNonQuery()` - Executes DDL/DML commands
- `Invoke-SqlQuery()` - Executes SELECT queries
- `Export-DataToTable()` - Bulk insert operations
- `New-DatabaseIfNotExists()` - Auto-creates database
- `Initialize-DatabaseSchema()` - Creates tables and indexes

**Design Patterns**:
- **Connection Pooling**: Reuses connections for efficiency
- **Bulk Insert**: Uses SqlBulkCopy for performance
- **Transaction Pattern**: Ensures data integrity
- **Factory Pattern**: Connection creation abstraction

### 3. Audit Logging Module (`Audit-Logging.ps1`)

**Purpose**: Provides comprehensive audit trail for compliance.

**Key Functions**:
- `Write-AuditLog()` - General audit logging
- `Write-ApiAuditLog()` - API request tracking
- `Write-DataAccessLog()` - Data access logging
- `Write-ExportAuditLog()` - Export operation tracking
- `Get-AuditLogs()` - Query audit history
- `Export-AuditLogs()` - Export compliance reports

**Audit Categories**:
- Authentication
- API Requests
- Data Access
- Export Operations
- Configuration Changes
- Security Events

### 4. Configuration Validator (`Validate-Config.ps1`)

**Purpose**: Validates configuration files before execution.

**Key Functions**:
- `Test-Configuration()` - Validates config.json
- `Test-Credentials()` - Validates credentials.json
- `Get-ConfigurationSettings()` - Loads configuration
- `Test-AllPrerequisites()` - Complete validation

### 5. Data Collectors

#### Azure AD Collector (`Collector-AzureAD.ps1`)
Exports:
- Users (with licenses and sign-in activity)
- Groups (all types with member counts)
- Devices (compliance status)
- Service Principals

#### M365 Services Collector (`Collector-M365Services.ps1`)
Exports:
- Microsoft Teams
- SharePoint Sites
- OneDrive Drives
- Planner Plans and Tasks

### 6. Main Export Script (`Export-M365ToSQL.ps1`)

**Purpose**: Orchestrates the entire export process.

**Workflow**:
```
1. Validate Prerequisites
   ├─ Check PowerShell version
   ├─ Validate config files
   └─ Test credentials

2. Initialize Connections
   ├─ Authenticate to Graph API
   ├─ Test Graph connectivity
   ├─ Connect to SQL database
   └─ Initialize schema

3. Export Data
   ├─ For each enabled component:
   │  ├─ Log export start
   │  ├─ Fetch data from Graph API
   │  ├─ Transform data
   │  ├─ Bulk insert to SQL
   │  └─ Log export completion
   └─ Handle errors and retries

4. Finalize
   ├─ Close connections
   ├─ Generate summary
   └─ Update audit logs
```

### 7. Excel/CSV Export Scripts

**Purpose**: Export SQL data to file formats.

**Scripts**:
- `Export-SQLToExcel.ps1` - Creates formatted Excel workbooks
- `Export-SQLToCSV.ps1` - Generates CSV files with optional compression

## Data Flow

### Full Export Mode
```
Graph API → Collector Module → DataTable → SqlBulkCopy → SQL Table
                                                ↓
                                          Audit Log
```

1. Authenticate to Microsoft Graph API
2. Retrieve all data for component (paginated)
3. Transform to PowerShell objects
4. TRUNCATE existing table data
5. Bulk insert new data
6. Log operation to audit trail

### Incremental Export Mode
```
SQL (Last Export Time) → Graph API (Delta Query) → Transform → MERGE/UPSERT → SQL
                                                                      ↓
                                                                 Audit Log
```

1. Query last export timestamp from ExportHistory
2. Request delta changes from Graph API
3. Transform changed records
4. Update or insert records (MERGE pattern)
5. Update last export timestamp

## Database Schema

### Schema Design Principles
- **Normalized**: Minimal redundancy, proper relationships
- **Indexed**: Performance optimization for common queries
- **Typed**: Proper data types for each field
- **Auditable**: Tracking columns on all tables
- **Extensible**: Easy to add new components

### Core Tables

**ExportHistory**:
```sql
ExportId (PK) | ComponentName | ExportMode | StartTime | EndTime | 
Status | RecordsExported | ErrorMessage | ExecutedBy
```
Tracks all export operations for monitoring and troubleshooting.

**AuditLog**:
```sql
AuditId (PK) | Timestamp | Category | Action | EntityType | 
EntityId | Details | ExecutedBy | SourceIP | SessionId
```
Comprehensive audit trail for compliance and security.

**Configuration**:
```sql
ConfigKey (PK) | ConfigValue | Description | LastModified
```
Stores runtime configuration and state.

### Data Tables

Each M365 component has dedicated tables:
- `AAD_Users`, `AAD_Groups`, `AAD_Devices`, `AAD_ServicePrincipals`
- `Teams_Teams`, `Teams_Channels`
- `SharePoint_Sites`, `SharePoint_Lists`
- `OneDrive_Drives`
- `Planner_Plans`, `Planner_Tasks`

### Indexing Strategy
- **Primary Keys**: Unique identifiers from Graph API (GUIDs)
- **Foreign Keys**: Relationships between entities
- **Covering Indexes**: Common query patterns
- **Filtered Indexes**: For active/enabled records

## Security Architecture

### Authentication Flow
```
1. Client Credentials Flow
   ├─ TenantId + ClientId + ClientSecret
   └─ Azure AD Token Endpoint
       ↓
   Access Token (Bearer)
       ↓
   Graph API Requests
```

### Security Layers
1. **Transport Security**: TLS 1.2+ for all communications
2. **Authentication**: OAuth 2.0 client credentials
3. **Authorization**: Application permissions (not delegated)
4. **Credential Storage**: External JSON file (not in code)
5. **Database Security**: SQL authentication or Windows Auth
6. **Audit Logging**: All operations logged

### Threat Mitigation
- **Credential Exposure**: External config, .gitignore
- **Man-in-the-Middle**: TLS encryption
- **Rate Limiting**: Retry with exponential backoff
- **SQL Injection**: Parameterized queries
- **Data Breach**: Access logging, encryption at rest

## Performance Optimization

### Graph API Optimization
- **Batch Processing**: 100-999 items per request
- **Parallel Requests**: Multiple components concurrently
- **Selective Fields**: `$select` to reduce payload
- **Pagination**: `$top` for controlled page sizes
- **Delta Queries**: Only fetch changes (where supported)

### Database Optimization
- **Bulk Insert**: SqlBulkCopy for large datasets
- **Connection Pooling**: Reuse connections
- **Batch Commits**: Commit in batches, not per-row
- **Indexes**: Strategic indexing for queries
- **Statistics**: Keep statistics updated

### Memory Management
- **Streaming**: Process data in chunks
- **Disposal**: Proper cleanup of objects
- **Batch Size**: Configurable to prevent OOM
- **Garbage Collection**: Allow GC between batches

## Scalability

### Current Scale
Tested and optimized for:
- 10,000+ users
- 5,000+ groups
- 1,000+ Teams
- 10,000+ SharePoint sites
- 10,000+ OneDrive accounts

### Scaling Strategies
1. **Horizontal Scaling**: Run multiple instances for different components
2. **Vertical Scaling**: Increase SQL Server resources
3. **Temporal Scaling**: Stagger export schedules
4. **Data Partitioning**: Table partitioning for large datasets

### Bottlenecks
- **Graph API Rate Limits**: 10,000 requests/10 min (typical)
- **SQL Insert Speed**: ~10,000 rows/sec (varies by server)
- **Network Bandwidth**: Large file downloads
- **PowerShell Memory**: Large object collections

## Compliance Architecture

### GDPR Compliance
- **Data Minimization**: Configurable fields to export
- **Retention Policies**: Auto-cleanup old data
- **Right to Erasure**: Delete operations logged
- **Audit Trail**: All processing activities logged
- **Pseudonymization**: Optional field masking

### HIPAA Compliance
- **Access Control**: Database-level permissions
- **Audit Logging**: All data access logged
- **Integrity Checks**: Checksums and validation
- **Session Management**: Timeout and tracking
- **Secure Transmission**: Encrypted connections

### SOC2 Compliance
- **Change Management**: Configuration versioning
- **Monitoring**: Export success tracking
- **Incident Response**: Error logging and alerts
- **Access Logging**: User activity tracking
- **Documentation**: Comprehensive docs

## Error Handling

### Error Hierarchy
```
1. Transient Errors (Retry)
   ├─ Network timeouts
   ├─ API throttling (429)
   └─ Temporary SQL issues

2. Retriable Errors (Retry with backoff)
   ├─ 5xx server errors
   ├─ Connection resets
   └─ Deadlocks

3. Non-Retriable Errors (Fail fast)
   ├─ Authentication failures (401)
   ├─ Permission errors (403)
   ├─ Not found (404)
   └─ Schema errors
```

### Recovery Mechanisms
- **Automatic Retry**: 3-5 attempts with exponential backoff
- **Checkpoint/Resume**: Track progress per component
- **Graceful Degradation**: Continue other components if one fails
- **Comprehensive Logging**: All errors logged to audit trail

## Extensibility

### Adding New Components
1. Create collector function in appropriate module
2. Add table creation SQL
3. Update config.json with component settings
4. Add to main export script orchestration
5. Update documentation

### Adding New Features
1. Create new module or extend existing
2. Update configuration schema
3. Add tests and validation
4. Update documentation
5. Version appropriately

## Deployment Models

### Standalone
- Run manually on workstation
- Scheduled via Task Scheduler
- One-time exports

### Server-Based
- Windows Server with Task Scheduler
- Dedicated service account
- Automated daily/hourly exports

### Azure Automation
- Azure Automation Runbook
- Managed identity or service principal
- Serverless execution
- Integration with Azure SQL

## Monitoring and Observability

### Metrics Tracked
- Export success rate
- Records exported per component
- Export duration
- API call counts
- Error rates
- Data freshness

### Monitoring Queries
See `SQL/sample-queries.sql` for:
- Export history
- Audit log analysis
- Performance metrics
- Error tracking

---

**Version**: 1.0.0  
**Last Updated**: 2026-02-07  
**Maintained by**: M365-SQL-Exporter Team
