# PowerShell Script to Export Entra ID Users with Detailed Attributes

# Connect to Microsoft Graph and Exchange Online
Connect-MgGraph -Scopes "User.Read.All","MailboxSettings.Read"
Connect-ExchangeOnline -UserPrincipalName $env:USER_PRINCIPAL_NAME

# Function to determine VIP status based on job titles
function Get-VipStatus { 
    param ($jobTitle)
    $vipTitles = @('Director', 'Manager', 'Executive') # Add titles that are considered VIPs
    return ($vipTitles -contains $jobTitle)
}

# Get all users from Azure AD
$users = Get-MgUser -All

# Prepare an array to hold user information
$userReport = @()

foreach ($user in $users) {
    # Get mailbox forwarding information
    $forwarding = Get-Mailbox -Identity $user.UserPrincipalName | Select-Object ForwardingAddress, ForwardingSmtpAddress

    # Get mailbox type
    $mailboxType = (Get-Mailbox -Identity $user.UserPrincipalName).RecipientTypeDetails

    # Get the OneDrive status
    $oneDriveStatus = Get-SPOSite | Where-Object { $_.Owner -eq $user.UserPrincipalName }
    $hasOneDrive = $null -ne $oneDriveStatus

    # Determine the VIP status
    $vipStatus = Get-VipStatus -jobTitle $user.JobTitle

    # Create a custom object for each user
    $userInfo = [PSCustomObject]@{
        Source = "Azure AD"
        EmploymentStatus = $user.AccountEnabled
        DisplayName = $user.DisplayName
        LastName = $user.Surname
        FirstName = $user.GivenName
        UPN = $user.UserPrincipalName
        Title = $user.JobTitle
        Department = $user.Department
        IsVIP = $vipStatus
        EmploymentType = $user.JobType
        Manager = (Get-MgUserManager -UserId $user.Id).DisplayName
        EmailAddress = $user.Mail
        PhoneNumber = $user.TelephoneNumber
        PhysicalDeliveryAddress = $user.PhysicalDeliveryOfficeName
        OfficeAffiliation = $user.PhysicalDeliveryOfficeName
        WorkingEnvironment = $user.PreferredLanguage
        LanguagePreference = $user.PreferredLanguage
        AccountStatus = $user.AccountEnabled
        BlockedCredentials = $user.Blocked
        AccountType = $mailboxType
        MailboxType = $mailboxType
        MailboxForward = $forwarding.ForwardingSmtpAddress
        HasOneDrive = $hasOneDrive
        AssignedLicenses = ($user.AssignedLicenses | ForEach-Object { $_.SkuId }) -join ';'
    }
    $userReport += $userInfo
}

# Export the report to CSV
$userReport | Export-Csv -Path "C:\UserReports\EntraIDUsers.csv" -NoTypeInformation