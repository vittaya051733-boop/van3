param(
  [string]$ConfirmDeploy,
  [string]$ConfirmFile,
  [string]$ConfirmImpact,
  [switch]$InteractiveConfirm,
  [string]$FinalAcknowledge,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$importScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\van2\scripts\deploy-governance-import.ps1'))
$canonicalScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\van2\scripts\deploy-firestore-isolated.ps1'))
. $importScript -CallingScriptRoot $PSScriptRoot

$cfg = Get-VanGovernanceConfig

Assert-VanDeployConfirmation -App 'van3' -ConfirmDeploy $ConfirmDeploy
Assert-VanFileConfirmation -ConfirmFile $ConfirmFile -ExpectedFile $cfg.FirestoreCanonicalFile
Assert-VanImpactConfirmation -ConfirmImpact $ConfirmImpact -ExpectedImpact $cfg.FirestoreSharedImpact
Assert-VanFinalAcknowledge -FinalAcknowledge $FinalAcknowledge
Assert-VanAppCanDeploy -App 'van3' -Target 'firestore'
Assert-VanFirestoreRulesSynced -App 'van3'

Write-Host 'van3 delegates shared Firestore deploy to van2 canonical script.' -ForegroundColor Cyan
& $canonicalScript `
  -ConfirmDeploy (Get-VanDeployConfirmToken -App 'van2') `
  -ConfirmFile $cfg.FirestoreCanonicalFile `
  -ConfirmImpact $cfg.FirestoreSharedImpact `
  -FinalAcknowledge $FinalAcknowledge `
  -DryRun:$DryRun
