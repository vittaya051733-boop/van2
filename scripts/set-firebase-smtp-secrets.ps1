param(
  [string]$ProjectId = 'van-merchant',
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$expectedConfirmation = "APPROVE:van2:$ProjectId"
if ($ConfirmDeploy -ne $expectedConfirmation) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmDeploy '$expectedConfirmation'"
  exit 1
}
Write-Host "[guard] Confirmation accepted: $expectedConfirmation" -ForegroundColor Green

$expectedFile = 'functions'
$expectedImpact = 'SELF:van2'
if ($ConfirmFile -ne $expectedFile) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmFile '$expectedFile'"
  exit 1
}
if ($ConfirmImpact -ne $expectedImpact) {
  Write-Error "Deployment blocked. Re-run with: -ConfirmImpact '$expectedImpact'"
  exit 1
}
Write-Host "[guard] File confirmation accepted: $expectedFile" -ForegroundColor Green
Write-Host "[guard] Impact confirmation accepted: $expectedImpact" -ForegroundColor Green

if ($InteractiveConfirm) {
  $interactiveFile = Read-Host "Interactive confirm file scope (expected: $expectedFile)"
  if ($interactiveFile -ne $expectedFile) {
    Write-Error "Interactive confirmation failed for file scope."
    exit 1
  }
  $interactiveImpact = Read-Host "Interactive confirm impact scope (expected: $expectedImpact)"
  if ($interactiveImpact -ne $expectedImpact) {
    Write-Error "Interactive confirmation failed for impact scope."
    exit 1
  }
  Write-Host "[interactive] File and impact confirmations accepted." -ForegroundColor Green
  $FinalAcknowledge = Read-Host "Type final acknowledgement before deploy (expected: YES I UNDERSTAND)"
}

$expectedFinalAcknowledge = 'YES I UNDERSTAND'
if ($FinalAcknowledge -ne $expectedFinalAcknowledge) {
  Write-Error "Deployment blocked. Re-run with: -FinalAcknowledge '$expectedFinalAcknowledge'"
  exit 1
}
Write-Host "[guard] Final acknowledgement accepted." -ForegroundColor Green

function Set-FirebaseSecret {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $tempFile = [System.IO.Path]::GetTempFileName()
  try {
    Set-Content -Path $tempFile -Value $Value -NoNewline
    Get-Content -Path $tempFile | firebase functions:secrets:set $Name --project $ProjectId
  }
  finally {
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
  }
}

$smtpHost = Read-Host 'SMTP host เช่น smtp.hostinger.com'
$smtpPort = Read-Host 'SMTP port เช่น 465 หรือ 587'
$smtpUser = Read-Host 'SMTP username เช่น no-reply@yourdomain.com'
$smtpPassSecure = Read-Host 'SMTP password หรือ app password' -AsSecureString
$smtpFrom = Read-Host 'From email เช่น Van Market <no-reply@yourdomain.com>'

$smtpPass = [System.Net.NetworkCredential]::new('', $smtpPassSecure).Password

Set-FirebaseSecret -Name 'SMTP_HOST' -Value $smtpHost
Set-FirebaseSecret -Name 'SMTP_PORT' -Value $smtpPort
Set-FirebaseSecret -Name 'SMTP_USER' -Value $smtpUser
Set-FirebaseSecret -Name 'SMTP_PASS' -Value $smtpPass
Set-FirebaseSecret -Name 'SMTP_FROM' -Value $smtpFrom

Write-Host ''
Write-Host 'SMTP secrets updated. Deploying OTP functions...' -ForegroundColor Cyan
if ($DryRun) {
  Write-Host '[dry-run] Skipping firebase deploy for OTP functions.' -ForegroundColor Yellow
  return
}
firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project $ProjectId