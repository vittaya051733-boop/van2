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

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi

Write-Host "Starting flutter run --machine on $DeviceId ..." -ForegroundColor Cyan
Write-Host "Logs: $LogFile"
Write-Host "Hot reload: scripts\flutter-hot-reload.ps1"

$appId = $null
$debugUri = $null
$lineQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$reloadResult = $null
$reloadDone = $false

function Handle-FlutterLine {
  param([string]$Line)

  if (-not $Line) {
    return
  }

  Add-Content -Path $LogFile -Value $Line -Encoding utf8
  Write-Host $Line

  if ($Line -match '"event"\s*:\s*"app\.debugPort"') {
    if ($Line -match '"appId"\s*:\s*"([^"]+)"') {
      $script:appId = $Matches[1]
    }
    if ($Line -match '"wsUri"\s*:\s*"ws://127\.0\.0\.1:(\d+)(/[^"]+)"') {
      $script:debugUri = "http://127.0.0.1:$($Matches[1])$($Matches[2])"
    } elseif ($Line -match '"uri"\s*:\s*"([^"]+)"') {
      $script:debugUri = $Matches[1]
    }
    if ($script:appId) {
      $resolvedDebugUri = if ($script:debugUri) { $script:debugUri } else { '' }
      Save-Session -AppId $script:appId -DebugUri $resolvedDebugUri
    }
  }

  if ($Line -match '"event"\s*:\s*"app\.started"') {
    if (-not $script:appId -and ($Line -match '"appId"\s*:\s*"([^"]+)"')) {
      $script:appId = $Matches[1]
      $resolvedDebugUri = if ($script:debugUri) { $script:debugUri } else { '' }
      Save-Session -AppId $script:appId -DebugUri $resolvedDebugUri
    }
  }

  if ($script:reloadDone) {
    return
  }
  if ($Line -match '"id"\s*:\s*2' -and $Line -notmatch '"error"') {
    $script:reloadResult = 'ok'
    $script:reloadDone = $true
  } elseif ($Line -match '"id"\s*:\s*2.*"error"') {
    $script:reloadResult = $Line
    $script:reloadDone = $true
  }
}

$process.add_OutputDataReceived({
  param($sender, $eventArgs)
  if ($eventArgs.Data) {
    $lineQueue.Enqueue($eventArgs.Data)
  }
})
$process.add_ErrorDataReceived({
  param($sender, $eventArgs)
  if ($eventArgs.Data) {
    $lineQueue.Enqueue($eventArgs.Data)
  }
})
if (-not $process.Start()) {
  throw 'Failed to start flutter run --machine.'
}

Write-Host "Flutter dev supervisor started (PID $PID, flutter PID $($process.Id))." -ForegroundColor Green
$process.BeginOutputReadLine()
$process.BeginErrorReadLine()

try {
  while (-not $process.HasExited) {
    $dequeued = $null
    while ($lineQueue.TryDequeue([ref]$dequeued)) {
      Handle-FlutterLine -Line $dequeued
    }

    if (Test-Path $ReloadRequestFile) {
      $payload = (Get-Content $ReloadRequestFile -Raw).Trim()
      Remove-Item $ReloadRequestFile -Force -ErrorAction SilentlyContinue
      Remove-Item $ReloadResultFile -Force -ErrorAction SilentlyContinue

      if ($payload) {
        $reloadDone = $false
        $reloadResult = $null
        $process.StandardInput.WriteLine($payload)
        $process.StandardInput.Flush()

        $reloadDeadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $reloadDeadline -and -not $process.HasExited -and -not $reloadDone) {
          $dequeued = $null
          while ($lineQueue.TryDequeue([ref]$dequeued)) {
            Handle-FlutterLine -Line $dequeued
          }
          Start-Sleep -Milliseconds 100
        }

        if ($reloadResult -eq 'ok') {
          Set-Content -Path $ReloadResultFile -Value 'ok' -Encoding ascii
        } else {
          $message = if ($reloadResult) { $reloadResult } else { 'timeout' }
          Set-Content -Path $ReloadResultFile -Value $message -Encoding utf8
        }
      }
    }

    Start-Sleep -Milliseconds 100
  }

  $dequeued = $null
  while ($lineQueue.TryDequeue([ref]$dequeued)) {
    Handle-FlutterLine -Line $dequeued
  }
} finally {
  Remove-Item $SupervisorPidFile, $SessionFile, $ReloadRequestFile, $ReloadResultFile -Force -ErrorAction SilentlyContinue
  if (-not $process.HasExited) {
    $process.Kill()
  }
}

if ($process.ExitCode -and $process.ExitCode -ne 0) {
  exit $process.ExitCode
}
