param(
  [Parameter(Mandatory = $true)]
  [string]$GoogleRoutesApiKey,

  [Parameter(Mandatory = $false)]
  [string]$ProjectId = "van-merchant",

  [Parameter(Mandatory = $false)]
  [string]$RedisContainerName = "van2-redis",

  [Parameter(Mandatory = $false)]
  [string]$RedisUrl = "redis://127.0.0.1:6379",

  [Parameter(Mandatory = $true)]
  [string]$RedisToken
)

$ErrorActionPreference = "Stop"

function Assert-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "ไม่พบคำสั่ง '$name' กรุณาติดตั้งก่อนใช้งาน"
  }
}

Assert-Command "docker"
Assert-Command "firebase"

$jbrJava = "C:\Program Files\Android\Android Studio\jbr\bin\java.exe"
if ((Test-Path $jbrJava) -and ((java -version 2>&1 | Select-Object -First 1) -notmatch 'version "(2[1-9]|[3-9]\d+)')) {
  $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
  $env:Path = "$env:JAVA_HOME\bin;$env:Path"
  Write-Host "Using Java 21 from Android Studio JBR (Firebase emulator requires 21+)" -ForegroundColor Yellow
}

Write-Host "== ตรวจ Redis container ==" -ForegroundColor Cyan
$exists = docker ps -a --format "{{.Names}}" | Select-String "^$RedisContainerName$"
if (-not $exists) {
  docker run -d --name $RedisContainerName -p 6379:6379 redis:7-alpine redis-server --appendonly yes --requirepass $RedisToken | Out-Null
} else {
  $running = docker ps --format "{{.Names}}" | Select-String "^$RedisContainerName$"
  if (-not $running) {
    docker start $RedisContainerName | Out-Null
  }
}

$ping = docker exec $RedisContainerName redis-cli -a $RedisToken ping
if ($ping -notmatch "PONG") {
  throw "Redis ping ไม่สำเร็จ: $ping"
}
Write-Host "Redis พร้อมใช้งาน: $RedisUrl" -ForegroundColor Green

Write-Host "== ตั้ง ENV สำหรับ emulator ==" -ForegroundColor Cyan
$env:GOOGLE_ROUTES_API_KEY = $GoogleRoutesApiKey
$env:REDIS_URL = $RedisUrl
$env:REDIS_TOKEN = $RedisToken

Write-Host "== เริ่ม Firebase Emulator (functions + firestore) ==" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'start-van2-emulator.ps1') -ProjectId $ProjectId
