<#
.SYNOPSIS
    Full M365 Migration Toolkit with optional domain translation.
.DESCRIPTION
    Orchestrates a complete M365 tenant migration across three phases:
      Phase 1 - Assessment:      Inventories mailboxes and previews translated addresses.
      Phase 2 - Backup/Export:   Exports mailbox data, aliases, and translates a permissions CSV.
      Phase 3 - Migration:       Applies UPN, PrimarySMTP, and alias changes to Exchange Online.

    Domain translation (renaming addresses from SourceDomain to TargetDomain) is an explicit
    opt-in feature controlled by -DomainTranslation.  The default is Disabled so the script is
    safe to run without any domain rewriting.
.PARAMETER DomainTranslation
    Enable or disable domain translation across all phases.
    Allowed values: Enabled, Disabled.
    Default: Disabled (safest option – no addresses are rewritten).
.PARAMETER SourceDomain
    The domain to translate FROM (e.g., olddomain.com).
    Required when -DomainTranslation Enabled.
.PARAMETER TargetDomain
    The domain to translate TO (e.g., newdomain.com).
    Required when -DomainTranslation Enabled.
.PARAMETER PermissionsCSV
    Optional path to a CSV file containing mailbox/trustee permission mappings.
    When -DomainTranslation Enabled the Mailbox and Trustee columns are translated.
.PARAMETER ExportPath
    Root folder for all output (assessment reports, backups, logs).
    Default: .\MigrationOutput
.PARAMETER TestMode
    When $true (default) the script previews all changes without modifying anything.
    Set to $false to apply changes in Phase 3.
.PARAMETER ReplicationDelaySeconds
    Seconds to wait after updating a UPN before updating the associated mailbox,
    to allow Azure AD / Exchange replication to propagate.
    Default: 5
.EXAMPLE
    # Safe mode – run all phases with domain translation disabled (default):
    .\M365-FullMigrationToolkit.ps1

.EXAMPLE
    # Preview with domain translation enabled (test mode, no changes made):
    .\M365-FullMigrationToolkit.ps1 -DomainTranslation Enabled `
        -SourceDomain "olddomain.com" -TargetDomain "newdomain.com"

.EXAMPLE
    # Live run with domain translation enabled and a permissions CSV:
    .\M365-FullMigrationToolkit.ps1 -DomainTranslation Enabled `
        -SourceDomain "olddomain.com" -TargetDomain "newdomain.com" `
        -PermissionsCSV ".\permissions.csv" -TestMode $false

.NOTES
    Smoke-check guidance:
      1. Always run with -TestMode $true first to preview every change before it is applied.
      2. Review log files under <ExportPath>\Logs\ after each run.
      3. When DomainTranslation is Disabled, -SourceDomain / -TargetDomain are silently
         ignored except for a logged warning – no addresses are rewritten.
      4. Requires: ExchangeOnlineManagement and Microsoft.Graph.Users PowerShell modules.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Enabled","Disabled")]
    [string]$DomainTranslation = "Disabled",

    [Parameter(Mandatory=$false)]
    [string]$SourceDomain = "",

    [Parameter(Mandatory=$false)]
    [string]$TargetDomain = "",

    [Parameter(Mandatory=$false)]
    [string]$PermissionsCSV = "",

    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ".\MigrationOutput",

    [Parameter(Mandatory=$false)]
    [bool]$TestMode = $true,

    [Parameter(Mandatory=$false)]
    [int]$ReplicationDelaySeconds = 5
)

# ─────────────────────────────────────────────────────────────────────────────
# Centralized translation flag – all callsites derive from this single bool
# ─────────────────────────────────────────────────────────────────────────────
$EnableDomainTranslation = ($DomainTranslation -eq "Enabled")

# ─────────────────────────────────────────────────────────────────────────────
# Logging setup
# ─────────────────────────────────────────────────────────────────────────────
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $ExportPath "Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logPath = Join-Path $logDir "MigrationToolkit-$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Add-Content -Path $logPath -Value $logMessage
    switch ($Level) {
        "WARN"  { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        default { Write-Host $logMessage }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Parameter validation
# ─────────────────────────────────────────────────────────────────────────────
if ($EnableDomainTranslation) {
    if ([string]::IsNullOrWhiteSpace($SourceDomain) -or [string]::IsNullOrWhiteSpace($TargetDomain)) {
        Write-Log "-DomainTranslation Enabled requires both -SourceDomain and -TargetDomain." "ERROR"
        exit 1
    }
    if ($SourceDomain.ToLower() -eq $TargetDomain.ToLower()) {
        Write-Log "-SourceDomain and -TargetDomain must not be equal (both are '$SourceDomain')." "ERROR"
        exit 1
    }
    Write-Log "Domain translation ENABLED: '$SourceDomain' -> '$TargetDomain'"
} else {
    Write-Log "Domain translation DISABLED – addresses will not be rewritten."
    if (-not [string]::IsNullOrWhiteSpace($SourceDomain) -or -not [string]::IsNullOrWhiteSpace($TargetDomain)) {
        Write-Log "-SourceDomain / -TargetDomain were provided but -DomainTranslation is Disabled – they will be ignored." "WARN"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Convert-Domain
#   Translates a single address/string from SourceDomain to TargetDomain.
#   Returns the original value unchanged when translation is disabled.
# ─────────────────────────────────────────────────────────────────────────────
function Convert-Domain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Value
    )
    if (-not $EnableDomainTranslation) {
        return $Value
    }
    return [regex]::Replace(
        $Value,
        [regex]::Escape($SourceDomain),
        $TargetDomain,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

# ─────────────────────────────────────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   M365 Full Migration Toolkit                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "Domain Translation : $DomainTranslation" -ForegroundColor $(if ($EnableDomainTranslation) { "Green" } else { "Yellow" })
if ($EnableDomainTranslation) {
    Write-Host "  Source Domain    : $SourceDomain" -ForegroundColor Green
    Write-Host "  Target Domain    : $TargetDomain" -ForegroundColor Green
}
Write-Host "Test Mode          : $TestMode" -ForegroundColor $(if ($TestMode) { "Yellow" } else { "Red" })
Write-Host "Export Path        : $ExportPath" -ForegroundColor White
Write-Host ""

if ($TestMode) {
    Write-Host "*** TEST MODE – NO CHANGES WILL BE MADE ***" -ForegroundColor Yellow
    Write-Log "Running in TEST MODE"
} else {
    Write-Host "*** LIVE MODE – CHANGES WILL BE APPLIED ***" -ForegroundColor Red
    $confirmation = Read-Host "Are you sure you want to proceed? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit
    }
    Write-Log "Running in LIVE MODE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Connect to services (shared across phases)
# ─────────────────────────────────────────────────────────────────────────────
try {
    Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Green
    Connect-MgGraph -Scopes "User.ReadWrite.All","Group.Read.All","Directory.ReadWrite.All" -NoWelcome -ErrorAction Stop
    Write-Log "Connected to Microsoft Graph"
} catch {
    Write-Log "Failed to connect to Microsoft Graph: $_" "ERROR"
    exit 1
}

try {
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Green
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    Write-Log "Connected to Exchange Online"
} catch {
    Write-Log "Failed to connect to Exchange Online: $_" "ERROR"
    exit 1
}

# Pre-load all mailboxes once for use across all phases
$allMailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction SilentlyContinue
Write-Log "Loaded $($allMailboxes.Count) mailboxes for processing"

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 1 – Assessment
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n══════════════════════════════" -ForegroundColor Cyan
Write-Host "  PHASE 1 – Assessment"        -ForegroundColor Cyan
Write-Host "══════════════════════════════" -ForegroundColor Cyan
Write-Log "=== PHASE 1: Assessment ==="

try {
    $assessmentPath = Join-Path $ExportPath "Assessment"
    if (-not (Test-Path $assessmentPath)) {
        New-Item -ItemType Directory -Path $assessmentPath -Force | Out-Null
    }

    $assessmentReport = @()
    foreach ($mbx in $allMailboxes) {
        $upn         = $mbx.UserPrincipalName
        $primary     = $mbx.PrimarySmtpAddress

        # Apply domain translation when enabled
        $translatedUPN     = Convert-Domain -Value $upn
        $translatedPrimary = Convert-Domain -Value $primary

        $assessmentReport += [PSCustomObject]@{
            DisplayName       = $mbx.DisplayName
            RecipientType     = $mbx.RecipientTypeDetails
            SourceUPN         = $upn
            TranslatedUPN     = $translatedUPN
            SourcePrimary     = $primary
            TranslatedPrimary = $translatedPrimary
        }
    }

    $assessmentCsv = Join-Path $assessmentPath "MailboxAssessment-$timestamp.csv"
    $assessmentReport | Export-Csv -Path $assessmentCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Phase 1: Assessment exported to $assessmentCsv"
} catch {
    Write-Log "Phase 1 error: $_" "ERROR"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 2 – Backup / Export
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n══════════════════════════════" -ForegroundColor Cyan
Write-Host "  PHASE 2 – Backup / Export"   -ForegroundColor Cyan
Write-Host "══════════════════════════════" -ForegroundColor Cyan
Write-Log "=== PHASE 2: Backup / Export ==="

try {
    $backupPath = Join-Path $ExportPath "Backup"
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }

    $backupReport = @()
    foreach ($mbx in $allMailboxes) {
        $primary = $mbx.PrimarySmtpAddress

        # Translate PrimarySMTP when enabled
        $translatedPrimary = Convert-Domain -Value $primary

        # Collect and translate all smtp: aliases when enabled
        $aliases           = @($mbx.EmailAddresses | Where-Object { $_ -like "smtp:*" })
        $translatedAliases = @($aliases | ForEach-Object { Convert-Domain -Value $_ })

        $backupReport += [PSCustomObject]@{
            DisplayName       = $mbx.DisplayName
            SourcePrimary     = $primary
            TranslatedPrimary = $translatedPrimary
            SourceAliases     = ($aliases -join "; ")
            TranslatedAliases = ($translatedAliases -join "; ")
        }
    }

    $backupCsv = Join-Path $backupPath "MailboxBackup-$timestamp.csv"
    $backupReport | Export-Csv -Path $backupCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Phase 2: Backup exported to $backupCsv"

    # ── Permissions CSV processing ──────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($PermissionsCSV)) {
        if (Test-Path $PermissionsCSV) {
            Write-Log "Phase 2: Processing permissions CSV: $PermissionsCSV"
            $permsData      = Import-Csv -Path $PermissionsCSV
            $translatedPerms = @()

            foreach ($row in $permsData) {
                # Clone the row so we don't mutate the original import
                $props = [ordered]@{}
                foreach ($prop in $row.PSObject.Properties) {
                    $props[$prop.Name] = $prop.Value
                }

                # Translate the Mailbox column (the object that holds the permission)
                if ($props.Contains("Mailbox")) {
                    $props["Mailbox"] = Convert-Domain -Value $props["Mailbox"]
                }

                # Translate the Trustee column (the identity being granted access)
                if ($props.Contains("Trustee")) {
                    $props["Trustee"] = Convert-Domain -Value $props["Trustee"]
                }

                $translatedPerms += [PSCustomObject]$props
            }

            $translatedPermsCsv = Join-Path $backupPath "Permissions-Translated-$timestamp.csv"
            $translatedPerms | Export-Csv -Path $translatedPermsCsv -NoTypeInformation -Encoding UTF8
            Write-Log "Phase 2: Translated permissions exported to $translatedPermsCsv"
        } else {
            Write-Log "Phase 2: Permissions CSV not found at '$PermissionsCSV' – skipping." "WARN"
        }
    }
} catch {
    Write-Log "Phase 2 error: $_" "ERROR"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 3 – Migration
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n══════════════════════════════" -ForegroundColor Cyan
Write-Host "  PHASE 3 – Migration"          -ForegroundColor Cyan
Write-Host "══════════════════════════════" -ForegroundColor Cyan
Write-Log "=== PHASE 3: Migration ==="

$successCount = 0
$failCount    = 0
$counter      = 0
$totalMbx     = $allMailboxes.Count

foreach ($mbx in $allMailboxes) {
    $counter++
    $currentUPN     = $mbx.UserPrincipalName
    $currentPrimary = $mbx.PrimarySmtpAddress

    # Translate UPN and PrimarySMTP when enabled
    $newUPN     = Convert-Domain -Value $currentUPN
    $newPrimary = Convert-Domain -Value $currentPrimary

    # Translate all email addresses (preserves prefix type SMTP:/smtp:)
    $emailAddresses  = @($mbx.EmailAddresses)
    $updatedAddresses = @($emailAddresses | ForEach-Object { Convert-Domain -Value $_ })

    Write-Host "`n[$counter/$totalMbx] $currentUPN" -ForegroundColor Cyan

    # Determine whether any address has changed (covers primary-only, alias-only, or both)
    $addressesChanged = $EnableDomainTranslation -and (
        (Compare-Object $emailAddresses $updatedAddresses) -ne $null
    )

    try {
        if (-not $TestMode) {
            # Update UPN in Azure AD / Entra ID (only if translation produces a change)
            if ($EnableDomainTranslation -and $newUPN -ne $currentUPN) {
                Update-MgUser -UserId $mbx.ExternalDirectoryObjectId -UserPrincipalName $newUPN
                Write-Log "Phase 3: Updated UPN $currentUPN -> $newUPN"
                # Wait for replication using the configurable delay before touching Exchange
                Start-Sleep -Seconds $ReplicationDelaySeconds
            }

            # Update mailbox email addresses when any address (primary or alias) changed.
            # Use ExternalDirectoryObjectId as the stable identity to avoid replication race.
            if ($addressesChanged) {
                # Ensure the new primary is represented with uppercase SMTP: prefix;
                # use case-sensitive cnotlike to preserve lowercase smtp: aliases.
                $primaryEntry   = "SMTP:$newPrimary"
                $otherAddresses = $updatedAddresses | Where-Object { $_ -cnotlike "SMTP:*" }
                $finalAddresses = @($primaryEntry) + $otherAddresses

                Set-Mailbox -Identity $mbx.ExternalDirectoryObjectId -EmailAddresses $finalAddresses -WindowsEmailAddress $newPrimary
                Write-Log "Phase 3: Updated addresses for $currentUPN (primary: $newPrimary)"
            }
            $successCount++
        } else {
            # Test mode – log what would happen
            Write-Log "Phase 3 TEST MODE: UPN '$currentUPN' -> '$newUPN'"
            Write-Log "Phase 3 TEST MODE: Primary '$currentPrimary' -> '$newPrimary'"
            if ($addressesChanged) {
                Write-Log "Phase 3 TEST MODE: Addresses would be updated for $currentUPN"
            }
            $successCount++
        }
    } catch {
        Write-Log "Phase 3 error for $currentUPN : $_" "ERROR"
        $failCount++
    }
}

Write-Log "Phase 3 complete – Success: $successCount  Failed: $failCount  Total: $totalMbx"

# ─────────────────────────────────────────────────────────────────────────────
# Disconnect
# ─────────────────────────────────────────────────────────────────────────────
try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch {}
try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }              catch {}

Write-Host ""
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Migration Toolkit complete."                 -ForegroundColor Cyan
Write-Host "  Log: $logPath"                              -ForegroundColor White
Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Log "=== Migration Toolkit finished ==="
