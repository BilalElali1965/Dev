Write-Host "Found $($users.Count) users. Processing data..." -ForegroundColor Cyan

# Get all available SKUs once (more efficient than individual lookups)
Write-Host "Retrieving license SKU information..." -ForegroundColor Cyan
$allSkus = Get-MgSubscribedSku -All
$skuHashTable = @{}
foreach ($sku in $allSkus) {
    $skuHashTable[$sku.SkuId] = $sku.SkuPartNumber
}

# License SKU friendly names mapping
$licenseNames = @{
    'O365_BUSINESS_ESSENTIALS' = 'Office 365 Business Essentials'
    'O365_BUSINESS_PREMIUM' = 'Office 365 Business Premium'
    'DESKLESSPACK' = 'Office 365 F3'
    'DESKLESSWOFFPACK' = 'Office 365 F3'
    'ENTERPRISEPACK' = 'Office 365 E3'
    'ENTERPRISEPREMIUM' = 'Office 365 E5'
    'ENTERPRISEPREMIUM_NOPSTNCONF' = 'Office 365 E5 Without Audio Conferencing'
    'SPE_E3' = 'Microsoft 365 E3'
    'SPE_E5' = 'Microsoft 365 E5'
    'MICROSOFT365_F1' = 'Microsoft 365 F1'
    'MICROSOFT365_F3' = 'Microsoft 365 F3'
    'EXCHANGESTANDARD' = 'Exchange Online Plan 1'
    'EXCHANGEENTERPRISE' = 'Exchange Online Plan 2'
    'POWER_BI_STANDARD' = 'Power BI Free'
    'POWER_BI_PRO' = 'Power BI Pro'
    'PROJECTPROFESSIONAL' = 'Project Plan 3'
    'PROJECTESSENTIALS' = 'Project Plan 1'
    'VISIOCLIENT' = 'Visio Plan 2'
    'TEAMS_EXPLORATORY' = 'Microsoft Teams Exploratory'
    'STREAM' = 'Microsoft Stream'
    'AAD_PREMIUM' = 'Azure Active Directory Premium P1'
    'AAD_PREMIUM_P2' = 'Azure Active Directory Premium P2'
    'INTUNE_A' = 'Microsoft Intune'
    'FLOW_FREE' = 'Microsoft Power Automate Free'
    'POWERAPPS_VIRAL' = 'Microsoft Power Apps Plan 2 Trial'
}

# Create export array
$exportData = @()
$counter = 0

foreach ($user in $users) {
    $counter++
    Write-Progress -Activity "Processing users" -Status "Processing $counter of $($users.Count)" -PercentComplete (($counter / $users.Count) * 100)
    
    # Get manager information
    $manager = $null
    try {
        $manager = Get-MgUserManager -UserId $user.Id -ErrorAction SilentlyContinue
    }
    catch {
        # Manager not set
    }
    
    # Determine source (Cloud vs On-Premises Synced)
    $source = if ($user.OnPremisesSyncEnabled -eq $true) { "On-Premises Synced" } else { "Cloud" }
    
    # Get assigned licenses using hash table lookup
    $assignedLicenses = @()
    if ($user.AssignedLicenses -and $user.AssignedLicenses.Count -gt 0) {
        foreach ($license in $user.AssignedLicenses) {
            if ($skuHashTable.ContainsKey($license.SkuId)) {
                $skuPartNumber = $skuHashTable[$license.SkuId]
                $friendlyName = if ($licenseNames.ContainsKey($skuPartNumber)) { 
                    $licenseNames[$skuPartNumber] 
                } else { 
                    $skuPartNumber 
                }
                $assignedLicenses += $friendlyName
            }
        }
    }
    $licenseString = if ($assignedLicenses.Count -gt 0) { $assignedLicenses -join "; " } else { "No Licenses" }