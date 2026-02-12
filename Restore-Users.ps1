param (
    [string]$UsersCsv = ".\Backup\Users-YYYYMMDD.csv",
    [switch]$TestMode = $true
)
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome
Connect-ExchangeOnline -ShowBanner:$false
Import-Csv $UsersCsv | ForEach-Object {
    $userId = $_.Id
    $upn = $_.UserPrincipalName
    $prox = $_.ProxyAddresses -split ';'
    if ($TestMode) {
        Write-Host "Would restore UPN for $userId to $upn"
        Write-Host "Would set EmailAddresses for mailbox $upn to $($prox -join ', ')"
    } else {
        Set-MgUser -UserId $userId -UserPrincipalName $upn
        try { Set-Mailbox -Identity $upn -EmailAddresses $prox } catch {}
    }
}
Disconnect-MgGraph | Out-Null
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "User restore complete."