# Import list items from CSV
param (
    [string]$SiteUrl,
    [string]$List,
    [string]$ImportCsv = ".\Backup\SPListItems.csv"
)
Connect-PnPOnline -Url $SiteUrl -Interactive
$rows = Import-Csv $ImportCsv
foreach ($row in $rows) {
    Add-PnPListItem -List $List -Values $row
    Write-Host "Added item: $($row.Title)"
}
Disconnect-PnPOnline