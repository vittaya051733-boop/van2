# Pricing Config Setup

เอกสารนี้กำหนดจุดปรับอัตราบวกเพิ่มราคาแบบศูนย์กลางผ่าน Firestore

## Firestore Path

- Collection: `pricing_config`
- Document: `global`

## Fields

- `taxableMarkupRate` (number) ตัวอย่าง `0.07`
- `nonTaxableMarkupRate` (number) ตัวอย่าง `0.07`
- `toppingMarkupRate` (number) ตัวอย่าง `0.07`
- `note` (string) ไม่บังคับ
- `updatedAt` (timestamp) ไม่บังคับ

## 7% Fuse (Fallback)

หากเอกสารหาย, ฟิลด์ไม่ถูกต้อง หรืออ่านไม่ได้ ระบบจะ fallback เป็น 7% อัตโนมัติ

- taxableMarkupRate = 0.07
- nonTaxableMarkupRate = 0.07
- toppingMarkupRate = 0.07

## วิธีปรับในอนาคต

1. เปิด Firestore
2. ไปที่ `pricing_config/global`
3. ปรับค่าเช่น `0.08` = 8%
4. บันทึก

## การใช้งานในระบบ

- Cloud Function `calculateCartTotals` อ่าน config นี้โดยตรง (มี cache)
- Flutter app อ่าน config เดียวกันตอนเริ่มแอป และ sync แบบ realtime
- ไม่ต้อง deploy ใหม่เมื่อเปลี่ยนเฉพาะค่า rate
