$ErrorActionPreference = 'Stop'

Write-Error 'BLOCKED: van3 has no isolated Cloud Functions codebase in firebase.json. Do not deploy functions from van3; use the owning app/codebase script for the specific function instead.'
exit 1