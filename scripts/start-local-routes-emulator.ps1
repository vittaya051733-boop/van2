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
Push-Location "C:/Users/TAM/Desktop/van2/_github_my_flutter"
try {
  firebase emulators:start --project $ProjectId --only functions,firestore
}
finally {
  Pop-Location
}
