# Deploy (van3 Rider)

**อ่านก่อน deploy ทุกครั้ง:**
- `..\van2\scripts\DEPLOY_GOVERNANCE.md`
- `..\van2\scripts\DEPLOY_RISK_MATRIX.md`

van3 deploy ได้แค่ **storage** และ **hosting** (SELF)

```powershell
..\van2\scripts\deploy-readiness.ps1 -App van3 -Target storage
..\van2\scripts\deploy-self.ps1 -App van3 -Target storage `
  -ConfirmDeploy "APPROVE:van3:van-merchant" -FinalAcknowledge "YES I UNDERSTAND"
```

ห้าม deploy Firestore default / Functions จาก van3
