# Upload files from a folder to a SharePoint library
param (
    [string]$SiteUrl,
    [string]$Library = "Documents",
    [string]$ImportPath = ".\Backup\SPFiles"
)
Connect-PnPOnline -Url $SiteUrl -Interactive
Get-ChildItem $ImportPath | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
    Add-PnPFile -Path $_.FullName -Folder $Library
    Write-Host "Uploaded $($_.Name)"
}
Disconnect-PnPOnline