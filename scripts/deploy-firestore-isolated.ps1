$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot


$expectedProjectId = 'van-merchant'
$rulesFile = 'firestore.rules'

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

Write-Error 'van3 cannot deploy Firestore rules in isolation right now because all apps still share the default Firestore database. Deploying van3 rules would overwrite shared rules used by van1/van2. Split the apps onto named databases first, or deploy the shared ruleset from the canonical app only.'
exit 1
