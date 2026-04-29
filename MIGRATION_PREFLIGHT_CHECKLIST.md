# Migration Pre-Flight Checklist (van2 + van3)

Checklist นี้ใช้ก่อนรัน migration จริง เพื่อให้ย้ายข้อมูลแบบปลอดภัยและตรวจสอบครบ 100%

## 1) เตรียมสิทธิ์และเครื่องมือ

1. ยืนยันว่าใช้ service account ที่มีสิทธิ์อ่าน/เขียน Firestore
2. ตั้งค่า `GOOGLE_APPLICATION_CREDENTIALS` ให้ชี้ไปยังไฟล์ JSON ของ service account
3. ติดตั้ง dependency ที่จำเป็น

```bash
# van3
cd van3
npm i firebase-admin

# van2/functions
cd ../van2/functions
npm i firebase-admin
```

## 2) Backup ก่อนย้าย (สำคัญ)

1. Export ทั้งโปรเจกต์ด้วย gcloud (แนะนำที่สุด)

```bash
gcloud firestore export gs://<YOUR_BUCKET>/pre-migration-$(date +%Y%m%d-%H%M%S)
```

2. ถ้าใช้ Windows PowerShell ให้กำหนด timestamp เอง เช่น `20260420-1700`

```powershell
gcloud firestore export gs://<YOUR_BUCKET>/pre-migration-20260420-1700
```

3. เก็บหลักฐาน backup path ไว้ใน ticket/เอกสารทีม

## 3) Dry-run ก่อนทุกครั้ง

1. van3: users -> riders

```bash
cd van3
node scripts/migrate-users-to-riders.js
```

2. van2: users -> customer_users

```bash
cd ../van2/functions
node migrate-users-to-customer-users.js --dry-run
```

## 4) Sample Verify ก่อนลบต้นทาง

1. เลือก sample UID จริง 3-10 ราย
2. Verify ว่าผลตรวจผ่าน (ยังไม่ strict all users)

```bash
# van3
cd van3
node scripts/verify-users-to-riders.js --sample-uids=<uid1>,<uid2>,<uid3>

# van2
cd ../van2/functions
node verify-users-to-customer-users.js --sample-uids=<uid1>,<uid2>,<uid3>
```

## 5) Run จริงแบบลบต้นทาง

1. van3

```bash
cd van3
node scripts/migrate-users-to-riders.js --delete-source
```

2. van2

```bash
cd ../van2/functions
node migrate-users-to-customer-users.js --delete-source
```

## 6) Verify หลัง migrate (เงื่อนไข 100%)

1. ตรวจเงื่อนไขหลัก + sample

```bash
# van3
cd van3
node scripts/verify-users-to-riders.js --sample-size=10

# van2
cd ../van2/functions
node verify-users-to-customer-users.js --sample-size=10
```

2. ถ้าต้องการบังคับว่า users ต้องเหลือ 0 ทั้งคอลเลกชัน ให้เปิด strict

```bash
# van3
cd van3
node scripts/verify-users-to-riders.js --strict-all-users-zero

# van2
cd ../van2/functions
node verify-users-to-customer-users.js --strict-all-users-zero
```

## 7) Post-check ทางแอป

1. ล็อกอิน van3 แล้วตรวจว่าเขียนโปรไฟล์เข้า `riders/{uid}`
2. ล็อกอิน van2 แล้วตรวจว่าเขียนโปรไฟล์เข้า `customer_users/{uid}`
3. ทดสอบ flow แชท/โทร/แจ้งเตือนที่อ่านข้อมูล user profile ว่าทำงานปกติ

## 8) Rollback Plan

1. หาก verify ไม่ผ่าน ให้หยุด deploy ต่อทันที
2. ใช้ backup จาก Firestore export เพื่อกู้ข้อมูล
3. แก้สคริปต์/ข้อมูลผิดพลาด แล้วรันเฉพาะ `--uid=<uid>` เป็นรายรายการก่อนวนทั้งระบบ
