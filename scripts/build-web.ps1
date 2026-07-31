param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Resolve-GoogleMapsWebApiKey {
  if ($env:GOOGLE_MAPS_WEB_API_KEY) {
    return $env:GOOGLE_MAPS_WEB_API_KEY.Trim()
  }

  $indexHtml = Join-Path $repoRoot 'web\index.html'
  if (-not (Test-Path $indexHtml)) {
    return ''
  }

  $content = Get-Content $indexHtml -Raw
  if ($content -match 'maps/api/js\?key=([^"&]+)') {
    return $Matches[1].Trim()
  }

  return ''
}

$mapsKey = Resolve-GoogleMapsWebApiKey
$buildArgs = @(
  'build', 'web',
  '--release',
  '--no-wasm-dry-run'
)

if ($mapsKey) {
  Write-Host "[build-web] GOOGLE_MAPS_WEB_API_KEY from $(if ($env:GOOGLE_MAPS_WEB_API_KEY) { 'env' } else { 'web/index.html' })" -ForegroundColor Cyan
  $buildArgs += "--dart-define=GOOGLE_MAPS_WEB_API_KEY=$mapsKey"
} else {
  Write-Warning 'No GOOGLE_MAPS_WEB_API_KEY found. Places/Directions search may be limited on web.'
}

if ($env:APP_CHECK_RECAPTCHA_SITE_KEY) {
  $buildArgs += "--dart-define=APP_CHECK_RECAPTCHA_SITE_KEY=$($env:APP_CHECK_RECAPTCHA_SITE_KEY)"
}

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
