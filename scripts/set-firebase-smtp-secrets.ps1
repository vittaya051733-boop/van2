param(
  [string]$ProjectId = 'van-merchant'
)

$ErrorActionPreference = 'Stop'

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
firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project $ProjectId