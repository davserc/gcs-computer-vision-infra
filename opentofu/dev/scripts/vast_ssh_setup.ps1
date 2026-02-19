param(
  [string]$Project = "unlu-genai-serranodavid",
  [string]$SecretName = "VAST_SSH_KEY",
  [string]$KeyPath = "$HOME\.ssh\vast_ed25519",
  [string]$VastApiKey = $env:VAST_API_KEY,
  [string]$VastApiKeySecret = "VAST_API_KEY"
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $name"
  }
}

Require-Command "ssh-keygen"
Require-Command "gcloud"

function Require-EnvOrParam($value, $name) {
  if (-not $value -or $value.Trim().Length -eq 0) {
    throw "Missing $name. Provide -$name or set $name in environment."
  }
}

$keyDir = Split-Path -Parent $KeyPath
$pubKeyPath = "$KeyPath.pub"

if (-not (Test-Path $keyDir)) {
  New-Item -ItemType Directory -Path $keyDir | Out-Null
}

if (-not (Test-Path $KeyPath)) {
  Write-Host "Generating SSH key: $KeyPath"
  & ssh-keygen --% -t ed25519 -f $KeyPath -N "" -C "vast-gpu" | Out-Null
} else {
  Write-Host "SSH key already exists: $KeyPath"
}

if (-not (Test-Path $pubKeyPath)) {
  throw "Public key not found: $pubKeyPath"
}

& gcloud secrets describe $SecretName --project $Project *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creating secret: $SecretName"
  & gcloud secrets create $SecretName --replication-policy=automatic --project $Project | Out-Null
}

Write-Host "Uploading private key to Secret Manager: $SecretName"
$tmpKeyPath = $null
try {
  $keyBytes = [System.IO.File]::ReadAllBytes($KeyPath)
  $keyText = [System.Text.Encoding]::UTF8.GetString($keyBytes)
  $keyText = $keyText -replace "`r`n", "`n"
  $keyText = $keyText -replace "`r", "`n"
  if (-not $keyText.EndsWith("`n")) {
    $keyText += "`n"
  }

  $tmpKeyPath = [System.IO.Path]::GetTempFileName()
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmpKeyPath, $keyText, $utf8NoBom)

  & gcloud secrets versions add $SecretName --data-file $tmpKeyPath --project $Project | Out-Null
} finally {
  if ($tmpKeyPath -and (Test-Path $tmpKeyPath)) {
    Remove-Item -Force $tmpKeyPath
  }
}

if (-not $VastApiKey -or $VastApiKey.Trim().Length -eq 0) {
  try {
    $VastApiKey = & gcloud secrets versions access latest --secret $VastApiKeySecret --project $Project 2>$null
  } catch {
    $VastApiKey = $null
  }
}

Require-EnvOrParam $VastApiKey "VastApiKey"

$pubKey = Get-Content $pubKeyPath -Raw
$pubKey = $pubKey.Trim()
if (-not $pubKey.StartsWith("ssh-")) {
  throw "Public key format looks invalid: $pubKeyPath"
}

Write-Host "Registering public key in Vast.ai (if missing)..."
$headers = @{
  Authorization = "Bearer $VastApiKey"
  "Content-Type" = "application/json"
}

try {
  $existing = Invoke-RestMethod -Method GET -Uri "https://console.vast.ai/api/v0/ssh/" -Headers $headers
} catch {
  throw "Failed to list SSH keys from Vast.ai. Check VAST_API_KEY and network."
}

$alreadyExists = $false
if ($existing) {
  foreach ($k in $existing) {
    if ($k.key -eq $pubKey -or $k.public_key -eq $pubKey) {
      $alreadyExists = $true
      break
    }
  }
}

if (-not $alreadyExists) {
  $body = @{ ssh_key = $pubKey } | ConvertTo-Json
  try {
    $resp = Invoke-RestMethod -Method POST -Uri "https://console.vast.ai/api/v0/ssh/" -Headers $headers -Body $body
    if (-not $resp.success) {
      throw "Vast.ai returned success=false when creating SSH key."
    }
    Write-Host "SSH key registered in Vast.ai."
  } catch {
    throw "Failed to create SSH key in Vast.ai. Check VAST_API_KEY and permissions."
  }
} else {
  Write-Host "SSH key already present in Vast.ai."
}

Write-Host ""
Write-Host "Public key (add to Vast.ai):"
Write-Host "----------------------------------------"
Get-Content $pubKeyPath
Write-Host "----------------------------------------"
Write-Host ""
Write-Host "Next steps:"
Write-Host "1) Public key is now registered via API (no manual step needed)"
Write-Host "2) Recreate the VM or refresh /opt/app/secrets/vast_ed25519 on the VM"
