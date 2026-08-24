# Register App Check debug tokens for van1–van4 Android apps (dev/sideload).
# Play Integrity SHA registration: run print-upload-keystore-sha.ps1 per app, then Firebase Console.
param(
  [string]$ProjectNumber = '802503541368'
)

$ErrorActionPreference = 'Stop'

function Get-GcloudAccessToken {
  $token = & gcloud auth print-access-token 2>$null
  if (-not $token) {
    throw 'gcloud auth print-access-token failed — run: gcloud auth login'
  }
  return $token.Trim()
}

function Register-AppCheckDebugToken {
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$DebugToken
  )

  $token = Get-GcloudAccessToken
  $body = @{
    displayName = $Label
    token       = $DebugToken
  } | ConvertTo-Json

  $uri = "https://firebaseappcheck.googleapis.com/v1/projects/$ProjectNumber/apps/$AppId/debugTokens"
  try {
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers @{
      Authorization = "Bearer $token"
      'Content-Type'  = 'application/json'
    } -Body $body
    Write-Host "[OK] $Label" -ForegroundColor Green
    if ($response.name) {
      Write-Host "     $($response.name)" -ForegroundColor DarkGray
    }
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    $detail = $_.ErrorDetails.Message
    if ($status -eq 409 -or ($detail -match 'ALREADY_EXISTS|already exists')) {
      Write-Host "[OK] $Label (already registered)" -ForegroundColor Green
    } else {
      Write-Host "[WARN] $Label failed ($status)" -ForegroundColor Yellow
      if ($detail) { Write-Host $detail -ForegroundColor DarkYellow }
    }
  }
}

Write-Host ''
Write-Host '=== Van ecosystem App Check debug tokens ===' -ForegroundColor Cyan
Write-Host "Project: van-merchant ($ProjectNumber)" -ForegroundColor Gray
Write-Host ''

Register-AppCheckDebugToken -Label 'van1 van.merchant' `
  -AppId '1:802503541368:android:c8333c4310663e19f6a38d' `
  -DebugToken 'd1a5b8e3-7f2c-4a6d-9e1b-3c4d5e6f7a82'

Register-AppCheckDebugToken -Label 'van2 Van2.com' `
  -AppId '1:802503541368:android:8512943c62753f90f6a38d' `
  -DebugToken 'c8e4a1f2-6b3d-4e9a-8f7c-2d5e6a9b0c41'

Register-AppCheckDebugToken -Label 'van3 van3.rider.com' `
  -AppId '1:802503541368:android:af96e87f3975ce44f6a38d' `
  -DebugToken '7e1d581a-5018-46b9-ae4f-66967a8fe773'

Register-AppCheckDebugToken -Label 'van4 van4.com admin' `
  -AppId '1:802503541368:android:bddc4d7775d9f43cf6a38d' `
  -DebugToken 'a3f9c2e1-4b8d-4a6f-9e2c-1d7b5e8f0a42'

Write-Host ''
Write-Host 'Play Integrity (release): enable per app in Firebase Console → App Check' -ForegroundColor Cyan
Write-Host 'SHA: van2\scripts\print-upload-keystore-sha.ps1 (per app key.properties)' -ForegroundColor White
Write-Host 'https://console.firebase.google.com/project/van-merchant/appcheck/apps' -ForegroundColor DarkGray
Write-Host ''
