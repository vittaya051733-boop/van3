param(
  [switch]$BuildWeb,
  [switch]$DeployHosting,
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$importScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\van2\scripts\deploy-governance-import.ps1'))
. $importScript -CallingScriptRoot $PSScriptRoot

$cfg = Get-VanGovernanceConfig
$appCfg = $cfg.Apps['van3']
$storageScript = Join-Path $PSScriptRoot 'deploy-storage-isolated.ps1'

$expectedFile = 'storage.rules'
if ($DeployHosting) {
  $expectedFile = 'storage.rules,firebase.json'
}

Invoke-VanDeployGuardSession `
  -App 'van3' `
  -ConfirmDeploy $ConfirmDeploy `
  -ConfirmFile $ConfirmFile `
  -ExpectedFile $expectedFile `
  -ConfirmImpact $ConfirmImpact `
  -ExpectedImpact 'SELF:van3' `
  -FinalAcknowledge $FinalAcknowledge `
  -InteractiveConfirm:$InteractiveConfirm

Write-Host 'Skipping shared Firestore (default DB). Use van2/scripts/deploy-firestore-isolated.ps1 for canonical rules.' -ForegroundColor DarkYellow
Write-Host 'Deploying isolated Storage rules (SELF:van3)...' -ForegroundColor DarkCyan
& $storageScript -ConfirmDeploy $ConfirmDeploy -ConfirmFile 'storage.rules' -ConfirmImpact 'SELF:van3' -FinalAcknowledge $FinalAcknowledge -DryRun:$DryRun

if (-not $DeployHosting) {
  Write-Host 'Routine deploy skips hosting. Use -DeployHosting to publish van3 web hosting.' -ForegroundColor DarkYellow
  return
}

Assert-VanAppCanDeploy -App 'van3' -Target 'hosting'
Set-Location $appCfg.Root
$rc = Get-Content (Join-Path $appCfg.Root '.firebaserc') -Raw | ConvertFrom-Json
$hostingTarget = $appCfg.HostingTarget
$hostingMap = $rc.targets.$($cfg.ProjectId).hosting.$hostingTarget
if (-not $hostingMap -or $hostingMap.Count -eq 0) {
  throw "Hosting target '$hostingTarget' is not mapped."
}

if ($BuildWeb) {
  flutter build web
}

Write-Host "Deploying hosting:$hostingTarget (SELF:van3)" -ForegroundColor Cyan
if ($DryRun) {
  Write-Host '[dry-run] Skipping firebase deploy for hosting.' -ForegroundColor Yellow
  return
}
firebase deploy --project $cfg.ProjectId --only "hosting:$hostingTarget"
