# Export files from a user's OneDrive
param ([string]$OneDriveUrl, [string]$ExportPath = ".\Backup\ODFiles")
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
Connect-PnPOnline -Url $OneDriveUrl -Interactive
$files = Get-PnPListItem -List "Documents"
foreach ($f in $files) {
    $fileName = [System.IO.Path]::GetFileName($f.FieldValues.FileRef)
    Get-PnPFile -Url $f.FieldValues.FileRef -Path $ExportPath -FileName $fileName -AsFile -Force
    Write-Host "Exported $fileName"
}
Disconnect-PnPOnline