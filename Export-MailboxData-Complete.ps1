function Get-AccountStatus {  
    param (
        [string]$username
    )  
    $user = Get-UserDetails -username $username  
    if ($user.AccountEnabled -eq $true) {  
        return "Enabled"  
    } elseif ($user.AccountEnabled -eq $false) {  
        return "Disabled"  
    } else {  
        return "Unknown"  
    }
}