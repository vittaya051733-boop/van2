# Adds van*.web.app to Firebase Auth authorized domains (required for Google Sign-In on custom hosting sites).
# Run once from repo root with gcloud auth logged in as project admin.
#
# Firebase Console alternative:
# Authentication -> Settings -> Authorized domains -> Add domain -> vantalad.web.app

$projectId = 'van-merchant'
$domainsToEnsure = @(
  'van1.web.app',
  'vantalad.web.app',
  'van3.web.app',
  'van4.web.app'
)

$token = gcloud auth print-access-token 2>$null
if (-not $token) {
  throw 'gcloud auth required'
}

$configUri = "https://identitytoolkit.googleapis.com/admin/v2/projects/$projectId/config"
$headers = @{
  Authorization = "Bearer $token"
  'Content-Type' = 'application/json'
}

$response = Invoke-RestMethod -Method Get -Uri $configUri -Headers $headers
$existing = @($response.authorizedDomains)
$merged = [System.Collections.Generic.HashSet[string]]::new([string[]]$existing)
foreach ($domain in $domainsToEnsure) {
  [void]$merged.Add($domain)
}

$body = @{
  authorizedDomains = @($merged)
} | ConvertTo-Json

Invoke-RestMethod -Method Patch -Uri "$configUri?updateMask=authorizedDomains" -Headers $headers -Body $body
Write-Host "Authorized domains updated for $projectId"
