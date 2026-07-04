<#
.SYNOPSIS
  YouTube OAuth setup for van4 Social Dashboard (project van-merchant)
#>
param(
  [string]$ProjectId = 'van-merchant',
  [string]$ProjectNumber = '802503541368',
  [string]$SupportEmail = 'vittaya051733@gmail.com',
  [string]$AppTitle = 'VANTALAD Admin Social',
  [string]$ClientDisplayName = 'Social OAuth Callback',
  [string]$RedirectUri = 'https://asia-southeast1-van-merchant.cloudfunctions.net/socialOAuthCallback',
  [string]$ClientId = '',
  [string]$ClientSecret = '',
  [switch]$SkipBrowser,
  [switch]$SkipSecrets,
  [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-GcloudAuth {
  $account = gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>$null
  if (-not $account) {
    throw 'gcloud not logged in. Run: gcloud auth login'
  }
  Write-Host "gcloud account: $account" -ForegroundColor DarkGray
}

function Ensure-YouTubeApi {
  Write-Step 'Check YouTube Data API v3'
  $enabled = gcloud services list --enabled --project $ProjectId `
    --filter='name:youtube.googleapis.com' --format='value(name)' 2>$null
  if ($enabled) {
    Write-Host '[ok] youtube.googleapis.com already enabled' -ForegroundColor Green
    return
  }
  gcloud services enable youtube.googleapis.com --project $ProjectId | Out-Null
  Write-Host '[ok] enabled youtube.googleapis.com' -ForegroundColor Green
}

function Get-FunctionsServiceAccount {
  $sa = gcloud functions describe getSocialOAuthUrl `
    --project $ProjectId --region asia-southeast1 `
    --gen2 --format='value(serviceConfig.serviceAccountEmail)' 2>$null
  if ($sa) { return $sa }
  return "${ProjectNumber}-compute@developer.gserviceaccount.com"
}

function Set-SecretValue([string]$SecretName, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Empty value for secret: $SecretName"
  }
  gcloud secrets describe $SecretName --project $ProjectId 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $Value | gcloud secrets versions add $SecretName --project $ProjectId --data-file=-
    Write-Host "[ok] updated secret $SecretName" -ForegroundColor Green
  } else {
    gcloud secrets create $SecretName --project $ProjectId --replication-policy automatic
    $Value | gcloud secrets versions add $SecretName --project $ProjectId --data-file=-
    Write-Host "[ok] created secret $SecretName" -ForegroundColor Green
  }
}

function Grant-SecretAccessor([string]$SecretName, [string]$ServiceAccount) {
  gcloud secrets add-iam-policy-binding $SecretName `
    --project $ProjectId `
    --member "serviceAccount:$ServiceAccount" `
    --role roles/secretmanager.secretAccessor `
    --quiet | Out-Null
  Write-Host "[ok] Secret Accessor: $SecretName -> $ServiceAccount" -ForegroundColor Green
}

function Open-ConsolePages {
  if ($SkipBrowser) { return }
  Write-Step 'Open Google Cloud Console'
  Start-Process "https://console.cloud.google.com/auth/branding?project=$ProjectId"
  Start-Process "https://console.cloud.google.com/auth/clients/create?project=$ProjectId"
  Write-Host ""
  Write-Host "Console steps (van-merchant has no GCP Organization - CLI cannot create OAuth client):" -ForegroundColor Yellow
  Write-Host "  1) OAuth consent: app name = $AppTitle"
  Write-Host "     scopes: youtube.upload, youtube.force-ssl, youtube.readonly"
  Write-Host "  2) Create OAuth client: Web application"
  Write-Host "     redirect URI: $RedirectUri"
  Write-Host "  3) Re-run with -ClientId and -ClientSecret"
}

function Try-GcloudIapOAuth {
  Write-Step 'Try gcloud iap oauth (usually fails without Organization)'
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $brandList = & gcloud iap oauth-brands list --project $ProjectId --format=json 2>&1 | Out-String
  $exit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($exit -ne 0) {
    if ($brandList -match 'Project must belong to an organization') {
      Write-Host '[skip] project has no Organization' -ForegroundColor Yellow
    } else {
      Write-Host '[skip] gcloud iap oauth-brands unavailable' -ForegroundColor Yellow
    }
    return $null
  }

  $brands = @()
  if ($brandList) { $brands = $brandList | ConvertFrom-Json }
  $brandName = $null
  if ($brands.Count -gt 0) {
    $brandName = $brands[0].name
  } else {
    $created = gcloud iap oauth-brands create `
      --application_title=$AppTitle `
      --support_email=$SupportEmail `
      --project $ProjectId `
      --format=json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $created) { return $null }
    $brandName = ($created | ConvertFrom-Json).name
  }

  $clientJson = gcloud iap oauth-clients create $brandName `
    --display_name=$ClientDisplayName `
    --project $ProjectId `
    --format=json 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $clientJson) { return $null }

  $client = $clientJson | ConvertFrom-Json
  if ($client.name -match '/identityAwareProxyClients/([^/]+)$') {
    return @{
      ClientId = "${ProjectNumber}-$($Matches[1]).apps.googleusercontent.com"
      ClientSecret = [string]$client.secret
    }
  }
  return $null
}

Write-Host "YouTube OAuth setup - project $ProjectId" -ForegroundColor White
Test-GcloudAuth
Ensure-YouTubeApi

if (-not $ClientId -or -not $ClientSecret) {
  $iap = Try-GcloudIapOAuth
  if ($iap) {
    $ClientId = $iap.ClientId
    $ClientSecret = $iap.ClientSecret
    Write-Host "[ok] credentials from gcloud iap" -ForegroundColor Green
  }
}

if (-not $ClientId -or -not $ClientSecret) {
  Open-ConsolePages
  if ($NonInteractive) {
    throw 'Missing ClientId/ClientSecret. Create in Console, then re-run with -ClientId and -ClientSecret'
  }
  if (-not $ClientId) {
    $ClientId = Read-Host 'Paste Web application Client ID'
  }
  if (-not $ClientSecret) {
    $secure = Read-Host 'Paste Client Secret' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  }
}

if ($SkipSecrets) {
  Write-Host "SkipSecrets - Client ID: $ClientId"
  exit 0
}

Write-Step 'Write Secret Manager'
Set-SecretValue 'SOCIAL_GOOGLE_OAUTH_CLIENT_ID' $ClientId.Trim()
Set-SecretValue 'SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET' $ClientSecret.Trim()

Write-Step 'Grant Secret Accessor to Cloud Functions runtime'
$runtimeSa = Get-FunctionsServiceAccount
Write-Host "Runtime SA: $runtimeSa" -ForegroundColor DarkGray
Grant-SecretAccessor 'SOCIAL_GOOGLE_OAUTH_CLIENT_ID' $runtimeSa
Grant-SecretAccessor 'SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET' $runtimeSa

Write-Step 'Done'
Write-Host "Redirect URI must match: $RedirectUri" -ForegroundColor Green
Write-Host "Next: deploy getSocialOAuthUrl and socialOAuthCallback functions from van2" -ForegroundColor Green
