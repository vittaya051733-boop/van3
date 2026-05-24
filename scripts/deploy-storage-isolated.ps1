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
. $importScript -CallingScriptRoot $PSScriptRoot
Invoke-VanStorageRulesDeploy -App 'van3' -ConfirmDeploy $ConfirmDeploy -ConfirmFile $ConfirmFile -ConfirmImpact $ConfirmImpact -FinalAcknowledge $FinalAcknowledge -InteractiveConfirm:$InteractiveConfirm -DryRun:$DryRun
