<#
.SYNOPSIS
  Hot reload (or restart) a running Flutter app on a device/emulator.
.EXAMPLE
  .\flutter-hot-reload.ps1
  .\flutter-hot-reload.ps1 -DeviceId emulator-5554
  .\flutter-hot-reload.ps1 -Restart
#>
param(
  [string]$DeviceId = 'emulator-5554',
  [switch]$Restart
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter CLI not found in PATH.'
}

$commandName = if ($Restart) { 'app.restart' } else { 'app.reload' }
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DevDir = Join-Path $ProjectRoot '.flutter-dev'
$SessionFile = Join-Path $DevDir 'session.json'
$ReloadRequestFile = Join-Path $DevDir 'reload.request'
$ReloadResultFile = Join-Path $DevDir 'reload.result'
$SupervisorPidFile = Join-Path $DevDir 'supervisor.pid'

function Invoke-DevSupervisorReload {
  param([string]$AppId)

  if (-not (Test-Path $SupervisorPidFile)) {
    return $false
  }

  $supervisorPid = (Get-Content $SupervisorPidFile -Raw).Trim()
  if ($supervisorPid -notmatch '^\d+$') {
    return $false
  }

  $supervisor = Get-Process -Id ([int]$supervisorPid) -ErrorAction SilentlyContinue
  if (-not $supervisor) {
    return $false
  }

  Remove-Item $ReloadResultFile -Force -ErrorAction SilentlyContinue
  $payload = "[{`"method`":`"$commandName`",`"id`":2,`"params`":{`"appId`":`"$AppId`",`"force`":false,`"pause`":false}}]"
  Set-Content -Path $ReloadRequestFile -Value $payload -Encoding utf8 -NoNewline

  $deadline = (Get-Date).AddSeconds(25)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $ReloadResultFile) {
      $result = (Get-Content $ReloadResultFile -Raw).Trim()
      Remove-Item $ReloadResultFile -Force -ErrorAction SilentlyContinue
      if ($result -eq 'ok') {
        return $true
      }
      throw "Flutter $commandName failed: $result"
    }
    Start-Sleep -Milliseconds 150
  }

  throw "Flutter $commandName timed out waiting for dev supervisor."
}

if (Test-Path $SessionFile) {
  try {
    $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
    if ($session.appId -and ($session.supervisorPid -as [string]) -match '^\d+$') {
      if (Invoke-DevSupervisorReload -AppId $session.appId) {
        Write-Host $(if ($Restart) { 'Hot restart OK' } else { 'Hot reload OK' }) -ForegroundColor Green
        exit 0
      }
    }
  } catch {
    if ($_.Exception.Message -notmatch 'timed out|failed') {
      throw
    }
    Write-Host "Dev supervisor reload failed, trying attach fallback..." -ForegroundColor Yellow
  }
}

$flutter = (Get-Command flutter -ErrorAction Stop).Source
$debugUri = $null
if (Test-Path $SessionFile) {
  $session = Get-Content $SessionFile -Raw | ConvertFrom-Json
  if ($session.debugUri) {
    $debugUri = [string]$session.debugUri
  }
}

$attachArgs = if ($debugUri) {
  "attach --debug-uri=$debugUri --machine"
} else {
  "attach -d $DeviceId --machine"
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $flutter
$psi.Arguments = $attachArgs
$psi.WorkingDirectory = $ProjectRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)
if (-not $process) {
  throw 'Failed to start flutter attach.'
}

$appId = $null
$deadline = (Get-Date).AddSeconds(20)

while ((Get-Date) -lt $deadline) {
  if ($process.StandardOutput.Peek() -ge 0) {
    $line = $process.StandardOutput.ReadLine()
    if ($line) {
      Write-Host $line
      if ($line -match '"appId"\s*:\s*"([^"]+)"') {
        $appId = $Matches[1]
      }
      if ($line -match '"event"\s*:\s*"app\.started"') {
        break
      }
    }
  }

  if ($process.HasExited) {
    break
  }

  Start-Sleep -Milliseconds 150
}

if (-not $appId) {
  while ($process.StandardError.Peek() -ge 0) {
    Write-Host $process.StandardError.ReadLine() -ForegroundColor Yellow
  }
  if (-not $process.HasExited) {
    $process.Kill()
  }
  throw "Could not attach to Flutter on $DeviceId. Start: scripts\flutter-run-dev.ps1"
}

$payload = "[{`"method`":`"$commandName`",`"id`":2,`"params`":{`"appId`":`"$appId`",`"force`":false,`"pause`":false}}]"
$process.StandardInput.WriteLine($payload)
$process.StandardInput.Flush()

Start-Sleep -Seconds 3

while ($process.StandardOutput.Peek() -ge 0) {
  $line = $process.StandardOutput.ReadLine()
  if ($line) {
    Write-Host $line
    if ($line -match '"id"\s*:\s*2' -and $line -notmatch '"error"') {
      break
    }
    if ($line -match '"id"\s*:\s*2.*"error"') {
      if (-not $process.HasExited) {
        $process.Kill()
      }
      throw "Flutter $commandName failed: $line"
    }
  }
}

if (-not $process.HasExited) {
  $process.Kill()
}

Write-Host $(if ($Restart) { 'Hot restart OK' } else { 'Hot reload OK' }) -ForegroundColor Green
