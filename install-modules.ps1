# Install Required PowerShell Modules for SharePoint Audit Export

Write-Host "Installing Microsoft.Online.SharePoint.PowerShell module..." -ForegroundColor Green
Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Force -AllowClobber

Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Green
Install-Module -Name Microsoft.Graph -Force -AllowClobber

Write-Host "All modules installed successfully!" -ForegroundColor Green
Write-Host "You can now run the export-sharepoint-audit.ps1 script" -ForegroundColor Yellow