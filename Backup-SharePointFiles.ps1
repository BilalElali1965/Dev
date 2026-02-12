# Export all files in a document library
param (
    [string]$SiteUrl,
    [string]$Library = "Documents",
    [string]$ExportPath = ".\Backup\SPFiles"
)
if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null }
Connect-PnPOnline -Url $SiteUrl -Interactive
$files = Get-PnPListItem -List $Library
foreach ($f in $files) {
    $fileRef = $f.FieldValues.FileRef
    $fileName = [System.IO.Path]::GetFileName($fileRef)
    $downloadTo = Join-Path $ExportPath $fileName
    Get-PnPFile -Url $fileRef -Path $ExportPath -FileName $fileName -AsFile -Force
    Write-Host "Exported $fileName"
}
Disconnect-PnPOnline