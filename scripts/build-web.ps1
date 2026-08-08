param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$secretsFile = Join-Path $PSScriptRoot 'web-build.secrets.ps1'
if (Test-Path $secretsFile) {
  Write-Host '[build-web] Loading scripts/web-build.secrets.ps1' -ForegroundColor Cyan
  . $secretsFile
}

function Resolve-GoogleMapsWebApiKey {
  if ($env:GOOGLE_MAPS_WEB_API_KEY) {
    return $env:GOOGLE_MAPS_WEB_API_KEY.Trim()
  }

  $indexHtml = Join-Path $repoRoot 'web\index.html'
  if (-not (Test-Path $indexHtml)) {
    return ''
  }

  $content = Get-Content $indexHtml -Raw
  if ($content -match '"apiKey"\s*:\s*"([^"]+)"') {
    return $Matches[1].Trim()
  }
  if ($content -match 'maps/api/js\?key=([^"&]+)') {
    return $Matches[1].Trim()
  }

  return ''
}

$mapsKey = Resolve-GoogleMapsWebApiKey
$buildArgs = @(
  'build', 'web',
  '--release',
  '--no-wasm-dry-run',
  '--no-web-resources-cdn',
  '--pwa-strategy=none'
)

if ($mapsKey) {
  Write-Host "[build-web] GOOGLE_MAPS_WEB_API_KEY from $(if ($env:GOOGLE_MAPS_WEB_API_KEY) { 'env' } else { 'web/index.html' })" -ForegroundColor Cyan
  $buildArgs += "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$mapsKey"
} else {
  Write-Warning 'No GOOGLE_MAPS_WEB_API_KEY found. Places/Directions search may be limited on web.'
}

if ($env:APP_CHECK_RECAPTCHA_SITE_KEY) {
  $buildArgs += "--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=$($env:APP_CHECK_RECAPTCHA_SITE_KEY)"
} else {
  Write-Warning 'APP_CHECK_RECAPTCHA_SITE_KEY not set — web login/checkout callables may fail in production.'
}

Write-Host '[build-web] Self-hosting CanvasKit/static web resources (--no-web-resources-cdn) for Safari/mobile reliability.' -ForegroundColor Cyan
Write-Host '[build-web] PWA strategy: none (avoid stale service-worker cache on deploy).' -ForegroundColor Cyan

Write-Host "[build-web] flutter $($buildArgs -join ' ')" -ForegroundColor Cyan
if ($DryRun) {
  Write-Host '[dry-run] Skipping flutter build.' -ForegroundColor Yellow
  exit 0
}

flutter @buildArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host '[build-web] Output: build\web' -ForegroundColor Green
