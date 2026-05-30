param(
  [switch]$IncludeApp,
  [switch]$ForceLegacy
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host 'BLOCKED: deploy-auto.ps1 — van3 must not deploy Firestore (SHARED).' -ForegroundColor Red
Write-Host ''
Write-Host 'Use: ..\van2\scripts\deploy-self.ps1 -App van3 -Target storage ...' -ForegroundColor Yellow
Write-Host 'Read: ..\van2\scripts\DEPLOY_GOVERNANCE.md + DEPLOY_RISK_MATRIX.md' -ForegroundColor Cyan
Write-Host ''

if (-not $ForceLegacy) { exit 1 }

Write-Warning 'ForceLegacy — deprecated combined deploy.'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
powershell -ExecutionPolicy Bypass -File 'scripts/deploy-storage-isolated.ps1'
if ($IncludeApp) { powershell -ExecutionPolicy Bypass -File 'scripts/deploy-isolated.ps1' }
