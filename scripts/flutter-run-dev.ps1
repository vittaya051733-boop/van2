<#
.SYNOPSIS
  Run Flutter in machine mode and keep a reload channel open for flutter-hot-reload.ps1.
.EXAMPLE
  .\flutter-run-dev.ps1
  .\flutter-run-dev.ps1 -DeviceId emulator-5554
#>
param(
  [string]$DeviceId = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter CLI not found in PATH.'
}

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DevDir = Join-Path $ProjectRoot '.flutter-dev'
$LogFile = Join-Path $DevDir 'run-machine.log'
$SessionFile = Join-Path $DevDir 'session.json'
$ReloadRequestFile = Join-Path $DevDir 'reload.request'
$ReloadResultFile = Join-Path $DevDir 'reload.result'
$SupervisorPidFile = Join-Path $DevDir 'supervisor.pid'

New-Item -ItemType Directory -Force -Path $DevDir | Out-Null

if (Test-Path $SupervisorPidFile) {
  $oldPid = Get-Content $SupervisorPidFile -Raw
  if ($oldPid -match '^\d+$') {
    $oldProcess = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    if ($oldProcess -and $oldProcess.Path -like '*powershell*') {
      Write-Host "Stopping previous dev supervisor (PID $oldPid)..."
      Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 1
    }
  }
}

Set-Content -Path $SupervisorPidFile -Value $PID -Encoding ascii
Remove-Item $ReloadRequestFile, $ReloadResultFile -Force -ErrorAction SilentlyContinue
Set-Content -Path $LogFile -Value '' -Encoding utf8

function Save-Session {
  param(
    [string]$AppId,
    [string]$DebugUri
  )

  @{
    appId = $AppId
    debugUri = $DebugUri
    deviceId = $DeviceId
    supervisorPid = $PID
    updatedAt = (Get-Date).ToString('o')
  } | ConvertTo-Json | Set-Content -Path $SessionFile -Encoding utf8
}

$flutter = (Get-Command flutter -ErrorAction Stop).Source
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $flutter
$psi.Arguments = "run -d $DeviceId --machine"
$psi.WorkingDirectory = $ProjectRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)
if (-not $process) {
  throw 'Failed to start flutter run --machine.'
}

Write-Host "Flutter dev supervisor started (PID $PID, flutter PID $($process.Id))." -ForegroundColor Green
Write-Host "Logs: $LogFile"
Write-Host "Hot reload: scripts\flutter-hot-reload.ps1"

$appId = $null
$debugUri = $null
$reloadCounter = 0

try {
  while (-not $process.HasExited) {
    if (Test-Path $ReloadRequestFile) {
      $payload = (Get-Content $ReloadRequestFile -Raw).Trim()
      Remove-Item $ReloadRequestFile -Force -ErrorAction SilentlyContinue
      Remove-Item $ReloadResultFile -Force -ErrorAction SilentlyContinue

      if ($payload) {
        $reloadCounter++
        $process.StandardInput.WriteLine($payload)
        $process.StandardInput.Flush()

        $reloadDeadline = (Get-Date).AddSeconds(20)
        $reloadOk = $false
        $reloadError = $null

        while ((Get-Date) -lt $reloadDeadline -and -not $process.HasExited) {
          if ($process.StandardOutput.Peek() -ge 0) {
            $line = $process.StandardOutput.ReadLine()
            if ($line) {
              Add-Content -Path $LogFile -Value $line -Encoding utf8
              Write-Host $line
              if ($line -match '"id"\s*:\s*2' -and $line -notmatch '"error"') {
                $reloadOk = $true
                break
              }
              if ($line -match '"id"\s*:\s*2.*"error"') {
                $reloadError = $line
                break
              }
            }
          } else {
            Start-Sleep -Milliseconds 100
          }
        }

        if ($reloadOk) {
          Set-Content -Path $ReloadResultFile -Value 'ok' -Encoding ascii
        } else {
          $message = if ($reloadError) { $reloadError } else { 'timeout' }
          Set-Content -Path $ReloadResultFile -Value $message -Encoding utf8
        }
      }
    }

    if ($process.StandardOutput.Peek() -ge 0) {
      $line = $process.StandardOutput.ReadLine()
      if ($line) {
        Add-Content -Path $LogFile -Value $line -Encoding utf8
        Write-Host $line

        if ($line -match '"event"\s*:\s*"app\.debugPort"') {
          if ($line -match '"appId"\s*:\s*"([^"]+)"') {
            $appId = $Matches[1]
          }
          if ($line -match '"wsUri"\s*:\s*"ws://127\.0\.0\.1:(\d+)(/[^"]+)"') {
            $debugUri = "http://127.0.0.1:$($Matches[1])$($Matches[2])"
          } elseif ($line -match '"uri"\s*:\s*"([^"]+)"') {
            $debugUri = $Matches[1]
          }
          if ($appId) {
            $resolvedDebugUri = if ($debugUri) { $debugUri } else { '' }
            Save-Session -AppId $appId -DebugUri $resolvedDebugUri
          }
        }

        if ($line -match '"event"\s*:\s*"app\.started"') {
          if (-not $appId -and ($line -match '"appId"\s*:\s*"([^"]+)"')) {
            $appId = $Matches[1]
            $resolvedDebugUri = if ($debugUri) { $debugUri } else { '' }
            Save-Session -AppId $appId -DebugUri $resolvedDebugUri
          }
        }
      }
    } else {
      Start-Sleep -Milliseconds 100
    }
  }
} finally {
  Remove-Item $SupervisorPidFile, $SessionFile, $ReloadRequestFile, $ReloadResultFile -Force -ErrorAction SilentlyContinue
  if (-not $process.HasExited) {
    $process.Kill()
  }
}

while ($process.StandardError.Peek() -ge 0) {
  Write-Host $process.StandardError.ReadLine() -ForegroundColor Yellow
}

if ($process.ExitCode -and $process.ExitCode -ne 0) {
  exit $process.ExitCode
}
