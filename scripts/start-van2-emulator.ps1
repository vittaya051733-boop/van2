<#
.SYNOPSIS
  Start van2 Firebase emulators (Firestore + Functions) for local dev.

.EXAMPLE
  .\start-van2-emulator.ps1
  .\start-van2-emulator.ps1 -WithRoutes -GoogleRoutesApiKey "AIza..." -RedisToken "my-redis-pass"
#>
param(
  [switch]$WithRoutes,
  [string]$GoogleRoutesApiKey = '',
  [string]$RedisToken = '',
  [string]$ProjectId = 'van-merchant',
  [string]$RedisContainerName = 'van2-redis'
)

$ErrorActionPreference = 'Stop'
$van2Root = Split-Path $PSScriptRoot -Parent
$functionsDir = Join-Path $van2Root 'functions'
$secretLocal = Join-Path $functionsDir '.secret.local'
$secretExample = Join-Path $functionsDir '.secret.local.example'

function Resolve-VanEmulatorJava {
  $jbr = 'C:\Program Files\Android\Android Studio\jbr'
  if (Test-Path (Join-Path $jbr 'bin\java.exe')) {
    $env:JAVA_HOME = $jbr
    $env:Path = "$env:JAVA_HOME\bin;" + (($env:Path -split ';' | Where-Object { $_ -and ($_ -ne "$env:JAVA_HOME\bin") }) -join ';')
    Write-Host "Java: Android Studio JBR (21+)" -ForegroundColor DarkGray
    return
  }
  throw 'Firebase emulator needs Java 21+. Install JDK 21 or Android Studio JBR.'
}

function Stop-EmulatorPorts {
  $ports = @(4000, 4400, 5001, 8080)
  foreach ($port in $ports) {
    $lines = netstat -ano | Select-String "127.0.0.1:$port\s"
    foreach ($line in $lines) {
      if ($line -match '\s(\d+)\s*$') {
        $procId = [int]$Matches[1]
        if ($procId -gt 0) {
          Write-Host "Stopping process on port $port (PID $procId)..." -ForegroundColor Yellow
          Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
      }
    }
  }
  Start-Sleep -Seconds 2
}

function Use-Node22 {
  if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) {
    Write-Host 'nvm not found; using current Node (functions package expects 22)' -ForegroundColor Yellow
    return
  }
  nvm use 22.20.0 2>&1 | Out-Host
}

function Ensure-SecretLocal {
  if (Test-Path $secretLocal) {
    return
  }
  if (Test-Path $secretExample) {
    Copy-Item $secretExample $secretLocal
    Write-Host "Created $secretLocal from example" -ForegroundColor Yellow
    return
  }
  throw "Missing $secretLocal. Create it with emulator placeholder secrets."
}

function Start-RedisIfRequested {
  if (-not $WithRoutes) {
    return
  }
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP Redis: Docker not available. Start Docker Desktop for routes+Redis dev.' -ForegroundColor Yellow
    return
  }
  if ([string]::IsNullOrWhiteSpace($GoogleRoutesApiKey) -or [string]::IsNullOrWhiteSpace($RedisToken)) {
    throw 'WithRoutes requires -GoogleRoutesApiKey and -RedisToken'
  }

  $exists = docker ps -a --format '{{.Names}}' | Select-String "^$RedisContainerName$"
  if (-not $exists) {
    docker run -d --name $RedisContainerName -p 6379:6379 redis:7-alpine redis-server --appendonly yes --requirepass $RedisToken | Out-Null
  }
  else {
    $running = docker ps --format '{{.Names}}' | Select-String "^$RedisContainerName$"
    if (-not $running) {
      docker start $RedisContainerName | Out-Null
    }
  }

  $ping = docker exec $RedisContainerName redis-cli -a $RedisToken ping
  if ($ping -notmatch 'PONG') {
    throw "Redis ping failed: $ping"
  }

  $env:GOOGLE_ROUTES_API_KEY = $GoogleRoutesApiKey
  $env:REDIS_URL = 'redis://127.0.0.1:6379'
  $env:REDIS_TOKEN = $RedisToken
  Write-Host 'Redis + GOOGLE_ROUTES_API_KEY ready for functions' -ForegroundColor Green
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  throw 'Firebase CLI not found. Run: npm i -g firebase-tools'
}

Resolve-VanEmulatorJava
Use-Node22
Ensure-SecretLocal
Stop-EmulatorPorts
Start-RedisIfRequested

Write-Host ''
Write-Host '== Starting van2 Firebase Emulator (firestore + functions) ==' -ForegroundColor Cyan
Write-Host "Project: $ProjectId"
Write-Host 'UI:      http://127.0.0.1:4000/'
Write-Host 'Firestore: 127.0.0.1:8080'
Write-Host 'Functions: 127.0.0.1:5001'
Write-Host ''

$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60000'

Push-Location $van2Root
try {
  firebase emulators:start --project $ProjectId --only 'firestore,functions'
}
finally {
  Pop-Location
}
