# เปิด Crashlytics — Van Ecosystem (project: van-merchant)

คู่มือนี้ใช้กับ van1–van4 ที่ติดตั้ง SDK แล้ว (`firebase_crashlytics` + Gradle plugin)

## แอป Android ในระบบ

| แอป | Package / applicationId |
|-----|---------------------------|
| van1 ร้าน | `van.merchant` |
| van2 ลูกค้า | `Van2.com` |
| van3 ไรเดอร์ | `van3.rider.com` |
| van4 แอดมิน | `van4.com` |

Project Firebase: **`van-merchant`**

---

## ขั้นตอนใน Firebase Console (ทำครั้งเดียว)

### 1) เปิด Crashlytics

1. ไปที่ [Firebase Console](https://console.firebase.google.com/)
2. เลือก project **`van-merchant`**
3. เมนูซ้าย: **Build** → **Crashlytics** (หรือ **Run** → **Crashlytics** ตาม UI รุ่นใหม่)
4. ถ้าเห็นปุ่ม **Enable Crashlytics** / **Get started** → กดเปิดใช้งาน
5. เลือกแอป Android แรก (เช่น van2) แล้วทำตาม wizard

> Crashlytics เปิดระดับ **project** — เปิดครั้งเดียว ใช้ได้ทุกแอปใน project เดียวกัน

### 2) ผูก Analytics (แนะนำ)

Crashlytics ทำงานดีที่สุดเมื่อ **Google Analytics for Firebase** เปิดอยู่:

1. **Project settings** (ไอคอนเฟือง) → **Integrations**
2. ตรวจว่า **Google Analytics** = Linked
3. ถ้ายังไม่ link → กด **Link** แล้วเลือก Analytics account

### 3) ตรวจว่ามี Android app ครบ 4 ตัว

1. **Project settings** → แท็บ **Your apps**
2. ตรวจว่ามี Android app ตรง package ด้านบน
3. ถ้าขาด → **Add app** → Android → ใส่ package name → ดาวน์โหลด `google-services.json` ไปวางที่ `android/app/`

ตรวจจากเครื่องคุณ (optional):

```powershell
cd C:\Users\TAM\Desktop\van2
npx -y firebase-tools@latest apps:list ANDROID --project van-merchant
```

### 4) ส่ง crash ทดสอบครั้งแรก (สำคัญ)

Crashlytics จะแสดง dashboard เต็มรูปแบบหลังได้รับ event แรกจาก **release build**

**วิธี A — non-fatal (ปลอดภัย แอปไม่เด้ง):**

```powershell
cd C:\Users\TAM\Desktop\van2
flutter run --release --dart-define=PILOT_OBSERVABILITY_VERIFY=true
```

**วิธี B — fatal crash ทดสอบ (แอปจะเด้ง ใช้ครั้งเดียว):**

```powershell
flutter run --release `
  --dart-define=PILOT_OBSERVABILITY_VERIFY=true `
  --dart-define=CRASHLYTICS_PILOT_CRASH=true
```

หลัง crash (วิธี B): เปิดแอปอีกครั้งเพื่อให้ SDK อัปโหลดรายงาน

### 5) ดูผลใน Console

1. รอ **2–10 นาที**
2. **Crashlytics** → เลือกแอป (filter ตาม package)
3. ควรเห็น:
   - Event `app_start` ใน **Analytics** → DebugView / Events (ถ้าเปิด debug device)
   - Non-fatal `van_pilot_nonfatal_van2_customer` ใน Crashlytics
   - Fatal `Test Crash` ถ้าใช้วิธี B

ลิงก์ตรง (แทน PROJECT_NUMBER ด้วยเลขจริงจาก Console):

- Crashlytics: `https://console.firebase.google.com/project/van-merchant/crashlytics`
- Analytics: `https://console.firebase.google.com/project/van-merchant/analytics`

### 6) ทำซ้ำ van1 / van3 / van4

รัน release + verify แต่ละแอป:

```powershell
cd C:\Users\TAM\Desktop\van1\my-flutter
flutter run --release --dart-define=PILOT_OBSERVABILITY_VERIFY=true

cd C:\Users\TAM\Desktop\van3
flutter run --release --dart-define=PILOT_OBSERVABILITY_VERIFY=true

cd C:\Users\TAM\Desktop\van4
flutter run --release --dart-define=PILOT_OBSERVABILITY_VERIFY=true
```

ใน Crashlytics แต่ละแอปจะมี custom key `van_app` = `van1_merchant`, `van2_customer`, `van3_rider`, `van4_admin`

---

## Troubleshooting

| อาการ | แก้ |
|--------|-----|
| ไม่เห็น crash ใน Console | ใช้ `--release` ไม่ใช่ debug; เปิดแอบอีกครั้งหลัง crash |
| Crashlytics ว่างเปล่า | กด Enable ใน Console; รอ 10 นาที |
| Debug build ไม่ส่ง | ถูกต้อง — SDK ตั้ง `setCrashlyticsCollectionEnabled(kReleaseMode)` |
| ไม่มี google-services.json | ดาวน์โหลดจาก Project settings → Your apps |
| Gradle build fail | ตรวจ `id("com.google.firebase.crashlytics")` ใน `android/app/build.gradle.kts` |

---

## สคริปต์ช่วยอัตโนมัติ

```powershell
# ตรวจความพร้อม + smoke test + แสดงขั้นตอน Console
C:\Users\TAM\Desktop\van2\scripts\soft-launch-pilot-test.ps1

# รวมส่งสัญญาณ Crashlytics บน van2 (ต้องมี device/emulator)
C:\Users\TAM\Desktop\van2\scripts\soft-launch-pilot-test.ps1 -SendObservabilityPing -App van2
```
