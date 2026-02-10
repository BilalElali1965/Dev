# Connect to SharePoint Online and Microsoft Graph
# Replace 'yourtenant' with your actual tenant name

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantName
)

Write-Host "Connecting to SharePoint Online..." -ForegroundColor Green
Connect-SPOService -Url "https://$TenantName-admin.sharepoint.com"

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Green
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All", "Sites.Read.All"

Write-Host "Successfully connected!" -ForegroundColor Green
Write-Host "You can now run the export-sharepoint-audit.ps1 script" -ForegroundColor Yellow