# Export list items to CSV
param (
    [string]$SiteUrl,
    [string]$List,
    [string]$ExportCsv = ".\Backup\SPListItems.csv"
)
Connect-PnPOnline -Url $SiteUrl -Interactive
$listItems = Get-PnPListItem -List $List -PageSize 1000
$listItems | Select-Object -ExpandProperty FieldValues | Export-Csv $ExportCsv -NoTypeInformation -Encoding UTF8
Disconnect-PnPOnline