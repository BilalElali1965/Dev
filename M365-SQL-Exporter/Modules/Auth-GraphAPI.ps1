<#
.SYNOPSIS
    Microsoft Graph API Authentication Module for M365-SQL-Exporter

.DESCRIPTION
    Handles authentication to Microsoft Graph API using client credentials flow.
    Implements secure token management, automatic refresh, and proper error handling.

.NOTES
    Version: 1.0.0
    Author: M365-SQL-Exporter
    Requires: PowerShell 5.1 or later
#>

#Requires -Version 5.1

# Module-level variables
$script:AccessToken = $null
$script:TokenExpiry = $null
$script:TenantId = $null
$script:ClientId = $null
$script:ClientSecret = $null

<#
.SYNOPSIS
    Initializes authentication credentials

.PARAMETER TenantId
    Azure AD Tenant ID

.PARAMETER ClientId
    Azure AD Application (Client) ID

.PARAMETER ClientSecret
    Azure AD Application Client Secret

.EXAMPLE
    Initialize-GraphAuth -TenantId "xxx" -ClientId "yyy" -ClientSecret "zzz"
#>
function Initialize-GraphAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    try {
        Write-Verbose "Initializing Graph API authentication..."
        
        # Validate parameters
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw "TenantId cannot be empty"
        }
        if ([string]::IsNullOrWhiteSpace($ClientId)) {
            throw "ClientId cannot be empty"
        }
        if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
            throw "ClientSecret cannot be empty"
        }

        $script:TenantId = $TenantId
        $script:ClientId = $ClientId
        $script:ClientSecret = $ClientSecret

        Write-Verbose "Authentication credentials initialized successfully"
        return $true
    }
    catch {
        Write-Error "Failed to initialize authentication: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets an access token for Microsoft Graph API

.DESCRIPTION
    Requests an access token using client credentials flow.
    Implements caching and automatic refresh.

.PARAMETER ForceRefresh
    Forces a new token request even if current token is valid

.EXAMPLE
    $token = Get-GraphAccessToken
#>
function Get-GraphAccessToken {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh
    )

    try {
        # Check if credentials are initialized
        if ([string]::IsNullOrWhiteSpace($script:TenantId)) {
            throw "Authentication not initialized. Call Initialize-GraphAuth first."
        }

        # Check if token is still valid (with 5 minute buffer)
        $now = Get-Date
        if (-not $ForceRefresh -and $null -ne $script:TokenExpiry -and $now -lt $script:TokenExpiry.AddMinutes(-5)) {
            Write-Verbose "Using cached access token"
            return $script:AccessToken
        }

        Write-Verbose "Requesting new access token from Azure AD..."

        # Build token request
        $tokenEndpoint = "https://login.microsoftonline.com/$script:TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $script:ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $script:ClientSecret
            grant_type    = "client_credentials"
        }

        # Request token
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop

        # Cache token and expiry
        $script:AccessToken = $response.access_token
        $script:TokenExpiry = $now.AddSeconds($response.expires_in)

        Write-Verbose "Access token obtained successfully. Expires at: $($script:TokenExpiry)"
        return $script:AccessToken
    }
    catch {
        Write-Error "Failed to obtain access token: $_"
        Write-Error "Error details: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $responseBody = $reader.ReadToEnd()
            Write-Error "Response: $responseBody"
        }
        return $null
    }
}

<#
.SYNOPSIS
    Invokes Microsoft Graph API request with proper authentication and error handling

.PARAMETER Uri
    The Graph API endpoint URI

.PARAMETER Method
    HTTP method (GET, POST, PATCH, DELETE)

.PARAMETER Body
    Request body (for POST/PATCH)

.PARAMETER MaxRetries
    Maximum number of retry attempts for transient failures

.EXAMPLE
    $users = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/users" -Method GET
#>
function Invoke-GraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE', 'PUT')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body = $null,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 5
    )

    $retryCount = 0
    $retryDelay = 10

    while ($retryCount -le $MaxRetries) {
        try {
            # Get valid access token
            $token = Get-GraphAccessToken
            if ([string]::IsNullOrWhiteSpace($token)) {
                throw "Failed to obtain access token"
            }

            # Build request headers
            $headers = @{
                "Authorization" = "Bearer $token"
                "Content-Type"  = "application/json"
                "ConsistencyLevel" = "eventual"
            }

            # Build request parameters
            $requestParams = @{
                Uri     = $Uri
                Method  = $Method
                Headers = $headers
            }

            if ($null -ne $Body) {
                $requestParams['Body'] = ($Body | ConvertTo-Json -Depth 10)
            }

            # Make request
            Write-Verbose "Graph API Request: $Method $Uri"
            $response = Invoke-RestMethod @requestParams -ErrorAction Stop

            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            # Handle throttling (429)
            if ($statusCode -eq 429) {
                $retryAfter = 60
                if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers['Retry-After']) {
                    $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                }
                
                Write-Warning "API throttling detected. Waiting $retryAfter seconds before retry..."
                Start-Sleep -Seconds $retryAfter
                $retryCount++
                continue
            }

            # Handle transient errors (5xx)
            if ($statusCode -ge 500 -and $statusCode -lt 600) {
                if ($retryCount -lt $MaxRetries) {
                    $waitTime = $retryDelay * [Math]::Pow(2, $retryCount)
                    Write-Warning "Transient error ($statusCode). Retrying in $waitTime seconds... (Attempt $($retryCount + 1)/$MaxRetries)"
                    Start-Sleep -Seconds $waitTime
                    $retryCount++
                    continue
                }
            }

            # Handle unauthorized (401) - try refreshing token
            if ($statusCode -eq 401 -and $retryCount -eq 0) {
                Write-Warning "Unauthorized response. Refreshing token..."
                $token = Get-GraphAccessToken -ForceRefresh
                $retryCount++
                continue
            }

            # Non-retriable error or max retries exceeded
            Write-Error "Graph API request failed: $Method $Uri"
            Write-Error "Status Code: $statusCode"
            Write-Error "Error: $($_.Exception.Message)"
            
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $reader.BaseStream.Position = 0
                    $responseBody = $reader.ReadToEnd()
                    Write-Error "Response: $responseBody"
                }
                catch {
                    # Ignore errors reading response body
                }
            }
            
            return $null
        }
    }

    Write-Error "Max retries exceeded for: $Method $Uri"
    return $null
}

<#
.SYNOPSIS
    Gets all pages from a Graph API endpoint that supports paging

.PARAMETER Uri
    The initial Graph API endpoint URI

.PARAMETER MaxPages
    Maximum number of pages to retrieve (0 = unlimited)

.EXAMPLE
    $allUsers = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/users"
#>
function Get-GraphAllPages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [int]$MaxPages = 0
    )

    $allResults = @()
    $currentUri = $Uri
    $pageCount = 0

    while ($null -ne $currentUri) {
        $pageCount++
        
        if ($MaxPages -gt 0 -and $pageCount -gt $MaxPages) {
            Write-Warning "Reached maximum page limit ($MaxPages)"
            break
        }

        Write-Verbose "Fetching page $pageCount from Graph API..."
        $response = Invoke-GraphRequest -Uri $currentUri -Method GET

        if ($null -eq $response) {
            Write-Error "Failed to retrieve page $pageCount"
            break
        }

        # Add results from this page
        if ($response.value) {
            $allResults += $response.value
            Write-Verbose "Retrieved $($response.value.Count) items from page $pageCount (Total: $($allResults.Count))"
        }
        else {
            # Single object response
            $allResults += $response
        }

        # Get next page URI
        $currentUri = $response.'@odata.nextLink'
        
        if ($null -eq $currentUri) {
            Write-Verbose "No more pages available. Total items retrieved: $($allResults.Count)"
        }
    }

    return $allResults
}

<#
.SYNOPSIS
    Tests Graph API connectivity

.EXAMPLE
    Test-GraphConnection
#>
function Test-GraphConnection {
    [CmdletBinding()]
    param()

    try {
        Write-Host "Testing Graph API connectivity..." -ForegroundColor Cyan
        
        # Try to get organization info
        $org = Invoke-GraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET
        
        if ($null -ne $org -and $org.value) {
            Write-Host "✓ Successfully connected to Microsoft Graph API" -ForegroundColor Green
            Write-Host "  Tenant: $($org.value[0].displayName)" -ForegroundColor Gray
            Write-Host "  Tenant ID: $($org.value[0].id)" -ForegroundColor Gray
            return $true
        }
        else {
            Write-Host "✗ Failed to retrieve organization information" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "✗ Graph API connection test failed: $_" -ForegroundColor Red
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-GraphAuth',
    'Get-GraphAccessToken',
    'Invoke-GraphRequest',
    'Get-GraphAllPages',
    'Test-GraphConnection'
)
