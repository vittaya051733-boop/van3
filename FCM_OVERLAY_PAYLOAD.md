# FCM Payload มาตรฐานสำหรับ Overlay (van3)

เอกสารนี้กำหนด payload สำหรับแจ้งงานไรเดอร์ให้ครอบคลุม 3 สถานะของแอป:
- Foreground: `FirebaseMessaging.onMessage`
- Background: `FirebaseMessaging.onBackgroundMessage`
- Terminated: `FirebaseMessaging.getInitialMessage`

## หลักการสำคัญ

1. ต้องมี `data` payload เสมอ เพื่อให้ฝั่ง Dart อ่าน `title/body` ได้ทุกสถานะ
2. Android ควรใช้ `priority: high` เพื่อเพิ่มโอกาสปลุกแอปในฉากหลัง
3. ใส่ทั้ง `notification` และ `data` ได้ แต่ให้ถือ `data` เป็น source หลักของระบบธุรกิจ
4. แนะนำกำหนด `type`, `jobId`, `click_action`, `deep_link` ให้ครบเพื่อรองรับการนำทาง

## โครงสร้างที่แนะนำ (FCM HTTP v1)

```json
{
  "message": {
    "token": "<RIDER_FCM_TOKEN>",
    "notification": {
      "title": "มีงานใหม่",
      "body": "มีคำขอเรียกรถใหม่ กรุณาตรวจสอบทันที"
    },
    "data": {
      "type": "ride_request",
      "jobId": "job_20260420_0001",
      "title": "มีงานใหม่",
      "body": "มีคำขอเรียกรถใหม่ กรุณาตรวจสอบทันที",
      "click_action": "FLUTTER_NOTIFICATION_CLICK",
      "deep_link": "van3://jobs/job_20260420_0001",
      "pickupLat": "13.7563",
      "pickupLng": "100.5018",
      "dropoffLat": "13.7367",
      "dropoffLng": "100.5231"
    },
    "android": {
      "priority": "high",
      "notification": {
        "channel_id": "rider_jobs",
        "sound": "default"
      }
    }
  }
}
```

## ตัวอย่างแบบเจาะตามสถานะ

### 1) Foreground (แอปเปิดอยู่)

โค้ดในแอปจะเข้า `onMessage` แล้วเรียก Overlay ทันที

```json
{
  "message": {
    "token": "<RIDER_FCM_TOKEN>",
    "data": {
      "type": "ride_request",
      "jobId": "fg_001",
      "title": "งานด่วน",
      "body": "ลูกค้าเรียกจาก สยาม -> อโศก"
    },
    "android": {
      "priority": "high"
    }
  }
}
```

### 2) Background (แอปพับอยู่)

ต้องมี data และ high priority เพื่อให้ `onBackgroundMessage` ทำงานได้ดีขึ้น

```json
{
  "message": {
    "token": "<RIDER_FCM_TOKEN>",
    "notification": {
      "title": "งานใหม่ (Background)",
      "body": "แตะเพื่อดูรายละเอียด"
    },
    "data": {
      "type": "ride_request",
      "jobId": "bg_001",
      "title": "งานใหม่",
      "body": "มีงานใหม่ระหว่างที่แอปพับอยู่"
    },
    "android": {
      "priority": "high"
    }
  }
}
```

### 3) Terminated (ปิดแอป)

เมื่อผู้ใช้แตะแจ้งเตือนเปิดแอป จะเข้า `getInitialMessage`

```json
{
  "message": {
    "token": "<RIDER_FCM_TOKEN>",
    "notification": {
      "title": "งานใหม่ (Terminated)",
      "body": "แตะเพื่อเปิดแอป"
    },
    "data": {
      "type": "ride_request",
      "jobId": "tm_001",
      "title": "งานใหม่",
      "body": "เปิดจากสถานะปิดแอป"
    },
    "android": {
      "priority": "high"
    }
  }
}
```

## ตัวอย่างส่งด้วย curl (FCM HTTP v1)

```bash
curl -X POST "https://fcm.googleapis.com/v1/projects/<PROJECT_ID>/messages:send" \
  -H "Authorization: Bearer <OAUTH2_ACCESS_TOKEN>" \
  -H "Content-Type: application/json; charset=UTF-8" \
  -d @payload.json
```

## เช็กลิสต์ทดสอบจริง

1. ติดตั้งแอปบนอุปกรณ์และล็อกอินไรเดอร์
2. ขอสิทธิ์แจ้งเตือนและ Overlay ให้ผ่านทั้งหมด
3. ส่ง payload แบบ Foreground แล้วตรวจว่า overlay เด้งทันที
4. กด Home ให้แอปเป็น Background แล้วส่ง payload แบบ Background
5. ปัดปิดแอป (force stop หลีกเลี่ยงถ้าเป็นไปได้) แล้วส่ง payload แบบ Terminated และแตะแจ้งเตือนเปิดแอป
6. ยืนยันว่าเห็นเนื้อหาตรงจาก `data.title` และ `data.body`

## หมายเหตุ

- หากใช้ Android 13+ ต้องอนุญาต Notification (`POST_NOTIFICATIONS`)
- Overlay ต้องอนุญาต `SYSTEM_ALERT_WINDOW`
- บางผู้ผลิตมือถือมีระบบประหยัดพลังงานที่กระทบ background delivery
