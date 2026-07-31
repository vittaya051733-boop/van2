# Thai deploy messages - loaded as UTF-8 at runtime (safe on Windows PowerShell 5.1)
$script:VanDeployMessages = $null

function Initialize-VanDeployMessages {
  if ($script:VanDeployMessages) {
    return
  }

  $scriptsRoot = if ($script:VanDeployScriptsRoot) { $script:VanDeployScriptsRoot } else { $PSScriptRoot }
  $jsonPath = Join-Path $scriptsRoot 'deploy-messages.th.json'
  if (-not (Test-Path $jsonPath)) {
    throw "Missing Thai deploy messages file: $jsonPath"
  }

  $raw = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8
  $script:VanDeployMessages = $raw | ConvertFrom-Json
}

function Get-VanMsg {
  param(
    [Parameter(Mandatory)][string]$Key,
    [object[]]$MessageArgs = @()
  )

  Initialize-VanDeployMessages
  $template = $script:VanDeployMessages.$Key
  if (-not $template) {
    throw "Missing deploy message key: $Key"
  }

  if ($MessageArgs -and $MessageArgs.Count -gt 0) {
    return [string]::Format($template, $MessageArgs)
  }
  return [string]$template
}

function Get-VanAckTh { Get-VanMsg 'ackTh' }
function Get-VanAckEn { Get-VanMsg 'ackEn' }
function Get-VanSharedImpactTh { Get-VanMsg 'sharedImpactTh' }
function Get-VanSharedImpactEn { Get-VanMsg 'sharedImpactEn' }

function Get-VanSelfImpactTh {
  param([Parameter(Mandatory)][string]$App)
  (Get-VanMsg 'selfImpactPrefixTh') + $App
}

function Get-VanSelfImpactEn {
  param([Parameter(Mandatory)][string]$App)
  (Get-VanMsg 'selfImpactPrefixEn') + $App
}

function ConvertTo-VanDeployTokenEn {
  param([string]$Value)
  if (-not $Value) { return $Value }
  $approveTh = Get-VanMsg 'approvePrefixTh'
  $approveEn = Get-VanMsg 'approvePrefixEn'
  if ($Value.StartsWith($approveTh)) {
    return $approveEn + $Value.Substring($approveTh.Length)
  }
  return $Value
}

function ConvertTo-VanDeployTokenTh {
  param([string]$Value)
  if (-not $Value) { return $Value }
  $approveTh = Get-VanMsg 'approvePrefixTh'
  $approveEn = Get-VanMsg 'approvePrefixEn'
  if ($Value.StartsWith($approveEn)) {
    return $approveTh + $Value.Substring($approveEn.Length)
  }
  return $Value
}

function ConvertTo-VanImpactTokenEn {
  param([string]$Value)
  if (-not $Value) { return $Value }
  $sharedTh = Get-VanMsg 'sharedImpactTh'
  $sharedEn = Get-VanMsg 'sharedImpactEn'
  $selfTh = Get-VanMsg 'selfImpactPrefixTh'
  $selfEn = Get-VanMsg 'selfImpactPrefixEn'
  if ($Value.StartsWith($sharedTh)) {
    return $sharedEn + $Value.Substring($sharedTh.Length)
  }
  if ($Value.StartsWith($selfTh)) {
    return $selfEn + $Value.Substring($selfTh.Length)
  }
  return $Value
}

function ConvertTo-VanImpactTokenTh {
  param([string]$Value)
  if (-not $Value) { return $Value }
  $sharedTh = Get-VanMsg 'sharedImpactTh'
  $sharedEn = Get-VanMsg 'sharedImpactEn'
  $selfTh = Get-VanMsg 'selfImpactPrefixTh'
  $selfEn = Get-VanMsg 'selfImpactPrefixEn'
  if ($Value.StartsWith($sharedEn)) {
    return $sharedTh + $Value.Substring($sharedEn.Length)
  }
  if ($Value.StartsWith($selfEn)) {
    return $selfTh + $Value.Substring($selfEn.Length)
  }
  return $Value
}

function ConvertTo-VanAckEn {
  param([string]$Value)
  if (-not $Value) { return $Value }
  if ($Value.Trim() -eq (Get-VanAckTh)) { return (Get-VanAckEn) }
  return $Value
}

function Test-VanDeployTokenMatch {
  param(
    [string]$Provided,
    [string]$ExpectedEn
  )
  (ConvertTo-VanDeployTokenEn $Provided) -eq $ExpectedEn
}

function Test-VanImpactTokenMatch {
  param(
    [string]$Provided,
    [string]$ExpectedEn
  )
  (ConvertTo-VanImpactTokenEn $Provided) -eq $ExpectedEn
}

function Test-VanAckMatch {
  param(
    [string]$Provided,
    [string]$ExpectedEn = (Get-VanAckEn)
  )
  (ConvertTo-VanAckEn $Provided) -eq $ExpectedEn
}
