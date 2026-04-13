const crypto = require('crypto');

const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const nodemailer = require('nodemailer');
const { defineSecret } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

admin.initializeApp();

const db = admin.firestore();
const DEFAULT_REGION = 'asia-southeast1';
const OTP_TTL_MS = 10 * 60 * 1000;
const OTP_RESEND_INTERVAL_MS = 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;

const SMTP_HOST = defineSecret('SMTP_HOST');
const SMTP_PORT = defineSecret('SMTP_PORT');
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_FROM = defineSecret('SMTP_FROM');

function readRequiredSecret(secret, label) {
  const value = String(secret.value() || '').trim();
  if (!value) {
    throw new HttpsError(
      'failed-precondition',
      `ยังไม่ได้ตั้งค่า ${label} สำหรับระบบ Email OTP`,
    );
  }
  return value;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function normalizeMode(mode) {
  return String(mode || 'sign_in').trim().toLowerCase();
}

function normalizePhoneNumber(raw = '') {
  let clean = String(raw).trim().replace(/[^0-9+]/g, '');
  if (!clean) return '';
  if (clean.startsWith('00')) {
    clean = `+${clean.substring(2)}`;
  }
  if (clean.startsWith('0') && clean.length === 10) {
    return `+66${clean.substring(1)}`;
  }
  if (!clean.startsWith('+') && clean.length >= 9) {
    return `+${clean}`;
  }
  return clean;
}

function otpDocId(email) {
  return Buffer.from(normalizeEmail(email)).toString('base64url');
}

function generateOtp() {
  return `${crypto.randomInt(0, 1000000)}`.padStart(6, '0');
}

function normalizeOtp(otp) {
  const digitMap = {
    '๐': '0',
    '๑': '1',
    '๒': '2',
    '๓': '3',
    '๔': '4',
    '๕': '5',
    '๖': '6',
    '๗': '7',
    '๘': '8',
    '๙': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  return String(otp || '')
    .trim()
    .split('')
    .map((char) => digitMap[char] || char)
    .join('')
    .replace(/\D/g, '');
}

function hashOtp(email, otp) {
  return crypto
    .createHash('sha256')
    .update(`${normalizeEmail(email)}:${otp}`)
    .digest('hex');
}

function hashPhonePassword(phoneNumber, password) {
  return crypto
    .createHash('sha256')
    .update(`${normalizePhoneNumber(phoneNumber)}:${String(password || '')}`)
    .digest('hex');
}

function buildTransport() {
  const host = readRequiredSecret(SMTP_HOST, 'SMTP_HOST');
  const port = Number(readRequiredSecret(SMTP_PORT, 'SMTP_PORT'));
  const user = readRequiredSecret(SMTP_USER, 'SMTP_USER');
  const pass = readRequiredSecret(SMTP_PASS, 'SMTP_PASS');

  if (Number.isNaN(port)) {
    throw new HttpsError(
      'failed-precondition',
      'ค่า SMTP_PORT ไม่ถูกต้องสำหรับระบบ Email OTP',
    );
  }

  return nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: {
      user,
      pass,
    },
  });
}

exports.sendEmailOtp = onCall(
  {
    region: DEFAULT_REGION,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM],
  },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    if (!email || !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
    }

    const docRef = db.collection('email_otps').doc(otpDocId(email));
    const existingDoc = await docRef.get();
    const now = Date.now();
    if (existingDoc.exists) {
      const data = existingDoc.data() || {};
      const lastSentAt = data.lastSentAt?.toMillis?.() || 0;
      if (now - lastSentAt < OTP_RESEND_INTERVAL_MS) {
        throw new HttpsError('resource-exhausted', 'กรุณารอก่อนขอรหัสใหม่');
      }
    }

    const otp = generateOtp();
    await docRef.set(
      {
        email,
        otpHash: hashOtp(email, otp),
        attempts: 0,
        lastSentAt: admin.firestore.Timestamp.fromMillis(now),
        expiresAt: admin.firestore.Timestamp.fromMillis(now + OTP_TTL_MS),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    try {
      const transport = buildTransport();
      const from = readRequiredSecret(SMTP_FROM, 'SMTP_FROM');
      await transport.sendMail({
        from,
        to: email,
        subject: 'รหัส OTP สำหรับเข้าสู่ระบบ Van Market',
        text: `รหัส OTP ของคุณคือ ${otp} รหัสนี้จะหมดอายุใน 10 นาที`,
        html: `
          <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #1f2937;">
            <h2 style="color: #ea580c;">ยืนยันการเข้าสู่ระบบ</h2>
            <p>รหัส OTP สำหรับเข้าสู่ระบบ Van Market ของคุณคือ</p>
            <div style="font-size: 32px; font-weight: 700; letter-spacing: 8px; color: #9a3412; margin: 16px 0;">${otp}</div>
            <p>รหัสนี้จะหมดอายุใน 10 นาที</p>
          </div>
        `,
      });
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error('sendEmailOtp failed', {
        email,
        message: error instanceof Error ? error.message : String(error),
      });

      throw new HttpsError(
        'unavailable',
        'ระบบ Email OTP ยังส่งอีเมลไม่ได้ กรุณาตรวจสอบ SMTP และ deploy functions ใหม่',
      );
    }

    return { success: true, expiresInSeconds: OTP_TTL_MS / 1000 };
  },
);

exports.verifyEmailOtp = onCall(
  {
    region: DEFAULT_REGION,
  },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    const otp = normalizeOtp(request.data?.otp);
    const mode = normalizeMode(request.data?.mode);
    const password = String(request.data?.password || '').trim();

    if (!email || !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
    }

    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError('invalid-argument', 'OTP ต้องเป็นตัวเลข 6 หลัก');
    }

    if (
      mode !== 'sign_in' &&
      mode !== 'reset_password' &&
      mode !== 'reset_password_check'
    ) {
      throw new HttpsError('invalid-argument', 'โหมดการยืนยัน OTP ไม่ถูกต้อง');
    }

    if (mode === 'reset_password' && password.length < 6) {
      throw new HttpsError(
        'invalid-argument',
        'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร',
      );
    }

    const docRef = db.collection('email_otps').doc(otpDocId(email));
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'ไม่พบรหัส OTP สำหรับอีเมลนี้');
    }

    const data = snapshot.data() || {};
    const expiresAt = data.expiresAt?.toMillis?.() || 0;
    const attempts = Number(data.attempts || 0);

    if (Date.now() > expiresAt) {
      await docRef.delete();
      throw new HttpsError('deadline-exceeded', 'OTP หมดอายุแล้ว');
    }

    if (attempts >= MAX_VERIFY_ATTEMPTS) {
      await docRef.delete();
      throw new HttpsError('permission-denied', 'กรอกรหัสผิดเกินจำนวนที่กำหนด');
    }

    if (data.otpHash !== hashOtp(email, otp)) {
      await docRef.set(
        {
          attempts: attempts + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw new HttpsError('permission-denied', 'รหัส OTP ไม่ถูกต้อง');
    }

    if (mode !== 'reset_password_check') {
      await docRef.delete();
    }

    try {
      const user = await admin.auth().getUserByEmail(email);
      const updatePayload =
        mode === 'reset_password'
          ? { emailVerified: true, password }
          : user.emailVerified
            ? null
            : { emailVerified: true };

      if (updatePayload) {
        await admin.auth().updateUser(user.uid, updatePayload);
      }

      if (mode === 'reset_password_check') {
        return { success: true, otpVerified: true };
      }

      if (mode === 'reset_password') {
        const customToken = await admin.auth().createCustomToken(user.uid);
        return { success: true, customToken };
      }
    } catch (error) {
      logger.error('verifyEmailOtp updateUser failed', {
        email,
        mode,
        message: error instanceof Error ? error.message : String(error),
      });
      throw new HttpsError(
        'internal',
        'ยืนยัน OTP สำเร็จ แต่ตั้งค่าสถานะยืนยันอีเมลไม่สำเร็จ',
      );
    }

    return { success: true };
  },
);

exports.upsertPhonePasswordProfile = onCall(
  {
    region: DEFAULT_REGION,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
    }

    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);
    const password = String(request.data?.password || '').trim();
    const authPhone = normalizePhoneNumber(request.auth.token?.phone_number || '');

    if (!phoneNumber || !phoneNumber.startsWith('+')) {
      throw new HttpsError('invalid-argument', 'เบอร์โทรศัพท์ไม่ถูกต้อง');
    }

    if (password.length < 4) {
      throw new HttpsError('invalid-argument', 'รหัสผ่านสั้นเกินไป');
    }

    if (!authPhone || authPhone !== phoneNumber) {
      throw new HttpsError('permission-denied', 'เบอร์โทรไม่ตรงกับบัญชีที่เข้าสู่ระบบ');
    }

    await db.collection('phone_login_profiles').doc(phoneNumber).set(
      {
        uid: request.auth.uid,
        phoneNumber,
        passwordHash: hashPhonePassword(phoneNumber, password),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { success: true };
  },
);

exports.signInWithPhonePassword = onCall(
  {
    region: DEFAULT_REGION,
  },
  async (request) => {
    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);
    const password = String(request.data?.password || '').trim();

    if (!phoneNumber || !phoneNumber.startsWith('+') || !password) {
      throw new HttpsError('invalid-argument', 'ข้อมูลเข้าสู่ระบบไม่ถูกต้อง');
    }

    const doc = await db.collection('phone_login_profiles').doc(phoneNumber).get();
    if (!doc.exists) {
      throw new HttpsError('permission-denied', 'ต้องยืนยัน OTP ครั้งแรกก่อน');
    }

    const data = doc.data() || {};
    if (!data.uid || !data.passwordHash) {
      throw new HttpsError('permission-denied', 'ไม่พบข้อมูลเข้าสู่ระบบ');
    }

    const expectedHash = hashPhonePassword(phoneNumber, password);
    if (expectedHash !== data.passwordHash) {
      throw new HttpsError('permission-denied', 'เบอร์โทรหรือรหัสผ่านไม่ถูกต้อง');
    }

    const customToken = await admin.auth().createCustomToken(String(data.uid));
    return { customToken };
  },
);