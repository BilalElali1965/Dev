<#
.SYNOPSIS
    Configuration Validator for M365-SQL-Exporter

.DESCRIPTION
    Validates configuration files and credentials before export operations.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

<#
.SYNOPSIS
    Validates the main configuration file

.PARAMETER ConfigPath
    Path to config.json file

.EXAMPLE
    Test-Configuration -ConfigPath ".\Config\config.json"
#>
function Test-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    try {
        Write-Host "Validating configuration file..." -ForegroundColor Cyan

        if (-not (Test-Path $ConfigPath)) {
            Write-Host "✗ Configuration file not found: $ConfigPath" -ForegroundColor Red
            return $false
        }

        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

        # Validate required sections
        $requiredSections = @(
            'GeneralSettings',
            'DatabaseSettings',
            'ExportSettings',
            'M365Components',
            'GraphAPISettings',
            'ComplianceSettings',
            'AuditSettings'
        )

        $allValid = $true
        foreach ($section in $requiredSections) {
            if (-not $config.PSObject.Properties[$section]) {
                Write-Host "✗ Missing required section: $section" -ForegroundColor Red
                $allValid = $false
            }
            else {
                Write-Host "  ✓ $section section found" -ForegroundColor Gray
            }
        }

        if ($allValid) {
            Write-Host "✓ Configuration file is valid" -ForegroundColor Green
        }

        return $allValid
    }
    catch {
        Write-Host "✗ Failed to validate configuration: $_" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Validates credentials file

.PARAMETER CredentialsPath
    Path to credentials.json file

.EXAMPLE
    Test-Credentials -CredentialsPath ".\Config\credentials.json"
#>
function Test-Credentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialsPath
    )

    try {
        Write-Host "Validating credentials file..." -ForegroundColor Cyan

        if (-not (Test-Path $CredentialsPath)) {
            Write-Host "✗ Credentials file not found: $CredentialsPath" -ForegroundColor Red
            Write-Host "  Please copy credentials.template.json to credentials.json and fill in your values" -ForegroundColor Yellow
            return $false
        }

        $credentials = Get-Content -Path $CredentialsPath -Raw | ConvertFrom-Json

        # Validate Azure AD credentials
        $allValid = $true
        
        if ([string]::IsNullOrWhiteSpace($credentials.AzureAD.TenantId) -or $credentials.AzureAD.TenantId -eq "YOUR_TENANT_ID_HERE") {
            Write-Host "✗ Azure AD TenantId not configured" -ForegroundColor Red
            $allValid = $false
        }
        else {
            Write-Host "  ✓ Azure AD TenantId configured" -ForegroundColor Gray
        }

        if ([string]::IsNullOrWhiteSpace($credentials.AzureAD.ClientId) -or $credentials.AzureAD.ClientId -eq "YOUR_CLIENT_ID_HERE") {
            Write-Host "✗ Azure AD ClientId not configured" -ForegroundColor Red
            $allValid = $false
        }
        else {
            Write-Host "  ✓ Azure AD ClientId configured" -ForegroundColor Gray
        }

        if ([string]::IsNullOrWhiteSpace($credentials.AzureAD.ClientSecret) -or $credentials.AzureAD.ClientSecret -eq "YOUR_CLIENT_SECRET_HERE") {
            Write-Host "✗ Azure AD ClientSecret not configured" -ForegroundColor Red
            $allValid = $false
        }
        else {
            Write-Host "  ✓ Azure AD ClientSecret configured" -ForegroundColor Gray
        }

        # Validate database credentials
        if ([string]::IsNullOrWhiteSpace($credentials.Database.ServerName) -or $credentials.Database.ServerName -like "*YOUR_SQL_SERVER*") {
            Write-Host "✗ Database ServerName not configured" -ForegroundColor Red
            $allValid = $false
        }
        else {
            Write-Host "  ✓ Database ServerName configured" -ForegroundColor Gray
        }

        if ($allValid) {
            Write-Host "✓ Credentials file is valid" -ForegroundColor Green
        }

        return $allValid
    }
    catch {
        Write-Host "✗ Failed to validate credentials: $_" -ForegroundColor Red
        return $false
    }
}

<#
.SYNOPSIS
    Loads and returns configuration

.PARAMETER ConfigPath
    Path to config.json file

.EXAMPLE
    $config = Get-ConfigurationSettings -ConfigPath ".\Config\config.json"
#>
function Get-ConfigurationSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Configuration file not found: $ConfigPath"
        }

        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Error "Failed to load configuration: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Loads and returns credentials

.PARAMETER CredentialsPath
    Path to credentials.json file

.EXAMPLE
    $creds = Get-CredentialSettings -CredentialsPath ".\Config\credentials.json"
#>
function Get-CredentialSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CredentialsPath
    )

    try {
        if (-not (Test-Path $CredentialsPath)) {
            throw "Credentials file not found: $CredentialsPath"
        }

        $credentials = Get-Content -Path $CredentialsPath -Raw | ConvertFrom-Json
        return $credentials
    }
    catch {
        Write-Error "Failed to load credentials: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Validates all configuration and prerequisites

.PARAMETER ConfigPath
    Path to config.json file

.PARAMETER CredentialsPath
    Path to credentials.json file

.EXAMPLE
    Test-AllPrerequisites -ConfigPath ".\Config\config.json" -CredentialsPath ".\Config\credentials.json"
#>
function Test-AllPrerequisites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$CredentialsPath
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Prerequisites Validation" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $allValid = $true

    # Validate PowerShell version
    Write-Host "Checking PowerShell version..." -ForegroundColor Cyan
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-Host "  ✓ PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    }
    else {
        Write-Host "  ✗ PowerShell 5.1 or later required" -ForegroundColor Red
        $allValid = $false
    }

    # Validate configuration files
    if (-not (Test-Configuration -ConfigPath $ConfigPath)) {
        $allValid = $false
    }

    if (-not (Test-Credentials -CredentialsPath $CredentialsPath)) {
        $allValid = $false
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    if ($allValid) {
        Write-Host "✓ All prerequisites validated successfully" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Some prerequisites failed validation" -ForegroundColor Red
    }
    Write-Host "========================================`n" -ForegroundColor Cyan

    return $allValid
}

# Export module functions
Export-ModuleMember -Function @(
    'Test-Configuration',
    'Test-Credentials',
    'Get-ConfigurationSettings',
    'Get-CredentialSettings',
    'Test-AllPrerequisites'
)
