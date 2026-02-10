# Your complete script content here, with the updated Get-AccountStatus function

# Function to get account status
function Get-AccountStatus {
    param($UserPrincipalName)
    
    if (-not $UserPrincipalName) {
        return "Unknown"
    }
    
    try {
        $user = Get-MgUser -UserId $UserPrincipalName -Property AccountEnabled -ErrorAction SilentlyContinue
        if ($user -and $null -ne $user.AccountEnabled) {
            return $user.AccountEnabled
        }
    }
    catch {
        # Silently continue
    }
    
    return "Unknown"
}

# ... rest of the original script ...
