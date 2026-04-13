param(
  [string]$ProjectId = 'van-merchant',
  [string]$Domain = '',
  [string[]]$DkimSelectors = @('default', 'mail', 'smtp', 's1', 's2')
)

$ErrorActionPreference = 'Stop'

function Write-Status {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][bool]$Ok,
    [string]$Hint = ''
  )

  if ($Ok) {
    Write-Host "[OK] $Label" -ForegroundColor Green
    return
  }

  Write-Host "[MISSING] $Label" -ForegroundColor Yellow
  if ($Hint) {
    Write-Host "         $Hint" -ForegroundColor DarkYellow
  }
}

function Test-CommandAvailable {
  param([Parameter(Mandatory = $true)][string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-FirebaseSecret {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ProjectId
  )

  firebase functions:secrets:get $Name --project $ProjectId *> $null
  return $LASTEXITCODE -eq 0
}

function Test-DnsTxtContains {
  param(
    [Parameter(Mandatory = $true)][string]$Host,
    [Parameter(Mandatory = $true)][string]$Needle
  )

  try {
    $records = Resolve-DnsName -Name $Host -Type TXT -ErrorAction Stop
    $joined = ($records | ForEach-Object { ($_.Strings -join '') }) -join ' '
    return $joined -match [Regex]::Escape($Needle)
  }
  catch {
    return $false
  }
}

function Test-DnsMx {
  param([Parameter(Mandatory = $true)][string]$Host)

  try {
    $mx = Resolve-DnsName -Name $Host -Type MX -ErrorAction Stop
    return $mx.Count -gt 0
  }
  catch {
    return $false
  }
}

Write-Host ''
Write-Host "Email OTP Readiness Check (project: $ProjectId)" -ForegroundColor Cyan
Write-Host ''

if (-not (Test-CommandAvailable -Name 'firebase')) {
  Write-Host '[MISSING] Firebase CLI is not installed or not on PATH' -ForegroundColor Red
  Write-Host 'Install: npm install -g firebase-tools' -ForegroundColor DarkYellow
  exit 1
}

$requiredSecrets = @('SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM')
$missingSecrets = New-Object System.Collections.Generic.List[string]

foreach ($secret in $requiredSecrets) {
  $ok = Test-FirebaseSecret -Name $secret -ProjectId $ProjectId
  Write-Status -Label "Secret $secret" -Ok $ok -Hint 'Run scripts/set-firebase-smtp-secrets.ps1 to set all SMTP secrets.'
  if (-not $ok) {
    $missingSecrets.Add($secret) | Out-Null
  }
}

Write-Host ''

$functionsRaw = firebase functions:list --project $ProjectId 2>&1 | Out-String
$hasSend = $functionsRaw -match 'sendEmailOtp'
$hasVerify = $functionsRaw -match 'verifyEmailOtp'

Write-Status -Label 'Function sendEmailOtp deployed' -Ok $hasSend -Hint 'Deploy with: firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project <project-id>'
Write-Status -Label 'Function verifyEmailOtp deployed' -Ok $hasVerify -Hint 'Deploy with: firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project <project-id>'

Write-Host ''

if ([string]::IsNullOrWhiteSpace($Domain)) {
  Write-Host '[INFO] Skip DNS check (no -Domain provided).' -ForegroundColor DarkCyan
  Write-Host '       Example: .\scripts\check-email-otp-readiness.ps1 -Domain yourdomain.com' -ForegroundColor DarkCyan
}
else {
  $mxOk = Test-DnsMx -Host $Domain
  $spfOk = Test-DnsTxtContains -Host $Domain -Needle 'v=spf1'
  $dmarcOk = Test-DnsTxtContains -Host "_dmarc.$Domain" -Needle 'v=DMARC1'

  $dkimOk = $false
  foreach ($selector in $DkimSelectors) {
    $dkimHost = "$selector._domainkey.$Domain"
    if (Test-DnsTxtContains -Host $dkimHost -Needle 'v=DKIM1') {
      $dkimOk = $true
      break
    }
  }

  Write-Status -Label "MX record for $Domain" -Ok $mxOk -Hint 'Create MX records from your email provider (Google Workspace, Zoho, Hostinger, etc.).'
  Write-Status -Label "SPF TXT for $Domain" -Ok $spfOk -Hint 'Add SPF TXT from your email provider guidance.'
  Write-Status -Label "DKIM for $Domain" -Ok $dkimOk -Hint 'Publish DKIM key(s) and enable DKIM signing in your mail provider.'
  Write-Status -Label "DMARC for $Domain" -Ok $dmarcOk -Hint 'Add _dmarc TXT such as: v=DMARC1; p=none; rua=mailto:postmaster@yourdomain.com'
}

Write-Host ''

if ($missingSecrets.Count -gt 0 -or -not $hasSend -or -not $hasVerify) {
  Write-Host 'Next actions:' -ForegroundColor Cyan
  if ($missingSecrets.Count -gt 0) {
    Write-Host '1) Set SMTP secrets:' -ForegroundColor White
    Write-Host '   .\scripts\set-firebase-smtp-secrets.ps1 -ProjectId van-merchant' -ForegroundColor Gray
  }
  if (-not $hasSend -or -not $hasVerify) {
    Write-Host '2) Deploy OTP functions:' -ForegroundColor White
    Write-Host '   firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project van-merchant' -ForegroundColor Gray
  }
  Write-Host '3) Re-run this checker to confirm green status.' -ForegroundColor White
}
else {
  Write-Host 'All core Email OTP checks passed.' -ForegroundColor Green
}
