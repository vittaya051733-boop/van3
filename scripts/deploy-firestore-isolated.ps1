$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$expectedProjectId = 'van-merchant'
$rulesFile = 'firestore.rules'
$canonicalRulesPath = 'C:\Users\TAM\Desktop\van2\firestore.rules'

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error 'Firebase CLI was not found in PATH.'
  exit 1
}

if (-not (Test-Path '.firebaserc')) {
  Write-Error 'Missing .firebaserc.'
  exit 1
}

if (-not (Test-Path $rulesFile)) {
  Write-Error "Missing rules file: $rulesFile"
  exit 1
}

$rc = Get-Content '.firebaserc' -Raw | ConvertFrom-Json
$projectId = $rc.projects.default
if ($projectId -ne $expectedProjectId) {
  Write-Error "Configured project '$projectId' does not match expected '$expectedProjectId'."
  exit 1
}

# Guard: van1/van2/van3 share the default Firestore database.
# Deploying from van3 must not overwrite the canonical (van2) ruleset.
# We require van3's rules to match the canonical superset before allowing deploy.
if (-not (Test-Path $canonicalRulesPath)) {
  Write-Error "Canonical rules file not found at: $canonicalRulesPath"
  exit 1
}

$localHash = (Get-FileHash $rulesFile -Algorithm SHA256).Hash
$canonicalHash = (Get-FileHash $canonicalRulesPath -Algorithm SHA256).Hash

if ($localHash -ne $canonicalHash) {
  Write-Host "[guard] van3 rules differ from canonical (van2) ruleset." -ForegroundColor Yellow
  Write-Host "[guard] Local : $localHash" -ForegroundColor Yellow
  Write-Host "[guard] Canon : $canonicalHash" -ForegroundColor Yellow
  Write-Host "[guard] To prevent overwriting rules used by van1/van2, refusing to deploy." -ForegroundColor Yellow
  Write-Host "[guard] If you intentionally changed rules, also update $canonicalRulesPath" -ForegroundColor Yellow
  Write-Host "[guard] then re-run this script." -ForegroundColor Yellow
  exit 1
}

Write-Host "[guard] van3 rules match canonical superset. Proceeding to deploy." -ForegroundColor Green
firebase deploy --only firestore:rules --project $expectedProjectId
