$ErrorActionPreference = 'Stop'
$importScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\van2\scripts\deploy-governance-import.ps1'))
. $importScript -CallingScriptRoot $PSScriptRoot

$cfg = Get-VanGovernanceConfig
throw @"
BLOCKED: van3 has no Cloud Functions codebase.
Deploy functions only from the owning app:
  van1: $($cfg.Apps.van1.Root)\scripts\deploy-functions-isolated.ps1
  van2: $($cfg.Apps.van2.Root)\scripts\deploy-functions-isolated.ps1
See: van2\scripts\DEPLOY_GOVERNANCE.md
"@
