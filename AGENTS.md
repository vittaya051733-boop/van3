# van3 Rider — Agent Instructions

## Before ANY Firebase deploy

1. Read `..\van2\scripts\DEPLOY_GOVERNANCE.md`
2. Read `..\van2\scripts\DEPLOY_RISK_MATRIX.md`
3. Run `..\van2\scripts\deploy-readiness.ps1 -App van3 -Target <target>`
4. Deploy ONE target: `..\van2\scripts\deploy-self.ps1 -App van3 -Target <target> ...`

## Never deploy from van3

- Firestore default DB (SHARED — breaks all rider listeners)
- Cloud Functions (no codebase)

## Allowed targets

`storage`, `hosting` only (SELF)

## Why this app is sensitive

Listeners on `orders` and `riders/{uid}` drop on permission-denied if SHARED rules deploy incorrectly.
