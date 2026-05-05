param(
  [switch]$BuildWeb,
  [switch]$DeployHosting
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Split-Path -Parent $scriptRoot
Set-Location $appRoot

$expectedProjectId = 'van-merchant'
$hostingTarget = 'van3'
$firestoreScript = Join-Path $scriptRoot 'deploy-firestore-isolated.ps1'
$storageScript = Join-Path $scriptRoot 'deploy-storage-isolated.ps1'

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Error 'Firebase CLI was not found in PATH.'
  exit 1
}

if (-not (Test-Path '.firebaserc') -or -not (Test-Path 'firebase.json')) {
  Write-Error 'Missing .firebaserc or firebase.json.'
  exit 1
}

$rc = Get-Content '.firebaserc' -Raw | ConvertFrom-Json
$projectId = $rc.projects.default
if ($projectId -ne $expectedProjectId) {
  Write-Error "Configured project '$projectId' does not match expected '$expectedProjectId'."
  exit 1
}

if (-not (Test-Path $storageScript)) {
  Write-Error "Missing deploy script: $storageScript"
  exit 1
}

Write-Host 'Skipping Firestore deploy for van3 because the project still uses a shared default database.' -ForegroundColor DarkYellow
Write-Host 'Deploying isolated Storage rules next...' -ForegroundColor DarkCyan
& powershell -ExecutionPolicy Bypass -File $storageScript

if (-not $DeployHosting) {
  Write-Host 'Routine isolated deploy skips hosting. Use -DeployHosting when you need to publish van3 web hosting explicitly.' -ForegroundColor DarkYellow
  return
}

$hostingMap = $rc.targets.$expectedProjectId.hosting.$hostingTarget
if (-not $hostingMap -or $hostingMap.Count -eq 0) {
  Write-Error "Hosting target '$hostingTarget' is not mapped. Run: firebase target:apply hosting $hostingTarget <SITE_ID> --project $expectedProjectId"
  exit 1
}

if ($BuildWeb) {
  flutter build web
}

Write-Host "Deploying isolated target: hosting:$hostingTarget" -ForegroundColor Cyan
firebase deploy --project $expectedProjectId --only "hosting:$hostingTarget"
