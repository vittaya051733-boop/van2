# SMTP And Domain Setup

โปรเจกต์นี้รองรับ 2 ส่วนแยกกัน แต่ใช้โดเมนเดียวกันได้:

1. Email OTP ส่งผ่าน Firebase Cloud Functions + SMTP
2. หน้าเว็บ deploy ผ่าน Firebase Hosting ของโปรเจกต์ `van-merchant`

## สถานะปัจจุบัน

- Firebase project: `van-merchant`
- Hosting site ปัจจุบัน: `https://van-merchant.web.app`
- Email OTP เรียกฟังก์ชัน `sendEmailOtp` และ `verifyEmailOtp`
- ฟังก์ชัน Email OTP ต้องใช้ secrets เหล่านี้:
  - `SMTP_HOST`
  - `SMTP_PORT`
  - `SMTP_USER`
  - `SMTP_PASS`
  - `SMTP_FROM`

## ทางที่ 1: ใช้อีเมลโดเมนจริงกับ OTP

ตัวอย่างผู้ให้บริการที่ใช้ได้:

- Hostinger email
- cPanel mail hosting
- Zoho Mail
- Google Workspace

ค่าที่ต้องเตรียม:

- SMTP host เช่น `smtp.hostinger.com`
- SMTP port เช่น `465` หรือ `587`
- อีเมลผู้ส่ง เช่น `no-reply@yourdomain.com`
- รหัสผ่านของกล่องเมล หรือ app password
- ชื่อผู้ส่ง เช่น `Van Market <no-reply@yourdomain.com>`

ตั้ง secrets แบบ interactive:

```powershell
Set-Location 'c:\Users\TAM\Desktop\van2\van2'
.\scripts\set-firebase-smtp-secrets.ps1
```

หรือถ้าต้องการตั้งทีละตัว:

```powershell
firebase functions:secrets:set SMTP_HOST --project van-merchant
firebase functions:secrets:set SMTP_PORT --project van-merchant
firebase functions:secrets:set SMTP_USER --project van-merchant
firebase functions:secrets:set SMTP_PASS --project van-merchant
firebase functions:secrets:set SMTP_FROM --project van-merchant
firebase deploy --only functions:sendEmailOtp,functions:verifyEmailOtp --project van-merchant
```

ตรวจหลัง deploy:

```powershell
firebase functions:list --project van-merchant
```

ควรเห็นอย่างน้อย:

- `sendEmailOtp`
- `verifyEmailOtp`

## ทางที่ 2: ใช้โดเมนเดียวกันกับเว็บ Van Market

แนวทางที่แนะนำ:

- ใช้ `www.yourdomain.com` หรือ `app.yourdomain.com` สำหรับเว็บ
- ใช้ `no-reply@yourdomain.com` สำหรับ OTP

โดเมนเดียวกันใช้ร่วมกันได้ เพราะ DNS คนละชนิด:

- เว็บใช้ `A`, `AAAA`, `CNAME`, หรือ record ที่ Firebase ระบุ
- อีเมลใช้ `MX`, `SPF`, `DKIM`, `DMARC`

Deploy เว็บขึ้น Hosting ก่อน:

```powershell
Set-Location 'c:\Users\TAM\Desktop\van2\van2'
.\scripts\deploy-web-hosting.ps1
```

จากนั้นผูก custom domain ใน Firebase Console:

1. เปิด Firebase Console ของ project `van-merchant`
2. เข้า Hosting
3. เลือก site `van-merchant`
4. กด `Add custom domain`
5. ใส่โดเมนที่ต้องการ เช่น `www.yourdomain.com`
6. เพิ่ม DNS records ตามที่ Firebase แสดง
7. รอ SSL provisioning และสถานะ `Connected`

## DNS สำหรับอีเมลโดเมน

นอกจาก Firebase Hosting ต้องตั้ง record ฝั่งเมลด้วย:

- `MX` ตามผู้ให้บริการอีเมล
- `TXT` สำหรับ SPF
- `TXT` หรือ `CNAME` สำหรับ DKIM
- `TXT` สำหรับ DMARC

ตัวอย่างแนวคิด:

- `www.yourdomain.com` -> Firebase Hosting
- `yourdomain.com` -> redirect ไป `www` หรือชี้เข้า Hosting ตามที่ Firebase รองรับ
- `MX` ของ `yourdomain.com` -> ผู้ให้บริการเมล
- `no-reply@yourdomain.com` -> กล่องที่ใช้ส่ง OTP

## สิ่งที่มักทำให้ OTP ไม่เข้า

- ยังไม่ได้ตั้ง `SMTP_*` secrets
- deploy functions แล้ว แต่ยังไม่มี `sendEmailOtp` หรือ `verifyEmailOtp`
- กล่องผู้ส่งยังไม่ได้เปิด SMTP
- ผู้ให้บริการบังคับใช้ app password แต่ยังใช้รหัสผ่านธรรมดา
- ยังไม่ได้ตั้ง SPF หรือ DKIM ทำให้เมลเข้าถังขยะหรือถูก reject

## ไฟล์อ้างอิง

- `functions/index.js`
- `lib/auth_verification_screen.dart`
- `firebase.json`