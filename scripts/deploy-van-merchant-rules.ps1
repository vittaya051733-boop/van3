param([switch]$FirestoreOnly, [switch]$StorageOnly)

$ErrorActionPreference = 'Stop'
Write-Error 'BLOCKED: Use van2\scripts\deploy-safe.ps1 or deploy-*-isolated.ps1. See van2\scripts\DEPLOY_GOVERNANCE.md'
exit 1
