param(
  [switch]$Interactive,
  [string]$ProjectId = 'van-merchant'
)

$ErrorActionPreference = 'Stop'

$secretNames = @(
  'SOCIAL_META_APP_ID',
  'SOCIAL_META_APP_SECRET',
  'SOCIAL_GOOGLE_OAUTH_CLIENT_ID',
  'SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET',
  'SOCIAL_TIKTOK_CLIENT_KEY',
  'SOCIAL_TIKTOK_CLIENT_SECRET',
  'SOCIAL_OAUTH_STATE_SECRET',
  'SOCIAL_META_WEBHOOK_VERIFY_TOKEN'
)

Write-Host "Social OAuth secrets for project: $ProjectId" -ForegroundColor Cyan
Write-Host "Ensure gcloud is authenticated: gcloud auth login" -ForegroundColor DarkYellow

foreach ($name in $secretNames) {
  $exists = gcloud secrets describe $name --project $ProjectId 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[skip] $name already exists" -ForegroundColor DarkGray
    continue
  }

  $value = ''
  if ($Interactive) {
    $secure = Read-Host "Enter value for $name (leave blank to skip)"
    $value = $secure
  }

  if ([string]::IsNullOrWhiteSpace($value)) {
    if ($name -eq 'SOCIAL_OAUTH_STATE_SECRET' -or $name -eq 'SOCIAL_META_WEBHOOK_VERIFY_TOKEN') {
      $bytes = New-Object byte[] 32
      [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
      $value = [Convert]::ToBase64String($bytes)
      Write-Host "[auto] Generated $name" -ForegroundColor Green
    } else {
      Write-Host "[skip] $name — no value provided (get from developer console)" -ForegroundColor Yellow
      continue
    }
  }

  gcloud secrets create $name --project $ProjectId --replication-policy automatic
  $value | gcloud secrets versions add $name --project $ProjectId --data-file=-
  Write-Host "[ok] Created $name" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next: grant Cloud Functions runtime service account Secret Accessor on these secrets." -ForegroundColor Cyan
Write-Host "See van4/docs/SOCIAL_DEVELOPER_SETUP.md for Meta/Google/TikTok app registration." -ForegroundColor Cyan
