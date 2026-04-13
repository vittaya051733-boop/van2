param(
  [string]$ProjectId = 'van-merchant'
)

$ErrorActionPreference = 'Stop'

flutter build web
firebase deploy --only hosting --project $ProjectId