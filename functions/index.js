const crypto = require('crypto');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const { GoogleAuth } = require('google-auth-library');

const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');
const logger = require('firebase-functions/logger');
const nodemailer = require('nodemailer');
const { defineSecret } = require('firebase-functions/params');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const {
  computeVan2CartTotals,
  persistCheckoutQuote,
  createCheckoutOrdersHandler,
  createNationwideParcelOrdersHandler,
} = require('./checkout_orders');
const {
  createTravelOrderHandler,
  quoteTravelFareHandler,
  assertNonAnonymous,
} = require('./travel_orders');
const { fetchGoogleDrivingDirectionsRoute } = require('./google_directions');
const { createRiderAvailabilityHandlers } = require('./rider_availability');
const { createSlipVerificationQueueHandlers } = require('./slip_verification_queue');
const { createOmisePaymentsHandlers } = require('./omise_payments');
const { createOmisePayoutHandlers } = require('./omise_payouts');
const { createManualPayoutHandlers } = require('./manual_payouts');
const {
  createPayoutProfileLoader,
  createPayoutLedger,
} = require('./payout_profile');
const { createSettlementConfigLoader } = require('./settlement_config');
const { createPlatformFloatHandlers } = require('./platform_float');
const { verifyStandaloneSlipCore } = require('./slipok_standalone');
const { readClientIp, assertCallableRateLimit } = require('./callable_rate_limit');
const { createCouponClaimsHandlers } = require('./coupon_claims');
const { createEnsureProductTranslationHandler } = require('./product_translation');
const { createProductSharePreviewExport } = require('./product_share_preview');
const { createProductShareOgImageExport } = require('./product_share_og_image');

admin.initializeApp({
  storageBucket: 'van-merchant-van2-storage-802503541368',
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const couponClaimsHandlers = createCouponClaimsHandlers({
  db,
  FieldValue,
  DEFAULT_REGION: 'asia-southeast1',
  enforceAppCheck: true,
});
const DEFAULT_REGION = 'asia-southeast1';
const CALL_TTL_MS = 30 * 1000;
const VAN3_ORDER_ALERT_TTL_MS = 60 * 1000;
const ACTIVE_CALL_INVITES_COLLECTION = 'active_call_invites';
const OTP_TTL_MS = 10 * 60 * 1000;
const OTP_RESEND_INTERVAL_MS = 60 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;
const RESET_PASSWORD_SESSION_TTL_MS = 15 * 60 * 1000;
const DEFAULT_TAXABLE_MARKUP_RATE = 0.07;
const DEFAULT_NON_TAXABLE_MARKUP_RATE = 0.07;
const DEFAULT_TOPPING_MARKUP_RATE = 0.07;
const DEFAULT_SHIPPING_BASE_FEE = 25;
const DEFAULT_SHIPPING_PER_KM_FEE = 12.5;
const DEFAULT_SHIPPING_MIN_BILLABLE_KM = 1;
const DEFAULT_SHIPPING_MAX_BILLABLE_KM = 50;
const DEFAULT_SHIPPING_MISSING_COORDS_FEE = 25;
const DEFAULT_MARKET_HUB_LATITUDE = 17.279915312140325;
const DEFAULT_MARKET_HUB_LONGITUDE = 102.87070264132565;
const DEFAULT_MARKET_HUB_RADIUS_METERS = 150;
const DEFAULT_MARKET_MULTI_SHOP_MIN_SHOPS = 2;
const DEFAULT_MARKET_COLLECTION_FEE = 5;
const DEFAULT_MARKET_SERVICE_FEE_PER_ORDER = 5;
const PRICING_CONFIG_COLLECTION = 'pricing_config';
const PRICING_CONFIG_DOC_ID = 'global';
const PRICING_CONFIG_CACHE_TTL_MS = 5 * 60 * 1000;
const PAYMENT_CONFIG_COLLECTION = 'payment_config';
const PAYMENT_CONFIG_DOC_ID = 'collection';
const REGISTRATION_COLLECTIONS = [
  'market_registrations',
  'shop_registrations',
  'restaurant_registrations',
  'pharmacy_registrations',
  'other_registrations',
];

const SMTP_HOST = defineSecret('SMTP_HOST');
const SMTP_PORT = defineSecret('SMTP_PORT');
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_FROM = defineSecret('SMTP_FROM');
const AGORA_APP_ID_SECRET = defineSecret('AGORA_APP_ID');
const AGORA_APP_CERT_SECRET = defineSecret('AGORA_APP_CERTIFICATE');
const AGORA_TTL_SECRET = defineSecret('AGORA_APP_TTL_SECONDS');
const SLIPOK_API_KEY_SECRET = defineSecret('SLIPOK_API_KEY');
const GOOGLE_GEOCODING_API_KEY_SECRET = defineSecret('GOOGLE_GEOCODING_API_KEY');

const CUSTOMER_COLLECTIONS = ['customer_users', 'users'];
const RIDER_COLLECTIONS = ['riders'];
const PROFILE_COLLECTIONS = [...CUSTOMER_COLLECTIONS, ...RIDER_COLLECTIONS, ...REGISTRATION_COLLECTIONS];
const SLIPOK_ENDPOINT = 'https://api.slipok.com/api/line/apikey/64492';
const SLIPOK_FEEDBACK_COLLECTION = 'slipok_feedback';
const PRIVACY_CONSENTS_COLLECTION = 'privacy_consents';
const PRIVACY_REQUESTS_COLLECTION = 'privacy_requests';
const PRIVACY_APP_KEYS = new Set([
  'van2_customer',
  'van1_merchant',
  'van3_rider',
]);
const PRIVACY_REQUEST_TYPES = new Set(['export', 'delete', 'correct']);

let pricingConfigCache = {
  expiresAt: 0,
  rates: null,
};

function geocodeCacheId(latitude, longitude) {
  return `${Number(latitude).toFixed(5)}_${Number(longitude).toFixed(5)}`;
}

function readGoogleAddressComponent(components, type) {
  const match = components.find((component) => {
    return Array.isArray(component.types) && component.types.includes(type);
  });
  return String(match?.long_name || '').trim();
}

function parseGoogleReverseGeocodeResult(payload, latitude, longitude) {
  const result = Array.isArray(payload?.results) ? payload.results[0] : null;
  if (!result) {
    return null;
  }

  const components = Array.isArray(result.address_components)
    ? result.address_components
    : [];
  const route = readGoogleAddressComponent(components, 'route');
  const streetNumber = readGoogleAddressComponent(components, 'street_number');
  const premise = readGoogleAddressComponent(components, 'premise');
  const subPremise = readGoogleAddressComponent(components, 'subpremise');
  const addressLine = [subPremise, premise, streetNumber, route]
    .filter(Boolean)
    .join(' ')
    .trim();
  const subDistrict =
    readGoogleAddressComponent(components, 'sublocality_level_2') ||
    readGoogleAddressComponent(components, 'sublocality_level_1') ||
    readGoogleAddressComponent(components, 'locality');
  const district =
    readGoogleAddressComponent(components, 'administrative_area_level_2') ||
    readGoogleAddressComponent(components, 'locality');
  const province = readGoogleAddressComponent(
    components,
    'administrative_area_level_1',
  );
  const postalCode = readGoogleAddressComponent(components, 'postal_code');

  return {
    latitude,
    longitude,
    formattedAddress: String(result.formatted_address || '').trim(),
    addressLine,
    subDistrict,
    district,
    province,
    postalCode,
    placeId: String(result.place_id || '').trim(),
    source: 'google_geocoding',
  };
}

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

function readRequiredConfiguredSecret(secret, label, purpose) {
  const value = String(secret.value() || '').trim();
  if (!value) {
    throw new HttpsError(
      'failed-precondition',
      `ยังไม่ได้ตั้งค่า ${label} สำหรับ${purpose}`,
    );
  }
  return value;
}

function buildSlipVerificationMessage(status, providerPayload, fallbackMessage) {
  const rawCode = Number(providerPayload?.code);
  const providerMessage = String(
    providerPayload?.message || providerPayload?.data?.message || fallbackMessage || '',
  ).trim();

  if (status === 'verified') {
    return 'ตรวจสอบสลิปถูกต้องแล้ว ระบบยืนยันการชำระเงินเรียบร้อย';
  }

  switch (rawCode) {
    case 1012:
      return 'สลิปนี้ถูกใช้ตรวจสอบไปแล้ว กรุณาใช้สลิปที่ยังไม่เคยส่ง';
    case 1013:
      return 'ยอดเงินในสลิปไม่ตรงกับยอดที่ต้องชำระ กรุณาตรวจสอบแล้วแนบสลิปใหม่';
    case 1014:
      return 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน กรุณาตรวจสอบแล้วชำระใหม่';
    default:
      break;
  }

  if (providerMessage.includes('ยอดที่ส่งมาไม่ตรงกับยอดสลิป')) {
    return 'ยอดเงินในสลิปไม่ตรงกับยอดที่ต้องชำระ กรุณาตรวจสอบแล้วแนบสลิปใหม่';
  }
  if (providerMessage.includes('สลิปซ้ำ')) {
    return 'สลิปนี้ถูกใช้ตรวจสอบไปแล้ว กรุณาใช้สลิปที่ยังไม่เคยส่ง';
  }
  if (providerMessage.includes('บัญชีผู้รับไม่ตรงกับบัญชีหลักของร้าน')) {
    return 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน กรุณาตรวจสอบแล้วชำระใหม่';
  }
  if (providerMessage.includes('QR Code ไม่ใช่ QR สำหรับตรวจสอบการชำระเงิน')) {
    return 'สลิปนี้ไม่ใช่สลิปโอนเงินที่ตรวจสอบได้ กรุณาแนบสลิปที่ถูกต้อง';
  }
  if (providerMessage.includes('QR Code หมดอายุ') || providerMessage.includes('ไม่มีรายการอยู่จริง')) {
    return 'สลิปนี้หมดอายุหรือไม่พบรายการ กรุณาแนบสลิปใหม่ที่ถูกต้อง';
  }
  if (providerMessage.includes('รูปภาพไม่มี QR Code')) {
    return 'ระบบอ่าน QR จากสลิปไม่เจอ กรุณาแนบรูปสลิปที่ชัดเจนกว่าเดิม';
  }
  if (providerMessage.includes('รูปภาพไม่ถูกต้อง')) {
    return 'รูปสลิปไม่ถูกต้องหรือไฟล์เสียหาย กรุณาแนบรูปใหม่';
  }
  if (providerMessage.includes('Authorization Header ไม่ถูกต้อง')) {
    return 'ระบบตรวจสลิปมีปัญหาชั่วคราว กรุณาลองใหม่อีกครั้ง';
  }
  if (providerMessage.includes('กรุณาใส่ข้อมูล QR Code ให้ครบ')) {
    return 'ระบบอ่านข้อมูลสลิปไม่ครบ กรุณาแนบสลิปใหม่อีกครั้ง';
  }

  if (status === 'failed') {
    return providerMessage || 'สลิปไม่ผ่านการตรวจสอบ กรุณาตรวจสอบแล้วแนบใหม่';
  }

  return providerMessage || 'ส่งสลิปไปตรวจสอบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}

function amountsMatch(actualAmount, expectedAmount) {
  if (!Number.isFinite(actualAmount) || !Number.isFinite(expectedAmount)) {
    return false;
  }

  return Math.abs(actualAmount - expectedAmount) < 0.01;
}

function defaultPaymentCollectionSettings() {
  return {
    recipientDisplayName: 'วิทยา ทนหงษา',
    bankAccountNumber: '1643440349',
    promptPayPhoneNumber: '',
    promptPayNationalIdOrTaxId: '1410400168710',
  };
}

function isPromptPayPhoneDigits(value) {
  const digits = normalizeDigits(value);
  return digits.length >= 9 && digits.length <= 10;
}

function normalizePaymentCollectionSettings(raw = {}) {
  const defaults = defaultPaymentCollectionSettings();
  let promptPayPhoneNumber = String(raw.promptPayPhoneNumber || '').trim();
  let promptPayNationalIdOrTaxId = String(
    raw.promptPayNationalIdOrTaxId || defaults.promptPayNationalIdOrTaxId,
  ).trim();

  if (!isPromptPayPhoneDigits(promptPayPhoneNumber)) {
    promptPayPhoneNumber = '';
  } else {
    promptPayPhoneNumber = normalizeDigits(promptPayPhoneNumber);
  }

  const nationalDigits = normalizeDigits(promptPayNationalIdOrTaxId);
  if (nationalDigits.length === 13) {
    promptPayNationalIdOrTaxId = nationalDigits;
  } else if (isPromptPayPhoneDigits(nationalDigits) && !promptPayPhoneNumber) {
    // Some configs store a phone number in the national-id field.
    promptPayPhoneNumber = nationalDigits;
    promptPayNationalIdOrTaxId = defaults.promptPayNationalIdOrTaxId;
  } else if (nationalDigits.length !== 13) {
    promptPayNationalIdOrTaxId = defaults.promptPayNationalIdOrTaxId;
  }

  return {
    recipientDisplayName:
      String(raw.recipientDisplayName || defaults.recipientDisplayName).trim()
      || defaults.recipientDisplayName,
    bankAccountNumber:
      String(raw.bankAccountNumber || defaults.bankAccountNumber).trim()
      || defaults.bankAccountNumber,
    promptPayPhoneNumber,
    promptPayNationalIdOrTaxId,
  };
}

async function getPaymentCollectionSettings() {
  const defaults = defaultPaymentCollectionSettings();

  try {
    const snapshot = await db
      .collection(PAYMENT_CONFIG_COLLECTION)
      .doc(PAYMENT_CONFIG_DOC_ID)
      .get();
    return normalizePaymentCollectionSettings(snapshot.data() || defaults);
  } catch (error) {
    logger.warn('Failed to read payment config. Falling back to defaults.', {
      message: error instanceof Error ? error.message : String(error),
    });
    return defaults;
  }
}

function normalizeMaskedDigits(value) {
  return String(value || '')
    .trim()
    .replace(/\*/g, 'X')
    .replace(/[^0-9xX]/g, '')
    .toUpperCase();
}

function buildDigitMaskPattern(value) {
  let pattern = '';
  for (const char of String(value || '')) {
    if (/[0-9]/.test(char)) {
      pattern += char;
    } else if (char === '*' || char === 'X' || char === 'x') {
      pattern += '?';
    }
  }
  return pattern;
}

function digitMaskPatternMatches(pattern, expectedDigits) {
  if (!pattern || !expectedDigits || pattern.length !== expectedDigits.length) {
    return false;
  }

  for (let index = 0; index < pattern.length; index += 1) {
    const patternChar = pattern[index];
    if (patternChar !== '?' && patternChar !== expectedDigits[index]) {
      return false;
    }
  }

  return true;
}

function promptPayFormattedIdMatches(actualValue, expectedValue) {
  const expectedDigits = normalizeDigits(expectedValue);
  if (expectedDigits.length !== 13) {
    return false;
  }

  const pattern = buildDigitMaskPattern(actualValue);
  if (digitMaskPatternMatches(pattern, expectedDigits)) {
    return true;
  }

  const masked = normalizeMaskedDigits(actualValue);
  if (masked.length === expectedDigits.length) {
    for (let index = 0; index < expectedDigits.length; index += 1) {
      const maskedChar = masked[index];
      if (maskedChar !== 'X' && maskedChar !== expectedDigits[index]) {
        return false;
      }
    }
    return true;
  }

  return false;
}

function normalizeDigits(value) {
  return String(value || '')
    .trim()
    .replace(/\D/g, '');
}

function maskedDigitsMatch(maskedValue, expectedValue) {
  const masked = normalizeMaskedDigits(maskedValue);
  const expected = normalizeDigits(expectedValue);

  if (!masked || !expected || masked.length !== expected.length) {
    return false;
  }

  for (let index = 0; index < masked.length; index += 1) {
    const maskedChar = masked[index];
    if (maskedChar !== 'X' && maskedChar !== expected[index]) {
      return false;
    }
  }

  return true;
}

function normalizeNameForComparison(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9ก-๙]/g, '');
}

function namePartiallyMatches(actualValue, expectedValue) {
  const actual = normalizeNameForComparison(actualValue);
  const expected = normalizeNameForComparison(expectedValue);

  if (!actual || !expected) {
    return false;
  }

  if (actual.includes(expected) || expected.includes(actual)) {
    return true;
  }

  const minPrefix = Math.min(actual.length, expected.length, 6);
  if (minPrefix >= 4) {
    const actualPrefix = actual.slice(0, minPrefix);
    const expectedPrefix = expected.slice(0, minPrefix);
    if (actual.includes(expectedPrefix) || expected.includes(actualPrefix)) {
      return true;
    }
  }

  return false;
}

function buildExpectedReceiverTargets(settings) {
  const defaults = defaultPaymentCollectionSettings();
  const targets = new Set();

  for (const value of [
    settings.bankAccountNumber,
    settings.promptPayPhoneNumber,
    settings.promptPayNationalIdOrTaxId,
    defaults.promptPayNationalIdOrTaxId,
  ]) {
    const digits = normalizeDigits(value);
    if (!digits) {
      continue;
    }
    targets.add(digits);
    if (isPromptPayPhoneDigits(digits)) {
      const local = digits.startsWith('0') ? digits.slice(1) : digits;
      targets.add(`66${local}`);
      if (!digits.startsWith('0')) {
        targets.add(`0${digits}`);
      }
    }
  }

  return [...targets];
}

function validateSlipReceiver(providerPayload, settings) {
  const receiver = providerPayload?.data?.receiver || {};
  const accountValue = String(receiver?.account?.value || '').trim();
  const proxyValue = String(receiver?.proxy?.value || '').trim();
  const actualNames = [receiver?.displayName, receiver?.name].map((value) => String(value || '').trim()).filter(Boolean);
  const expectedTargets = buildExpectedReceiverTargets(settings);
  const actualTargets = [accountValue, proxyValue].filter(Boolean);

  const accountMatched =
    actualTargets.length > 0 &&
    expectedTargets.some((expectedTarget) =>
      actualTargets.some((actualTarget) =>
        maskedDigitsMatch(actualTarget, expectedTarget) ||
        promptPayFormattedIdMatches(actualTarget, expectedTarget),
      ),
    );

  const nameMatched = actualNames.some((actualName) =>
    namePartiallyMatches(actualName, settings.recipientDisplayName),
  );

  const matched = accountMatched || (!actualTargets.length && nameMatched);

  return {
    matched,
    accountMatched,
    nameMatched,
    actualAccountValue: accountValue,
    actualProxyValue: proxyValue,
    actualNames,
    expectedRecipientDisplayName: settings.recipientDisplayName,
    expectedTargets,
  };
}

async function writeSlipOkFeedbackLog({
  feedbackId,
  customerUid,
  orderIds,
  paymentGroupId,
  storagePath,
  fileName,
  contentType,
  expectedCombinedAmount,
  verifiedSlipAmount,
  verificationStatus,
  verificationMessage,
  responseCode,
  providerPayload,
  providerRawText,
}) {
  const docId = String(feedbackId || paymentGroupId || '').trim();
  const feedbackRef = docId
    ? db.collection(SLIPOK_FEEDBACK_COLLECTION).doc(docId)
    : db.collection(SLIPOK_FEEDBACK_COLLECTION).doc();

  await feedbackRef.set({
    provider: 'slipok',
    providerLabel: 'Slip OK',
    customerUid,
    orderIds,
    paymentGroupId,
    storagePath,
    fileName,
    contentType,
    expectedCombinedAmount,
    verifiedSlipAmount,
    status: verificationStatus,
    message: verificationMessage,
    responseCode,
    apiEndpoint: SLIPOK_ENDPOINT,
    response: providerPayload,
    rawResponseText: providerRawText,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return feedbackRef.id;
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

function buildDefaultCustomerDisplayName({ email = '', phoneNumber = '' } = {}) {
  const normalizedEmail = normalizeEmail(email);
  if (normalizedEmail.includes('@')) {
    const localPart = normalizedEmail.split('@')[0].trim();
    if (localPart) {
      return localPart;
    }
  }

  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  if (normalizedPhone) {
    return normalizedPhone;
  }

  return 'ผู้ใช้ใหม่';
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

function phoneToPseudoEmail(phoneNumber) {
  const digits = normalizePhoneNumber(phoneNumber).replace(/^\+/, '');
  return `${digits}@phone.vanmerchant.app`;
}

const identityToolkitAuth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

async function identityToolkitRequest(path, body) {
  const client = await identityToolkitAuth.getClient();
  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    'van-merchant';
  const url = `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/${path}`;
  try {
    const response = await client.request({
      url,
      method: 'POST',
      data: body,
    });
    return response.data || {};
  } catch (error) {
    const apiError = error?.response?.data?.error;
    const message =
      apiError?.message ||
      (error instanceof Error ? error.message : String(error));
    const wrapped = new Error(message);
    wrapped.code = apiError?.status || error?.code;
    throw wrapped;
  }
}

async function sendPhoneVerificationCode(phoneNumber) {
  const data = await identityToolkitRequest('accounts:sendVerificationCode', {
    phoneNumber: normalizePhoneNumber(phoneNumber),
  });
  const sessionInfo = String(data.sessionInfo || '').trim();
  if (!sessionInfo) {
    throw new Error('Identity Toolkit did not return sessionInfo');
  }
  return sessionInfo;
}

async function signInWithPhoneVerificationCode(sessionInfo, code) {
  return identityToolkitRequest('accounts:signInWithPhoneNumber', {
    sessionInfo,
    code: normalizeOtp(code),
  });
}

function parseNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function roundForPayment(value) {
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  const floorValue = Math.floor(value);
  const fraction = value - floorValue;
  if (fraction > 0.5) {
    return floorValue + 1;
  }
  return floorValue;
}

function applyMarkup(amount, rate) {
  if (!Number.isFinite(amount) || amount <= 0) {
    return 0;
  }
  return roundForPayment(amount * (1 + rate));
}

function applyProductMarkup(amount, taxable) {
  return applyMarkup(
    amount,
    taxable ? DEFAULT_TAXABLE_MARKUP_RATE : DEFAULT_NON_TAXABLE_MARKUP_RATE,
  );
}

function applyToppingMarkup(amount) {
  return applyMarkup(amount, DEFAULT_TOPPING_MARKUP_RATE);
}

function sanitizeRate(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 5) {
    return fallback;
  }
  return parsed;
}

function sanitizeMoney(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 100000) {
    return fallback;
  }
  return parsed;
}

function sanitizeKm(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100) {
    return fallback;
  }
  return parsed;
}

function sanitizeRadiusMeters(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 10000) {
    return fallback;
  }
  return parsed;
}

function sanitizeInt(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    return fallback;
  }
  return parsed;
}

function sanitizeLatitude(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed < -90 || parsed > 90) {
    return fallback;
  }
  return parsed;
}

function sanitizeLongitude(value, fallback) {
  const parsed = parseNumber(value);
  if (!Number.isFinite(parsed) || parsed < -180 || parsed > 180) {
    return fallback;
  }
  return parsed;
}

function defaultPricingRates() {
  return {
    taxableMarkupRate: DEFAULT_TAXABLE_MARKUP_RATE,
    nonTaxableMarkupRate: DEFAULT_NON_TAXABLE_MARKUP_RATE,
    toppingMarkupRate: DEFAULT_TOPPING_MARKUP_RATE,
    shippingBaseFee: DEFAULT_SHIPPING_BASE_FEE,
    shippingPerKmFee: DEFAULT_SHIPPING_PER_KM_FEE,
    shippingMinBillableKm: DEFAULT_SHIPPING_MIN_BILLABLE_KM,
    shippingMissingCoordsFee: DEFAULT_SHIPPING_MISSING_COORDS_FEE,
    travelBaseFee: DEFAULT_SHIPPING_BASE_FEE,
    travelPerKmFee: DEFAULT_SHIPPING_PER_KM_FEE,
    travelMinBillableKm: DEFAULT_SHIPPING_MIN_BILLABLE_KM,
    nationwideBaseFee: 45,
    nationwidePerKgFee: 18,
    nationwideRemoteSurcharge: 30,
    marketHubLatitude: DEFAULT_MARKET_HUB_LATITUDE,
    marketHubLongitude: DEFAULT_MARKET_HUB_LONGITUDE,
    marketHubRadiusMeters: DEFAULT_MARKET_HUB_RADIUS_METERS,
    marketMultiShopMinShops: DEFAULT_MARKET_MULTI_SHOP_MIN_SHOPS,
    marketMultiShopCollectionFee: DEFAULT_MARKET_COLLECTION_FEE,
    marketServiceFeePerOrder: DEFAULT_MARKET_SERVICE_FEE_PER_ORDER,
  };
}

async function getPricingRates() {
  const now = Date.now();
  if (pricingConfigCache.rates && now < pricingConfigCache.expiresAt) {
    return pricingConfigCache.rates;
  }

  const defaults = defaultPricingRates();
  try {
    const docRef = db.collection(PRICING_CONFIG_COLLECTION).doc(PRICING_CONFIG_DOC_ID);
    const snapshot = await docRef.get();
    if (!snapshot.exists) {
      await docRef.set(
        {
          ...defaults,
          note: 'Admin-managed global pricing: markup, local shipping, travel, nationwide',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      pricingConfigCache = {
        rates: defaults,
        expiresAt: now + PRICING_CONFIG_CACHE_TTL_MS,
      };
      return defaults;
    }

    const data = snapshot.data() || {};
    const rates = {
      taxableMarkupRate: sanitizeRate(data.taxableMarkupRate, defaults.taxableMarkupRate),
      nonTaxableMarkupRate: sanitizeRate(data.nonTaxableMarkupRate, defaults.nonTaxableMarkupRate),
      toppingMarkupRate: sanitizeRate(data.toppingMarkupRate, defaults.toppingMarkupRate),
      shippingBaseFee: sanitizeMoney(data.shippingBaseFee, defaults.shippingBaseFee),
      shippingPerKmFee: sanitizeMoney(data.shippingPerKmFee, defaults.shippingPerKmFee),
      shippingMinBillableKm: sanitizeKm(data.shippingMinBillableKm, defaults.shippingMinBillableKm),
      shippingMissingCoordsFee: sanitizeMoney(
        data.shippingMissingCoordsFee,
        defaults.shippingMissingCoordsFee,
      ),
      travelBaseFee: sanitizeMoney(data.travelBaseFee, defaults.travelBaseFee),
      travelPerKmFee: sanitizeMoney(data.travelPerKmFee, defaults.travelPerKmFee),
      travelMinBillableKm: sanitizeKm(data.travelMinBillableKm, defaults.travelMinBillableKm),
      nationwideBaseFee: sanitizeMoney(data.nationwideBaseFee, defaults.nationwideBaseFee),
      nationwidePerKgFee: sanitizeMoney(data.nationwidePerKgFee, defaults.nationwidePerKgFee),
      nationwideRemoteSurcharge: sanitizeMoney(
        data.nationwideRemoteSurcharge,
        defaults.nationwideRemoteSurcharge,
      ),
      marketHubLatitude: sanitizeLatitude(data.marketHubLatitude, defaults.marketHubLatitude),
      marketHubLongitude: sanitizeLongitude(data.marketHubLongitude, defaults.marketHubLongitude),
      marketHubRadiusMeters: sanitizeRadiusMeters(
        data.marketHubRadiusMeters,
        defaults.marketHubRadiusMeters,
      ),
      marketMultiShopMinShops: sanitizeInt(
        data.marketMultiShopMinShops,
        defaults.marketMultiShopMinShops,
        2,
        20,
      ),
      marketMultiShopCollectionFee: sanitizeMoney(
        data.marketMultiShopCollectionFee,
        defaults.marketMultiShopCollectionFee,
      ),
      marketServiceFeePerOrder: sanitizeMoney(
        data.marketServiceFeePerOrder,
        defaults.marketServiceFeePerOrder,
      ),
    };

    pricingConfigCache = {
      rates,
      expiresAt: now + PRICING_CONFIG_CACHE_TTL_MS,
    };
    return rates;
  } catch (error) {
    logger.warn('Failed to read pricing config. Falling back to defaults.', {
      message: error instanceof Error ? error.message : String(error),
    });
    return defaults;
  }
}

function applyProductMarkupWithRates(amount, taxable, rates) {
  const rate = taxable ? rates.taxableMarkupRate : rates.nonTaxableMarkupRate;
  return applyMarkup(amount, rate);
}

function applyToppingMarkupWithRates(amount, rates) {
  return applyMarkup(amount, rates.toppingMarkupRate);
}

function normalizeText(value) {
  return String(value || '').trim().toLowerCase();
}

function canonicalizeToppingLabel(value) {
  let text = normalizeText(value);
  if (!text) {
    return '';
  }

  // Accept legacy client payloads like "+ชีส 11" and map to "+ชีส".
  text = text.replace(/\s+\d+(?:\.\d+)?\s*$/g, '').trim();
  if (text.startsWith('+')) {
    text = text.substring(1).trim();
  }
  return text;
}

function isTaxableProduct(data = {}) {
  const boolKeys = [
    'isTaxable',
    'taxable',
    'hasTax',
    'includeTax',
    'vatEnabled',
    'isVat',
    'isTaxIncluded',
  ];

  for (const key of boolKeys) {
    const value = data[key];
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      const text = normalizeText(value);
      if (['true', 'yes', '1', 'tax', 'vat', 'taxable', 'เสียภาษี'].includes(text)) {
        return true;
      }
      if (['false', 'no', '0', 'notax', 'no_tax', 'ไม่เสียภาษี'].includes(text)) {
        return false;
      }
    }
  }

  const statusKeys = ['taxStatus', 'taxType', 'vatType'];
  for (const key of statusKeys) {
    const text = normalizeText(data[key]);
    if (text.includes('เสีย') || text.includes('tax') || text.includes('vat')) {
      return true;
    }
    if (text.includes('ไม่เสีย') || text.includes('no tax') || text.includes('notax')) {
      return false;
    }
  }

  return false;
}

function extractPlusSegments(source, rates = defaultPricingRates()) {
  const text = String(source || '').trim();
  if (!text.includes('+')) {
    return [];
  }

  const result = [];
  const matches = text.matchAll(/\+\s*([^+\d][^+]*?)\s*(\d+(?:\.\d+)?)/g);
  for (const match of matches) {
    const label = `+${String(match[1] || '').trim()}`;
    if (!label || label === '+') {
      continue;
    }
    result.push({
      label,
      adjustedPrice: applyToppingMarkupWithRates(parseNumber(match[2]), rates),
    });
  }
  return result;
}

function parseToppingValues(raw, rates = defaultPricingRates()) {
  if (typeof raw === 'string') {
    const plusSegments = extractPlusSegments(raw, rates);
    if (plusSegments.length > 0) {
      return plusSegments;
    }

    return raw
      .split(',')
      .map((value) => value.trim())
      .filter((value) => value)
      .map((value) => ({ label: value, adjustedPrice: 0 }));
  }

  if (Array.isArray(raw)) {
    const result = [];
    for (const item of raw) {
      if (typeof item === 'string') {
        const plusSegments = extractPlusSegments(item, rates);
        if (plusSegments.length > 0) {
          result.push(...plusSegments);
          continue;
        }
        const value = item.trim();
        if (value) {
          result.push({ label: value, adjustedPrice: 0 });
        }
        continue;
      }

      if (item && typeof item === 'object') {
        const label = String(item.name || item.label || item.title || '').trim();
        if (!label) {
          continue;
        }
        result.push({
          label,
          adjustedPrice: applyToppingMarkupWithRates(parseNumber(item.price), rates),
        });
      }
    }
    return result;
  }

  return [];
}

function extractToppings(data = {}, rates = defaultPricingRates()) {
  const keys = ['toppings', 'topping', 'addons', 'addOns', 'options', 'extraOptions'];
  for (const key of keys) {
    const values = parseToppingValues(data[key], rates);
    if (values.length > 0) {
      return values;
    }
  }
  return [];
}

function toFiniteOrNull(value) {
  const parsed = parseNumber(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function haversineDistanceKm(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function computeShippingFeeByDistance(distanceKm, rates = defaultPricingRates()) {
  const normalized =
    !Number.isFinite(distanceKm) || distanceKm < 0 ? 0 : distanceKm;
  const minKm = rates.shippingMinBillableKm ?? DEFAULT_SHIPPING_MIN_BILLABLE_KM;
  const maxKm = rates.shippingMaxBillableKm ?? DEFAULT_SHIPPING_MAX_BILLABLE_KM;
  const cappedKm = normalized > maxKm ? maxKm : normalized;
  const billableKm = cappedKm < minKm ? minKm : cappedKm;
  const baseFee = rates.shippingBaseFee ?? DEFAULT_SHIPPING_BASE_FEE;
  const perKmFee = rates.shippingPerKmFee ?? DEFAULT_SHIPPING_PER_KM_FEE;
  return baseFee + (billableKm - minKm) * perKmFee;
}

function distanceMeters(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const earthRadiusMeters = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

function isShopNearMarketHub(latitude, longitude, rates = defaultPricingRates()) {
  if (latitude == null || longitude == null) {
    return false;
  }
  const hubLat = rates.marketHubLatitude ?? DEFAULT_MARKET_HUB_LATITUDE;
  const hubLng = rates.marketHubLongitude ?? DEFAULT_MARKET_HUB_LONGITUDE;
  const radius = rates.marketHubRadiusMeters ?? DEFAULT_MARKET_HUB_RADIUS_METERS;
  return distanceMeters(latitude, longitude, hubLat, hubLng) <= radius;
}

function computeMarketCheckoutFees(shops, rates = defaultPricingRates()) {
  const minShops = rates.marketMultiShopMinShops ?? DEFAULT_MARKET_MULTI_SHOP_MIN_SHOPS;
  const collectionFee =
    rates.marketMultiShopCollectionFee ?? DEFAULT_MARKET_COLLECTION_FEE;
  const serviceFeePerOrder =
    rates.marketServiceFeePerOrder ?? DEFAULT_MARKET_SERVICE_FEE_PER_ORDER;

  const shopCount = shops.size;
  let hubQualifyingCount = 0;
  for (const shop of shops.values()) {
    if (isShopNearMarketHub(shop.latitude, shop.longitude, rates)) {
      hubQualifyingCount += 1;
    }
  }

  const marketServiceFee =
    shopCount > 0 && serviceFeePerOrder > 0 ? serviceFeePerOrder * shopCount : 0;
  const marketCollectionFee =
    hubQualifyingCount >= minShops ? collectionFee : 0;

  return {
    applies: marketServiceFee > 0 || marketCollectionFee > 0,
    qualifyingShopCount: hubQualifyingCount,
    marketCollectionFee,
    marketServiceFee,
    marketTotalFees: marketCollectionFee + marketServiceFee,
  };
}

async function loadProductsByIds(productIds) {
  const chunks = [];
  for (let i = 0; i < productIds.length; i += 30) {
    chunks.push(productIds.slice(i, i + 30));
  }

  const productMap = new Map();
  for (const chunk of chunks) {
    if (chunk.length === 0) {
      continue;
    }
    const snapshot = await db
      .collection('products')
      .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
      .get();
    for (const doc of snapshot.docs) {
      productMap.set(doc.id, doc.data() || {});
    }
  }

  return productMap;
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
    enforceAppCheck: true,
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM],
  },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    if (!email || !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
    }

    const clientIp = readClientIp(request);
    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `send_email_otp:${email}`,
      maxAttempts: 5,
      windowMs: 15 * 60 * 1000,
      message: 'ขอ OTP บ่อยเกินไป กรุณารอ 15 นาที',
    });
    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `send_email_otp_ip:${clientIp}`,
      maxAttempts: 20,
      windowMs: 15 * 60 * 1000,
    });

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

exports.lookupLoginIdentifier = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    const clientIp = readClientIp(request);
    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `lookup_login_ip:${clientIp}`,
      maxAttempts: 30,
      windowMs: 15 * 60 * 1000,
    });

    const email = normalizeEmail(request.data?.email);
    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);

    if (!email && !phoneNumber) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุอีเมลหรือเบอร์โทร');
    }

    if (email && !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
    }

    if (phoneNumber && !phoneNumber.startsWith('+')) {
      throw new HttpsError('invalid-argument', 'รูปแบบเบอร์โทรไม่ถูกต้อง');
    }

    let emailExists = false;
    let phoneExists = false;

    if (email) {
      try {
        await admin.auth().getUserByEmail(email);
        emailExists = true;
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') {
          throw new HttpsError('internal', 'ตรวจสอบอีเมลไม่สำเร็จ');
        }
      }
    }

    if (phoneNumber) {
      try {
        const profileDoc = await db.collection('phone_login_profiles').doc(phoneNumber).get();
        phoneExists = profileDoc.exists;
        if (!phoneExists) {
          await admin.auth().getUserByPhoneNumber(phoneNumber);
          phoneExists = true;
        }
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') {
          throw new HttpsError('internal', 'ตรวจสอบเบอร์โทรไม่สำเร็จ');
        }
      }
    }

    return {
      success: true,
      email,
      phoneNumber,
      emailExists,
      phoneExists,
    };
  },
);

exports.resolveRiderLoginEmail = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);

    if (!phoneNumber || !phoneNumber.startsWith('+')) {
      throw new HttpsError('invalid-argument', 'รูปแบบเบอร์โทรไม่ถูกต้อง');
    }

    const digits = phoneNumber.replace(/\D/g, '');
    const pseudoEmail = `${digits}@phone.vanmerchant.app`;

    const snapshot = await db
      .collection('riders')
      .where('phoneNumber', '==', phoneNumber)
      .limit(1)
      .get();

    if (snapshot.empty) {
      return {
        success: true,
        found: false,
        loginEmail: null,
        useEmailLogin: false,
      };
    }

    const data = snapshot.docs[0].data() || {};
    const storedLoginEmail = String(data.loginEmail || data.email || '').trim();
    const loginEmail =
      storedLoginEmail && storedLoginEmail.toLowerCase() === pseudoEmail.toLowerCase()
        ? storedLoginEmail
        : null;

    return {
      success: true,
      found: true,
      loginEmail,
      useEmailLogin: Boolean(storedLoginEmail && !loginEmail),
    };
  },
);

exports.verifyEmailOtp = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    const email = normalizeEmail(request.data?.email);
    const otp = normalizeOtp(request.data?.otp);
    const mode = normalizeMode(request.data?.mode);
    const password = String(request.data?.password || '').trim();
    const otpPattern = /^\d{6}$/;

    if (!email || !email.includes('@')) {
      throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
    }

    if (
      mode !== 'sign_in' &&
      mode !== 'register' &&
      mode !== 'reset_password' &&
      mode !== 'reset_password_check'
    ) {
      throw new HttpsError('invalid-argument', 'โหมดการยืนยัน OTP ไม่ถูกต้อง');
    }

    if ((mode === 'reset_password' || mode === 'register') && password.length < 6) {
      throw new HttpsError(
        'invalid-argument',
        'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร',
      );
    }

    if ((mode === 'sign_in' || mode === 'register' || mode === 'reset_password_check') && !otpPattern.test(otp)) {
      throw new HttpsError('invalid-argument', 'OTP ต้องเป็นตัวเลข 6 หลัก');
    }

    const otpCollectionRef = db.collection('email_otps');
    const otpRef = otpCollectionRef.doc(otpDocId(email));
    const resetSessionRef = db
      .collection('email_otp_reset_sessions')
      .doc(otpDocId(email));

    const verifyOtpDocument = async () => {
      const snapshot = await otpRef.get();
      if (!snapshot.exists) {
        throw new HttpsError('not-found', 'ไม่พบรหัส OTP สำหรับอีเมลนี้');
      }

      const data = snapshot.data() || {};
      const expiresAt = data.expiresAt?.toMillis?.() || 0;
      const attempts = Number(data.attempts || 0);

      if (Date.now() > expiresAt) {
        await otpRef.delete();
        throw new HttpsError('deadline-exceeded', 'OTP หมดอายุแล้ว');
      }

      if (attempts >= MAX_VERIFY_ATTEMPTS) {
        await otpRef.delete();
        throw new HttpsError('permission-denied', 'กรอกรหัสผิดเกินจำนวนที่กำหนด');
      }

      if (data.otpHash !== hashOtp(email, otp)) {
        await otpRef.set(
          {
            attempts: attempts + 1,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        throw new HttpsError('permission-denied', 'รหัส OTP ไม่ถูกต้อง');
      }

      return true;
    };

    if (mode === 'sign_in' || mode === 'register' || mode === 'reset_password_check') {
      await verifyOtpDocument();
    }

    if (mode === 'sign_in' || mode === 'register') {
      await otpRef.delete();
      await resetSessionRef.delete().catch(() => {});
    }

    if (mode === 'reset_password_check') {
      await resetSessionRef.set(
        {
          email,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + RESET_PASSWORD_SESSION_TTL_MS,
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      // Keep OTP alive for the password step if the reset session lookup fails.
      await otpRef.set(
        {
          expiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + RESET_PASSWORD_SESSION_TTL_MS,
          ),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { success: true, otpVerified: true };
    }

    if (mode === 'reset_password') {
      let hasActiveResetSession = false;
      const resetSessionSnapshot = await resetSessionRef.get();
      if (resetSessionSnapshot.exists) {
        const sessionData = resetSessionSnapshot.data() || {};
        const sessionExpiresAt = sessionData.expiresAt?.toMillis?.() || 0;
        hasActiveResetSession = Date.now() <= sessionExpiresAt;
        if (!hasActiveResetSession) {
          await resetSessionRef.delete().catch(() => {});
        }
      }

      if (!hasActiveResetSession) {
        if (!otpPattern.test(otp)) {
          throw new HttpsError(
            'failed-precondition',
            'กรุณายืนยัน OTP ก่อนตั้งรหัสผ่านใหม่',
          );
        }
        await verifyOtpDocument();
      }

      await otpRef.delete().catch(() => {});
      await resetSessionRef.delete().catch(() => {});
    }

    try {
      if (mode === 'register') {
        const signInProvider = String(request.auth?.token?.firebase?.sign_in_provider || '');
        const hasLinkedAuthenticatedUser = Boolean(request.auth?.uid) && signInProvider !== 'anonymous';
        let existingEmailUser = null;
        try {
          existingEmailUser = await admin.auth().getUserByEmail(email);
        } catch (error) {
          if (error?.code !== 'auth/user-not-found') {
            throw error;
          }
        }

        if (hasLinkedAuthenticatedUser) {
          if (existingEmailUser && existingEmailUser.uid !== request.auth.uid) {
            throw new HttpsError('already-exists', 'อีเมลนี้มีอยู่ในระบบแล้ว');
          }

          const currentUser = await admin.auth().getUser(request.auth.uid);
          const currentEmail = normalizeEmail(currentUser.email || '');
          if (currentEmail && currentEmail !== email) {
            throw new HttpsError('already-exists', 'บัญชีนี้ผูกกับอีเมลอื่นอยู่แล้ว');
          }

          await admin.auth().updateUser(request.auth.uid, {
            email,
            password,
            emailVerified: true,
          });

          const refreshedUser = await admin.auth().getUser(request.auth.uid);
          await db.collection('customer_users').doc(request.auth.uid).set(
            {
              email,
              phoneNumber: normalizePhoneNumber(refreshedUser.phoneNumber || ''),
              displayName: buildDefaultCustomerDisplayName({
                email,
                phoneNumber: refreshedUser.phoneNumber || '',
              }),
              profileCompleted: false,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          return { success: true, linkedToUid: request.auth.uid };
        }

        if (existingEmailUser) {
          throw new HttpsError('already-exists', 'อีเมลนี้มีอยู่ในระบบแล้ว');
        }

        const createdUser = await admin.auth().createUser({
          email,
          password,
          emailVerified: true,
        });

        await db.collection('customer_users').doc(createdUser.uid).set(
          {
            email,
            phoneNumber: '',
            displayName: buildDefaultCustomerDisplayName({
              email,
            }),
            profileCompleted: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        const customToken = await admin.auth().createCustomToken(createdUser.uid);
        return { success: true, customToken, linkedToUid: createdUser.uid };
      }

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

exports.sendMerchantPhoneOtp = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);
    if (!phoneNumber || !phoneNumber.startsWith('+')) {
      throw new HttpsError('invalid-argument', 'เบอร์โทรไม่ถูกต้อง');
    }

    const clientIp = readClientIp(request);
    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `send_phone_otp:${phoneNumber}`,
      maxAttempts: 5,
      windowMs: 15 * 60 * 1000,
      message: 'ขอ OTP บ่อยเกินไป กรุณารอ 15 นาที',
    });
    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `send_phone_otp_ip:${clientIp}`,
      maxAttempts: 20,
      windowMs: 15 * 60 * 1000,
    });

    const docRef = db.collection('phone_otp_sessions').doc(phoneNumber);
    const existingDoc = await docRef.get();
    const now = Date.now();
    if (existingDoc.exists) {
      const data = existingDoc.data() || {};
      const lastSentAt = data.lastSentAt?.toMillis?.() || 0;
      if (now - lastSentAt < OTP_RESEND_INTERVAL_MS) {
        throw new HttpsError('resource-exhausted', 'กรุณารอก่อนขอรหัสใหม่');
      }
    }

    try {
      const sessionInfo = await sendPhoneVerificationCode(phoneNumber);
      await docRef.set(
        {
          phoneNumber,
          sessionInfo,
          attempts: 0,
          lastSentAt: admin.firestore.Timestamp.fromMillis(now),
          expiresAt: admin.firestore.Timestamp.fromMillis(now + OTP_TTL_MS),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { success: true, expiresInSeconds: OTP_TTL_MS / 1000 };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error('sendMerchantPhoneOtp failed', {
        phoneNumber,
        message,
        code: error?.code,
      });
      throw new HttpsError(
        'unavailable',
        message.includes('BILLING')
          ? 'ต้องเปิด Firebase Blaze (Billing) ก่อนส่ง SMS OTP'
          : message.includes('RECAPTCHA') || message.includes('CAPTCHA')
            ? 'ระบบยืนยันเบอร์ไม่พร้อม กรุณาอัปเดตแอปแล้วลองใหม่'
            : 'ไม่สามารถส่ง SMS OTP ได้ในขณะนี้ กรุณาลองใหม่ภายหลัง',
      );
    }
  },
);

exports.verifyMerchantPhoneOtp = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    const phoneNumber = normalizePhoneNumber(request.data?.phoneNumber);
    const otp = normalizeOtp(request.data?.otp);
    const password = String(request.data?.password || '').trim();

    if (!phoneNumber || !phoneNumber.startsWith('+')) {
      throw new HttpsError('invalid-argument', 'เบอร์โทรไม่ถูกต้อง');
    }
    if (otp.length !== 6) {
      throw new HttpsError('invalid-argument', 'รหัส OTP ต้องเป็นตัวเลข 6 หลัก');
    }

    const docRef = db.collection('phone_otp_sessions').doc(phoneNumber);
    const sessionDoc = await docRef.get();
    if (!sessionDoc.exists) {
      throw new HttpsError('failed-precondition', 'กรุณากดส่ง OTP ก่อนยืนยัน');
    }

    const sessionData = sessionDoc.data() || {};
    const expiresAtMs = sessionData.expiresAt?.toMillis?.() || 0;
    if (!expiresAtMs || expiresAtMs < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'รหัส OTP หมดอายุ กรุณาขอรหัสใหม่');
    }

    const attempts = Number(sessionData.attempts || 0);
    if (attempts >= MAX_VERIFY_ATTEMPTS) {
      throw new HttpsError('resource-exhausted', 'กรอก OTP ผิดเกินจำนวนที่กำหนด กรุณาขอรหัสใหม่');
    }

    const sessionInfo = String(sessionData.sessionInfo || '').trim();
    if (!sessionInfo) {
      throw new HttpsError('failed-precondition', 'เซสชัน OTP หมดอายุ กรุณาขอรหัสใหม่');
    }

    let signInResult;
    try {
      signInResult = await signInWithPhoneVerificationCode(sessionInfo, otp);
    } catch (error) {
      await docRef.set(
        {
          attempts: attempts + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw new HttpsError('invalid-argument', 'รหัส OTP ไม่ถูกต้อง');
    }

    const uid = String(signInResult.localId || '').trim();
    if (!uid) {
      throw new HttpsError('internal', 'ยืนยัน OTP สำเร็จ แต่ไม่พบบัญชีผู้ใช้');
    }

    if (password.length >= 4) {
      const pseudoEmail = phoneToPseudoEmail(phoneNumber);
      try {
        await admin.auth().updateUser(uid, {
          email: pseudoEmail,
          password,
          emailVerified: true,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (message.includes('email-already-exists')) {
          await admin.auth().updateUser(uid, { password });
        } else {
          logger.error('verifyMerchantPhoneOtp password link failed', {
            uid,
            phoneNumber,
            message,
          });
          throw new HttpsError(
            'internal',
            'ยืนยัน OTP สำเร็จ แต่ตั้งรหัสผ่านไม่สำเร็จ',
          );
        }
      }

      await db.collection('phone_login_profiles').doc(phoneNumber).set(
        {
          uid,
          phoneNumber,
          passwordHash: hashPhonePassword(phoneNumber, password),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    await db.collection('users').doc(uid).set(
      {
        phoneNumber,
        phoneVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(password.length >= 4
          ? {
              loginEmail: phoneToPseudoEmail(phoneNumber),
              loginProvider: 'phone',
            }
          : {}),
      },
      { merge: true },
    );

    await db.collection('customer_users').doc(uid).set(
      {
        phoneNumber,
        displayName: buildDefaultCustomerDisplayName({ phoneNumber }),
        profileCompleted: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await docRef.delete().catch(() => {});

    const customToken = await admin.auth().createCustomToken(uid);
    return { success: true, customToken, uid };
  },
);

exports.upsertPhonePasswordProfile = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
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
    enforceAppCheck: true,
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

const PROMOTIONS_COLLECTION = 'promotions';
const COUPONS_COLLECTION = 'coupons';
const COUPON_REDEMPTIONS_COLLECTION = 'coupon_redemptions';

function normalizeCouponCode(code) {
  return String(code || '').trim().toUpperCase();
}

function parseTimestampMs(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function isWithinSchedule(conditions = {}, nowMs = Date.now()) {
  const startMs = parseTimestampMs(conditions.startAt);
  const endMs = parseTimestampMs(conditions.endAt);
  if (startMs != null && nowMs < startMs) {
    return false;
  }
  if (endMs != null && nowMs > endMs) {
    return false;
  }
  return true;
}

function evaluateGeoCondition(conditions = {}, customerLat, customerLng, rates) {
  const geo = conditions.geo || {};
  const type = String(geo.type || 'none').toLowerCase();
  if (!type || type === 'none') {
    return true;
  }
  if (!Number.isFinite(customerLat) || !Number.isFinite(customerLng)) {
    return false;
  }
  if (type === 'market_hub') {
    return isShopNearMarketHub(customerLat, customerLng, rates);
  }
  if (type === 'radius') {
    const lat = parseNumber(geo.latitude);
    const lng = parseNumber(geo.longitude);
    const radiusMeters = parseNumber(geo.radiusMeters) || 5000;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return false;
    }
    return distanceMeters(lat, lng, customerLat, customerLng) <= radiusMeters;
  }
  return true;
}

async function countUserOfferRedemptions(offerId, userId, fieldName) {
  if (!userId || !offerId) {
    return 0;
  }
  const snapshot = await db
    .collection(COUPON_REDEMPTIONS_COLLECTION)
    .where('userId', '==', userId)
    .where(fieldName, '==', offerId)
    .limit(100)
    .get();
  return snapshot.size;
}

async function evaluateOfferConditions(offer, context, userId, rates, offerKind) {
  const conditions = offer.conditions || {};

  if (offer.active === false) {
    return { eligible: false, reason: 'ไม่เปิดใช้งาน' };
  }
  if (!isWithinSchedule(conditions)) {
    return { eligible: false, reason: 'หมดเวลาโปรโมชั่น' };
  }

  const minSubtotal = parseNumber(conditions.minSubtotal);
  if (minSubtotal > 0 && context.subtotal < minSubtotal) {
    return {
      eligible: false,
      reason: `ขั้นต่ำ ฿${minSubtotal}`,
      shortfall: minSubtotal - context.subtotal,
    };
  }

  const minItemCount = Math.floor(parseNumber(conditions.minItemCount) || 0);
  if (minItemCount > 0 && context.itemCount < minItemCount) {
    return { eligible: false, reason: `ต้องมีอย่างน้อย ${minItemCount} ชิ้น` };
  }

  const requiredProductIds = Array.isArray(conditions.productIds)
    ? conditions.productIds.map((id) => String(id).trim()).filter(Boolean)
    : [];
  if (requiredProductIds.length > 0) {
    const hasMatch = requiredProductIds.some((id) => context.productIds.includes(id));
    if (!hasMatch) {
      return { eligible: false, reason: 'ไม่ตรงสินค้าในโปร' };
    }
  }

  const requiredShopIds = Array.isArray(conditions.shopIds)
    ? conditions.shopIds.map((id) => String(id).trim()).filter(Boolean)
    : [];
  if (requiredShopIds.length > 0) {
    const hasMatch = requiredShopIds.some((id) => context.shopIds.includes(id));
    if (!hasMatch) {
      return { eligible: false, reason: 'ไม่ตรงร้านในโปร' };
    }
  }

  if (!evaluateGeoCondition(conditions, context.customerLatitude, context.customerLongitude, rates)) {
    return { eligible: false, reason: 'นอกพื้นที่โปรโมชั่น' };
  }

  const maxTotal = Math.floor(parseNumber(conditions.maxRedemptionsTotal) || 0);
  const redemptionCount = Math.floor(parseNumber(offer.redemptionCount) || 0);
  if (maxTotal > 0 && redemptionCount >= maxTotal) {
    return { eligible: false, reason: 'โควต้าหมดแล้ว' };
  }

  const maxPerUser = Math.floor(parseNumber(conditions.maxRedemptionsPerUser) || 0);
  if (maxPerUser > 0 && userId) {
    const fieldName = offerKind === 'coupon' ? 'couponId' : 'promotionId';
    const userCount = await countUserOfferRedemptions(offer.id, userId, fieldName);
    if (userCount >= maxPerUser) {
      return { eligible: false, reason: 'คุณใช้สิทธิ์ครบแล้ว' };
    }
  }

  const assigneeUid = String(offer.assigneeUid || conditions.assigneeUid || '').trim();
  if (assigneeUid && userId && assigneeUid !== userId) {
    return { eligible: false, reason: 'คูปองนี้ไม่ใช่ของคุณ' };
  }

  return { eligible: true };
}

function computeDiscountAmount(discount, baseAmounts) {
  const type = String(discount?.type || 'fixed').toLowerCase();
  const value = Math.max(0, parseNumber(discount?.value));
  const maxDiscount = parseNumber(discount?.maxDiscount);
  const applyTo = String(discount?.applyTo || 'subtotal').toLowerCase();

  let base = baseAmounts.subtotal;
  if (applyTo === 'shipping') {
    base = baseAmounts.shippingFee;
  } else if (applyTo === 'grand_total') {
    base = baseAmounts.grandTotalBeforeDiscount;
  } else if (applyTo === 'market_fees') {
    base = baseAmounts.marketTotalFees;
  }

  if (base <= 0) {
    return 0;
  }

  let amount = 0;
  if (type === 'percent') {
    amount = base * (value / 100);
    if (Number.isFinite(maxDiscount) && maxDiscount > 0) {
      amount = Math.min(amount, maxDiscount);
    }
  } else if (type === 'fixed') {
    amount = Math.min(value, base);
  } else if (type === 'free_shipping') {
    amount = Math.min(baseAmounts.shippingFee, base);
  }

  return Math.max(0, Math.round(amount * 100) / 100);
}

async function loadActivePromotions() {
  const snapshot = await db
    .collection(PROMOTIONS_COLLECTION)
    .where('active', '==', true)
    .limit(50)
    .get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

async function loadCouponByCode(code) {
  const normalized = normalizeCouponCode(code);
  if (!normalized) {
    return null;
  }
  const snapshot = await db
    .collection(COUPONS_COLLECTION)
    .where('code', '==', normalized)
    .limit(1)
    .get();
  if (snapshot.empty) {
    return null;
  }
  const doc = snapshot.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function applyCartDiscounts({
  userId,
  subtotal,
  shippingFee,
  marketTotalFees,
  couponCode,
  context,
  rates,
}) {
  const grandTotalBeforeDiscount = subtotal + shippingFee + marketTotalFees;
  const baseAmounts = {
    subtotal,
    shippingFee,
    marketTotalFees,
    grandTotalBeforeDiscount,
  };

  const promotions = await loadActivePromotions();
  const appliedLines = [];
  const nearMissPromotions = [];
  let promotionDiscount = 0;
  let couponDiscount = 0;
  let stackNote = null;

  const sortedPromotions = promotions
    .slice()
    .sort((a, b) => (parseNumber(b.priority) || 0) - (parseNumber(a.priority) || 0));

  for (const promo of sortedPromotions) {
    const evaluation = await evaluateOfferConditions(promo, context, userId, rates, 'promotion');
    if (evaluation.eligible) {
      const promoAmount = computeDiscountAmount(promo.discount, baseAmounts);
      if (promoAmount > 0) {
        promotionDiscount = promoAmount;
        appliedLines.push({
          kind: 'promotion',
          id: promo.id,
          label: String(promo.display?.shortLabel || promo.name || 'โปรโมชั่น'),
          amount: promoAmount,
          stackableWithCoupon: promo.stackableWithCoupon !== false,
        });
        break;
      }
    } else if (evaluation.shortfall > 0) {
      nearMissPromotions.push({
        id: promo.id,
        label: String(promo.display?.shortLabel || promo.name || 'โปรโมชั่น'),
        reason: evaluation.reason,
        shortfall: evaluation.shortfall,
      });
    }
  }

  let couponOffer = null;
  let couponError = null;
  let appliedCouponCode = null;

  if (couponCode) {
    couponOffer = await loadCouponByCode(couponCode);
    if (!couponOffer) {
      couponError = 'ไม่พบคูปองนี้';
    } else {
      const couponEval = await evaluateOfferConditions(couponOffer, context, userId, rates, 'coupon');
      if (!couponEval.eligible) {
        couponError = couponEval.reason || 'ใช้คูปองไม่ได้';
      } else {
        const couponStackable = couponOffer.stackableWithPromotion !== false;
        const promoStackable =
          appliedLines.length === 0 || appliedLines.every((line) => line.stackableWithCoupon !== false);

        const couponOnlyAmount = computeDiscountAmount(couponOffer.discount, baseAmounts);

        if (appliedLines.length > 0 && (!couponStackable || !promoStackable)) {
          if (couponOnlyAmount >= promotionDiscount) {
            promotionDiscount = 0;
            appliedLines.length = 0;
            couponDiscount = couponOnlyAmount;
            appliedLines.push({
              kind: 'coupon',
              id: couponOffer.id,
              code: normalizeCouponCode(couponOffer.code),
              label: String(
                couponOffer.display?.shortLabel || couponOffer.name || couponOffer.code,
              ),
              amount: couponOnlyAmount,
            });
            stackNote = 'ใช้คูปองแทนโปร (ไม่สามารถใช้พร้อมกัน)';
          } else {
            stackNote = 'ใช้โปรแทนคูปอง (ไม่สามารถใช้พร้อมกัน)';
          }
        } else {
          couponDiscount = computeDiscountAmount(couponOffer.discount, {
            ...baseAmounts,
            subtotal: Math.max(0, baseAmounts.subtotal - promotionDiscount),
          });
          if (couponDiscount > 0) {
            appliedLines.push({
              kind: 'coupon',
              id: couponOffer.id,
              code: normalizeCouponCode(couponOffer.code),
              label: String(
                couponOffer.display?.shortLabel || couponOffer.name || couponOffer.code,
              ),
              amount: couponDiscount,
            });
          }
        }

        if (couponDiscount > 0) {
          appliedCouponCode = normalizeCouponCode(couponOffer.code);
        }
      }
    }
  }

  let discountTotal = promotionDiscount + couponDiscount;
  discountTotal = Math.min(discountTotal, grandTotalBeforeDiscount);
  const grandTotal = Math.max(0, grandTotalBeforeDiscount - discountTotal);

  return {
    promotionDiscount,
    couponDiscount,
    discountTotal,
    discountLines: appliedLines,
    nearMissPromotions: nearMissPromotions.slice(0, 3),
    couponError,
    appliedCouponCode,
    grandTotal,
    stackNote,
  };
}

function assertAuthenticatedNonAnonymous(request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
  }
  if (request.auth?.token?.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError(
      'failed-precondition',
      'กรุณาเข้าสู่ระบบด้วยบัญชีจริงก่อนบันทึกความยินยอม',
    );
  }
  return uid;
}

function normalizePrivacyAppKey(value) {
  const appKey = String(value || '').trim();
  if (!PRIVACY_APP_KEYS.has(appKey)) {
    throw new HttpsError('invalid-argument', 'แอปไม่ถูกต้อง');
  }
  return appKey;
}

function normalizePrivacyRequestType(value) {
  const requestType = String(value || '').trim().toLowerCase();
  if (!PRIVACY_REQUEST_TYPES.has(requestType)) {
    throw new HttpsError('invalid-argument', 'ประเภทคำขอไม่ถูกต้อง');
  }
  return requestType;
}

function privacyRequestTypeLabel(requestType) {
  switch (requestType) {
    case 'export':
      return 'ขอส่งออกข้อมูลส่วนบุคคล';
    case 'delete':
      return 'ขอลบบัญชีและข้อมูล';
    case 'correct':
      return 'ขอแก้ไขข้อมูลส่วนบุคคล';
    default:
      return requestType;
  }
}

function privacyAppSourceLabel(appKey) {
  switch (appKey) {
    case 'van2_customer':
      return 'ลูกค้า (van2)';
    case 'van1_merchant':
      return 'ร้านค้า (van1)';
    case 'van3_rider':
      return 'ไรเดอร์ (van3)';
    default:
      return appKey;
  }
}

exports.recordPrivacyConsent = onCall(
  {
    region: DEFAULT_REGION,
  },
  async (request) => {
    const uid = assertAuthenticatedNonAnonymous(request);
    const appKey = normalizePrivacyAppKey(request.data?.app);
    const policyVersion = String(request.data?.policyVersion || '').trim();
    if (!policyVersion) {
      throw new HttpsError('invalid-argument', 'ไม่พบเวอร์ชันนโยบาย');
    }

    const pushOptIn = request.data?.pushOptIn === true;
    const marketingOptIn = request.data?.marketingOptIn === true;
    const locale = String(request.data?.locale || 'th').trim().slice(0, 16);
    const platform = String(request.data?.platform || 'unknown')
      .trim()
      .slice(0, 32);
    const source = String(request.data?.source || 'app').trim().slice(0, 64);
    const now = FieldValue.serverTimestamp();

    await db
      .collection(PRIVACY_CONSENTS_COLLECTION)
      .doc(uid)
      .set(
        {
          uid,
          apps: {
            [appKey]: {
              policyVersion,
              termsAcceptedAt: now,
              pushOptIn,
              marketingOptIn,
              locale,
              platform,
              source,
              updatedAt: now,
            },
          },
          updatedAt: now,
        },
        { merge: true },
      );

    return {
      success: true,
      uid,
      app: appKey,
      policyVersion,
      pushOptIn,
      marketingOptIn,
    };
  },
);

exports.createPrivacyRequest = onCall(
  {
    region: DEFAULT_REGION,
  },
  async (request) => {
    const uid = assertAuthenticatedNonAnonymous(request);
    const appKey = normalizePrivacyAppKey(request.data?.app);
    const requestType = normalizePrivacyRequestType(request.data?.type);
    const note = String(request.data?.note || '').trim().slice(0, 500);
    const now = FieldValue.serverTimestamp();

    const requestRef = db.collection(PRIVACY_REQUESTS_COLLECTION).doc();
    const typeLabel = privacyRequestTypeLabel(requestType);
    const appLabel = privacyAppSourceLabel(appKey);

    await requestRef.set({
      uid,
      app: appKey,
      type: requestType,
      typeLabel,
      status: 'pending',
      note: note || null,
      createdAt: now,
      updatedAt: now,
    });

    const userRecord = await admin.auth().getUser(uid).catch(() => null);
    const requesterName =
      String(userRecord?.displayName || '').trim() ||
      String(userRecord?.email || '').trim() ||
      'ผู้ใช้';
    const ticketRef = db.collection('admin_support_tickets').doc();
    const ticketMessage = [
      `[PDPA] ${typeLabel}`,
      `แอป: ${appLabel}`,
      `Request ID: ${requestRef.id}`,
      ...(note ? [`หมายเหตุ: ${note}`] : []),
    ].join('\n');

    await ticketRef.set({
      sourceApp: appKey,
      sourceLabel: appLabel,
      requesterUid: uid,
      requesterName,
      requesterEmail: userRecord?.email || null,
      requesterPhone: userRecord?.phoneNumber || null,
      topicKey: 'privacy_rights',
      topicLabel: typeLabel,
      message: ticketMessage,
      imageUrls: [],
      status: 'open',
      privacyRequestId: requestRef.id,
      privacyRequestType: requestType,
      unreadForRequester: false,
      unreadForAdmin: true,
      lastMessagePreview: typeLabel,
      lastMessageRole: 'requester',
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
    });

    return {
      success: true,
      requestId: requestRef.id,
      ticketId: ticketRef.id,
      type: requestType,
    };
  },
);

exports.recordCheckoutDiscounts = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const checkoutQuoteId = String(request.data?.checkoutQuoteId || '').trim();
    const orderIds = Array.isArray(request.data?.orderIds)
      ? request.data.orderIds.map((id) => String(id).trim()).filter(Boolean)
      : [];
    const discountLines = Array.isArray(request.data?.discountLines)
      ? request.data.discountLines
      : [];
    const discountTotal = Math.max(0, parseNumber(request.data?.discountTotal));

    if (!checkoutQuoteId) {
      throw new HttpsError('invalid-argument', 'ต้องมี checkoutQuoteId');
    }
    if (orderIds.length === 0 || discountTotal <= 0 || discountLines.length === 0) {
      return { recorded: false, reason: 'no_discount' };
    }

    const userId = request.auth.uid;
    const quoteRef = db.collection('checkout_quotes').doc(checkoutQuoteId);
    const quoteSnap = await quoteRef.get();
    if (!quoteSnap.exists) {
      throw new HttpsError('not-found', 'ไม่พบ checkout quote');
    }
    const quote = quoteSnap.data() || {};
    if (String(quote.customerId || '') !== userId) {
      throw new HttpsError('permission-denied', 'checkout quote ไม่ตรงกับผู้ใช้');
    }
    if (quote.consumed !== true) {
      throw new HttpsError('failed-precondition', 'checkout quote ยังไม่ถูกใช้กับออเดอร์');
    }

    const quotedDiscountTotal = parseNumber(quote.discountTotal);
    if (Math.abs(quotedDiscountTotal - discountTotal) > 0.02) {
      throw new HttpsError('invalid-argument', 'ยอดส่วนลดไม่ตรงกับ quote');
    }

    let lineSum = 0;
    for (const line of discountLines) {
      lineSum += Math.max(0, parseNumber(line?.amount));
    }
    if (Math.abs(lineSum - discountTotal) > 0.02) {
      throw new HttpsError('invalid-argument', 'รายการส่วนลดไม่ตรงกับยอดรวม');
    }

    const orderSnapshots = await Promise.all(
      orderIds.map((orderId) => db.collection('orders').doc(orderId).get()),
    );
    for (const snapshot of orderSnapshots) {
      if (!snapshot.exists) {
        throw new HttpsError('not-found', 'ไม่พบออเดอร์สำหรับบันทึกส่วนลด');
      }
      const order = snapshot.data() || {};
      if (String(order.customerId || '') !== userId) {
        throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์บันทึกส่วนลดให้ออเดอร์นี้');
      }
      if (String(order.checkoutQuoteId || '') !== checkoutQuoteId) {
        throw new HttpsError('failed-precondition', 'ออเดอร์ไม่ตรงกับ checkout quote');
      }
    }

    const batch = db.batch();
    const now = FieldValue.serverTimestamp();

    for (const line of discountLines) {
      const amount = Math.max(0, parseNumber(line?.amount));
      if (amount <= 0) {
        continue;
      }

      const kind = String(line?.kind || '').toLowerCase();
      const offerId = String(line?.id || '').trim();
      if (!offerId) {
        continue;
      }

      const redemptionRef = db.collection(COUPON_REDEMPTIONS_COLLECTION).doc();
      batch.set(redemptionRef, {
        userId,
        orderIds,
        checkoutQuoteId,
        discountAmount: amount,
        redeemedAt: now,
        ...(kind === 'coupon'
          ? {
              couponId: offerId,
              couponCode: normalizeCouponCode(line?.code),
            }
          : {
              promotionId: offerId,
            }),
      });

      const collectionName = kind === 'coupon' ? COUPONS_COLLECTION : PROMOTIONS_COLLECTION;
      batch.set(
        db.collection(collectionName).doc(offerId),
        {
          redemptionCount: FieldValue.increment(1),
          updatedAt: now,
        },
        { merge: true },
      );
    }

    couponClaimsHandlers.markClaimedCouponsUsed(batch, userId, discountLines, now);

    await batch.commit();
    return { recorded: true, orderIds, checkoutQuoteId };
  },
);

exports.claimCoupon = couponClaimsHandlers.claimCoupon;

function buildCheckoutDeps() {
  return {
    db,
    admin,
    FieldValue,
    HttpsError,
    parseNumber,
    loadProductsByIds,
    getPricingRates,
    isTaxableProduct,
    applyProductMarkupWithRates,
    extractToppings,
    canonicalizeToppingLabel,
    haversineDistanceKm,
    computeShippingFeeByDistance,
    computeMarketCheckoutFees,
    applyCartDiscounts,
    normalizeCouponCode,
    toFiniteOrNull,
    isShopNearMarketHub,
    fetchDrivingRouteKm: async (
      originLatitude,
      originLongitude,
      destinationLatitude,
      destinationLongitude,
    ) => {
      try {
        const apiKey = readRequiredConfiguredSecret(
          GOOGLE_GEOCODING_API_KEY_SECRET,
          'GOOGLE_GEOCODING_API_KEY',
          'Google Directions',
        );
        const route = await fetchGoogleDrivingDirectionsRoute({
          apiKey,
          originLatitude,
          originLongitude,
          destinationLatitude,
          destinationLongitude,
          logger,
        });
        if (!route.ok) {
          return null;
        }
        return route.distanceMeters / 1000;
      } catch (error) {
        logger.warn('fetchDrivingRouteKm failed for travel order', {
          message: error instanceof Error ? error.message : String(error),
        });
        return null;
      }
    },
  };
}

exports.calculateCartTotals = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนคำนวณตะกร้า');
    }

    const items = Array.isArray(request.data?.items) ? request.data.items : [];
    if (items.length === 0) {
      return {
        subtotal: 0,
        shippingFee: 0,
        grandTotal: 0,
        promotionDiscount: 0,
        couponDiscount: 0,
        discountTotal: 0,
        discountLines: [],
        itemCount: 0,
        shopCount: 0,
      };
    }
    if (items.length > 200) {
      throw new HttpsError('invalid-argument', 'จำนวนสินค้าในตะกร้ามากเกินไป');
    }

    const customerLatitude = parseNumber(request.data?.customerLatitude);
    const customerLongitude = parseNumber(request.data?.customerLongitude);
    if (!Number.isFinite(customerLatitude) || !Number.isFinite(customerLongitude)) {
      throw new HttpsError('invalid-argument', 'พิกัดลูกค้าไม่ถูกต้อง');
    }

    const totals = await computeVan2CartTotals({
      uid: request.auth.uid,
      items,
      customerLatitude,
      customerLongitude,
      couponCode: normalizeCouponCode(request.data?.couponCode),
      helpers: buildCheckoutDeps(),
    });

    const response = {
      subtotal: totals.subtotal,
      shippingFee: totals.shippingFee,
      marketCollectionFee: totals.marketFees.marketCollectionFee,
      marketServiceFee: totals.marketFees.marketServiceFee,
      marketFeesApplied: totals.marketFees.applies,
      marketQualifyingShopCount: totals.marketFees.qualifyingShopCount,
      promotionDiscount: totals.discounts.promotionDiscount,
      couponDiscount: totals.discounts.couponDiscount,
      discountTotal: totals.discounts.discountTotal,
      discountLines: totals.discounts.discountLines,
      nearMissPromotions: totals.discounts.nearMissPromotions,
      appliedCouponCode: totals.discounts.appliedCouponCode,
      couponError: totals.discounts.couponError,
      stackNote: totals.discounts.stackNote,
      grandTotal: totals.grandTotal,
      itemCount: totals.itemCount,
      shopCount: totals.shopCount,
      computedAt: Date.now(),
    };

    if (request.data?.persistQuote === true) {
      response.checkoutQuoteId = await persistCheckoutQuote(
        db,
        FieldValue,
        request.auth.uid,
        totals,
        items,
      );
    }

    return response;
  },
);

exports.createCheckoutOrders = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => createCheckoutOrdersHandler(request, buildCheckoutDeps()),
);

exports.createTravelOrder = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => createTravelOrderHandler(request, buildCheckoutDeps()),
);

exports.quoteTravelFare = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => quoteTravelFareHandler(request, buildCheckoutDeps()),
);

exports.createNationwideParcelOrders = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  async (request) => createNationwideParcelOrdersHandler(request, buildCheckoutDeps()),
);

exports.reverseGeocodeDeliveryLocation = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
    secrets: [GOOGLE_GEOCODING_API_KEY_SECRET],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนดึงที่อยู่');
    }

    const latitude = parseNumber(request.data?.latitude);
    const longitude = parseNumber(request.data?.longitude);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      throw new HttpsError('invalid-argument', 'พิกัดจัดส่งไม่ถูกต้อง');
    }

    const cacheId = geocodeCacheId(latitude, longitude);
    const cacheRef = db.collection('geocode_cache').doc(cacheId);
    const cacheSnapshot = await cacheRef.get();
    const cacheData = cacheSnapshot.data();
    const cacheTtlMs = 30 * 24 * 60 * 60 * 1000;
    const cachedAtMs = cacheData?.cachedAt?.toMillis?.() || 0;
    if (
      cacheSnapshot.exists &&
      cachedAtMs > 0 &&
      Date.now() - cachedAtMs < cacheTtlMs &&
      cacheData?.result
    ) {
      return {
        ...cacheData.result,
        cacheHit: true,
      };
    }

    const apiKey = readRequiredConfiguredSecret(
      GOOGLE_GEOCODING_API_KEY_SECRET,
      'GOOGLE_GEOCODING_API_KEY',
      'Google Geocoding',
    );
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('latlng', `${latitude},${longitude}`);
    url.searchParams.set('language', 'th');
    url.searchParams.set('region', 'th');
    url.searchParams.set('key', apiKey);

    let response;
    try {
      response = await fetch(url);
    } catch (error) {
      logger.error('reverseGeocodeDeliveryLocation network failed', {
        message: error instanceof Error ? error.message : String(error),
      });
      throw new HttpsError('unavailable', 'เชื่อมต่อ Google Geocoding ไม่สำเร็จ');
    }

    const payload = await response.json().catch(() => null);
    const status = String(payload?.status || '').trim();
    if (!response.ok || status !== 'OK') {
      logger.warn('reverseGeocodeDeliveryLocation google response not OK', {
        httpStatus: response.status,
        googleStatus: status,
        errorMessage: payload?.error_message,
      });
      throw new HttpsError(
        status === 'ZERO_RESULTS' ? 'not-found' : 'unavailable',
        status === 'ZERO_RESULTS'
          ? 'ไม่พบที่อยู่จากพิกัดนี้'
          : 'ดึงที่อยู่จาก Google ไม่สำเร็จ',
      );
    }

    const result = parseGoogleReverseGeocodeResult(payload, latitude, longitude);
    if (!result) {
      throw new HttpsError('not-found', 'ไม่พบที่อยู่จากพิกัดนี้');
    }

    await cacheRef.set(
      {
        latitude: Number(latitude.toFixed(7)),
        longitude: Number(longitude.toFixed(7)),
        result,
        cachedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return {
      ...result,
      cacheHit: false,
    };
  },
);

function parseGooglePlacesAutocompletePrediction(prediction) {
  if (!prediction || typeof prediction !== 'object') {
    return null;
  }

  const placeId = String(prediction.place_id || '').trim();
  if (!placeId) {
    return null;
  }

  const structured = prediction.structured_formatting || {};
  const mainText = String(structured.main_text || '').trim();
  const secondaryText = String(structured.secondary_text || '').trim();
  const description = String(prediction.description || '').trim();
  const primaryText = mainText || description;

  if (!primaryText) {
    return null;
  }

  return {
    placeId,
    primaryText,
    secondaryText,
    description: description || primaryText,
  };
}

function parseGooglePlacesDetailsResult(result, fallbackPlaceId) {
  if (!result || typeof result !== 'object') {
    return null;
  }

  const latitude = Number(result?.geometry?.location?.lat);
  const longitude = Number(result?.geometry?.location?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null;
  }

  const title = String(result.name || '').trim();
  if (!title) {
    return null;
  }

  const formattedAddress = String(result.formatted_address || '').trim();
  const placeId = String(result.place_id || fallbackPlaceId || '').trim();

  return {
    placeId,
    title,
    subtitle:
      formattedAddress && formattedAddress !== title ? formattedAddress : '',
    latitude,
    longitude,
  };
}

async function fetchGooglePlacesAutocomplete({
  apiKey,
  input,
  originLat,
  originLng,
}) {
  const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
  url.searchParams.set('input', input);
  url.searchParams.set('key', apiKey);
  url.searchParams.set('language', 'th');
  url.searchParams.set('components', 'country:th');

  if (
    Number.isFinite(originLat) &&
    Number.isFinite(originLng) &&
    originLat >= -90 &&
    originLat <= 90 &&
    originLng >= -180 &&
    originLng <= 180
  ) {
    url.searchParams.set('location', `${originLat},${originLng}`);
    url.searchParams.set('radius', '50000');
  }

  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    logger.error('fetchGooglePlacesAutocomplete network failed', {
      message: error instanceof Error ? error.message : String(error),
    });
    return {
      ok: false,
      status: 'NETWORK_ERROR',
      errorMessage: 'network failed',
    };
  }

  const payload = await response.json().catch(() => null);
  const status = String(payload?.status || '').trim();
  if (!response.ok) {
    return {
      ok: false,
      status: status || String(response.status),
      errorMessage: String(payload?.error_message || '').trim(),
    };
  }

  if (status === 'ZERO_RESULTS') {
    return { ok: true, suggestions: [] };
  }

  if (status !== 'OK') {
    return {
      ok: false,
      status: status || 'ERROR',
      errorMessage: String(payload?.error_message || '').trim(),
    };
  }

  const predictions = Array.isArray(payload?.predictions) ? payload.predictions : [];
  const suggestions = predictions
    .map(parseGooglePlacesAutocompletePrediction)
    .filter(Boolean);

  return { ok: true, suggestions };
}

async function fetchGooglePlaceDetails({ apiKey, placeId }) {
  const url = new URL('https://maps.googleapis.com/maps/api/place/details/json');
  url.searchParams.set('place_id', placeId);
  url.searchParams.set('fields', 'place_id,name,formatted_address,geometry');
  url.searchParams.set('language', 'th');
  url.searchParams.set('key', apiKey);

  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    logger.error('fetchGooglePlaceDetails network failed', {
      message: error instanceof Error ? error.message : String(error),
    });
    return {
      ok: false,
      status: 'NETWORK_ERROR',
      errorMessage: 'network failed',
    };
  }

  const payload = await response.json().catch(() => null);
  const status = String(payload?.status || '').trim();
  if (!response.ok || status !== 'OK') {
    return {
      ok: false,
      status: status || String(response.status),
      errorMessage: String(payload?.error_message || '').trim(),
    };
  }

  const parsed = parseGooglePlacesDetailsResult(payload?.result, placeId);
  if (!parsed) {
    return {
      ok: false,
      status: 'INVALID_RESPONSE',
      errorMessage: 'missing place details',
    };
  }

  return { ok: true, place: parsed };
}

exports.placesAutocomplete = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
    secrets: [GOOGLE_GEOCODING_API_KEY_SECRET],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนค้นหาสถานที่');
    }

    const input = String(request.data?.input || request.data?.query || '').trim();
    if (input.length < 2) {
      return { suggestions: [] };
    }

    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `places_autocomplete:${request.auth.uid}`,
      maxAttempts: 60,
      windowMs: 60 * 1000,
      message: 'ค้นหาบ่อยเกินไป กรุณารอสักครู่',
    });

    const originLat = parseNumber(request.data?.originLat ?? request.data?.originLatitude);
    const originLng = parseNumber(request.data?.originLng ?? request.data?.originLongitude);

    const apiKey = readRequiredConfiguredSecret(
      GOOGLE_GEOCODING_API_KEY_SECRET,
      'GOOGLE_GEOCODING_API_KEY',
      'Places Autocomplete',
    );

    const result = await fetchGooglePlacesAutocomplete({
      apiKey,
      input,
      originLat,
      originLng,
    });

    if (!result.ok) {
      throw new HttpsError(
        'unavailable',
        result.errorMessage || 'ค้นหาสถานที่จาก Google ไม่สำเร็จ',
      );
    }

    return { suggestions: result.suggestions };
  },
);

exports.placesResolvePlace = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
    secrets: [GOOGLE_GEOCODING_API_KEY_SECRET],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนเลือกสถานที่');
    }

    const placeId = String(request.data?.placeId || '').trim();
    if (!placeId) {
      throw new HttpsError('invalid-argument', 'ไม่พบ placeId');
    }

    await assertCallableRateLimit(db, admin, HttpsError, {
      key: `places_resolve:${request.auth.uid}`,
      maxAttempts: 60,
      windowMs: 60 * 1000,
      message: 'เลือกสถานที่บ่อยเกินไป กรุณารอสักครู่',
    });

    const apiKey = readRequiredConfiguredSecret(
      GOOGLE_GEOCODING_API_KEY_SECRET,
      'GOOGLE_GEOCODING_API_KEY',
      'Place Details',
    );

    const result = await fetchGooglePlaceDetails({ apiKey, placeId });
    if (!result.ok) {
      throw new HttpsError(
        'unavailable',
        result.errorMessage || 'ดึงรายละเอียดสถานที่จาก Google ไม่สำเร็จ',
      );
    }

    return result.place;
  },
);

exports.computeRouteMetrics = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
    secrets: [GOOGLE_GEOCODING_API_KEY_SECRET],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนคำนวณเส้นทาง');
    }

    const originLatitude = parseNumber(request.data?.originLatitude);
    const originLongitude = parseNumber(request.data?.originLongitude);
    const destinationLatitude = parseNumber(request.data?.destinationLatitude);
    const destinationLongitude = parseNumber(request.data?.destinationLongitude);

    if (
      !Number.isFinite(originLatitude) ||
      !Number.isFinite(originLongitude) ||
      !Number.isFinite(destinationLatitude) ||
      !Number.isFinite(destinationLongitude) ||
      originLatitude < -90 ||
      originLatitude > 90 ||
      destinationLatitude < -90 ||
      destinationLatitude > 90 ||
      originLongitude < -180 ||
      originLongitude > 180 ||
      destinationLongitude < -180 ||
      destinationLongitude > 180
    ) {
      throw new HttpsError('invalid-argument', 'พิกัดเส้นทางไม่ถูกต้อง');
    }

    const apiKey = readRequiredConfiguredSecret(
      GOOGLE_GEOCODING_API_KEY_SECRET,
      'GOOGLE_GEOCODING_API_KEY',
      'Google Directions',
    );

    const route = await fetchGoogleDrivingDirectionsRoute({
      apiKey,
      originLatitude,
      originLongitude,
      destinationLatitude,
      destinationLongitude,
      logger,
    });

    if (!route.ok) {
      throw new HttpsError(
        'unavailable',
        route.errorMessage || 'คำนวณเส้นทางจาก Google ไม่สำเร็จ',
      );
    }

    return {
      distanceMeters: route.distanceMeters,
      durationSeconds: route.durationSeconds,
      encodedPolyline: route.encodedPolyline,
      provider: route.provider,
    };
  },
);

exports.verifyOrderPaymentSlip = onCall(
  {
    region: DEFAULT_REGION,
    secrets: [SLIPOK_API_KEY_SECRET],
    enforceAppCheck: true,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนส่งสลิป');
    }

    const rawOrderIds = Array.isArray(request.data?.orderIds) ? request.data.orderIds : [];
    const orderIds = [...new Set(rawOrderIds.map((value) => String(value || '').trim()).filter(Boolean))];
    const storagePath = String(request.data?.storagePath || '').trim();
    const paymentGroupId = String(request.data?.paymentGroupId || '').trim();
    const fileName = String(request.data?.fileName || 'slip.jpg').trim() || 'slip.jpg';
    const contentType = String(request.data?.contentType || 'image/jpeg').trim() || 'image/jpeg';

    if (orderIds.length === 0) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ orderIds');
    }
    if (!storagePath) {
      throw new HttpsError('invalid-argument', 'กรุณาระบุ storagePath');
    }

    const snapshots = await Promise.all(
      orderIds.map((orderId) => db.collection('orders').doc(orderId).get()),
    );

    const missingOrder = snapshots.find((snapshot) => !snapshot.exists);
    if (missingOrder) {
      throw new HttpsError('not-found', 'ไม่พบข้อมูลออเดอร์สำหรับตรวจสลิป');
    }

    for (const snapshot of snapshots) {
      const data = snapshot.data() || {};
      if (String(data.customerId || '').trim() !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'คุณไม่มีสิทธิ์ส่งสลิปให้ออเดอร์นี้');
      }

      const expiresAt = data.paymentExpiresAt?.toMillis?.() || 0;
      if (expiresAt > 0 && Date.now() > expiresAt) {
        throw new HttpsError(
          'deadline-exceeded',
          'หมดเวลาชำระเงินแล้ว กรุณาสั่งซื้อใหม่',
        );
      }

      if (data.paymentStatus === 'verified' || data.paymentStatus === 'cash_on_delivery') {
        throw new HttpsError('failed-precondition', 'ออเดอร์นี้ชำระเงินแล้ว');
      }
    }

    const expectedCombinedAmount = snapshots.reduce((sum, snapshot) => {
      const data = snapshot.data() || {};
      return sum + parseNumber(data.grandTotal);
    }, 0);
    const paymentCollectionSettings = await getPaymentCollectionSettings();

    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError('not-found', 'ไม่พบไฟล์สลิปใน Firebase Storage');
    }

    let verificationStatus = 'error';
    let verificationMessage = 'ส่งสลิปไปตรวจไม่สำเร็จ';
    let responseCode = 0;
    let providerPayload = null;
    let verifiedSlipAmount = null;
    let providerRawText = '';

    try {
      const [buffer] = await file.download();
      const apiKey = readRequiredConfiguredSecret(
        SLIPOK_API_KEY_SECRET,
        'SLIPOK_API_KEY',
        'ระบบตรวจสลิป Slip OK',
      );

      const formData = new FormData();
      formData.append('files', new Blob([buffer], { type: contentType }), fileName);
      formData.append('log', 'true');
      formData.append('amount', expectedCombinedAmount.toString());

      const slipResponse = await fetch(SLIPOK_ENDPOINT, {
        method: 'POST',
        headers: {
          'x-authorization': apiKey,
        },
        body: formData,
      });

      responseCode = slipResponse.status;
      providerRawText = await slipResponse.text();
      try {
        providerPayload = providerRawText ? JSON.parse(providerRawText) : null;
      } catch (_) {
        providerPayload = { raw: providerRawText };
      }

      const requestSucceeded = providerPayload?.success === true;
      const dataSucceeded = providerPayload?.data?.success === true;
      verifiedSlipAmount = parseNumber(providerPayload?.data?.amount);
      const hasMatchingAmount = amountsMatch(verifiedSlipAmount, expectedCombinedAmount);
      const receiverValidation = validateSlipReceiver(providerPayload, paymentCollectionSettings);
      const hasMatchingReceiver = receiverValidation.matched;

      if (
        slipResponse.ok &&
        requestSucceeded &&
        dataSucceeded &&
        hasMatchingAmount &&
        hasMatchingReceiver
      ) {
        verificationStatus = 'verified';
        verificationMessage = buildSlipVerificationMessage(
          verificationStatus,
          providerPayload,
          'ตรวจสอบสลิปสำเร็จ',
        );
      } else if (slipResponse.ok && requestSucceeded && dataSucceeded && !hasMatchingAmount) {
        verificationStatus = 'failed';
        providerPayload = {
          ...(providerPayload && typeof providerPayload === 'object' ? providerPayload : {}),
          code: Number(providerPayload?.code) || 1013,
          data: {
            ...(providerPayload?.data && typeof providerPayload.data === 'object' ? providerPayload.data : {}),
            amount: Number.isFinite(verifiedSlipAmount) ? verifiedSlipAmount : providerPayload?.data?.amount,
            expectedAmount: expectedCombinedAmount,
            message:
              providerPayload?.data?.message || 'ยอดที่ส่งมาไม่ตรงกับยอดสลิป',
          },
          message: providerPayload?.message || 'ยอดที่ส่งมาไม่ตรงกับยอดสลิป',
        };
        verificationMessage = buildSlipVerificationMessage(
          verificationStatus,
          providerPayload,
          'ยอดเงินในสลิปไม่ตรงกับยอดที่ต้องชำระ',
        );
      } else if (slipResponse.ok && requestSucceeded && dataSucceeded && !hasMatchingReceiver) {
        verificationStatus = 'failed';
        providerPayload = {
          ...(providerPayload && typeof providerPayload === 'object' ? providerPayload : {}),
          code: Number(providerPayload?.code) || 1014,
          data: {
            ...(providerPayload?.data && typeof providerPayload.data === 'object' ? providerPayload.data : {}),
            receiverValidation,
            expectedRecipientDisplayName: paymentCollectionSettings.recipientDisplayName,
            expectedReceiverTargets: buildExpectedReceiverTargets(paymentCollectionSettings),
            message:
              providerPayload?.data?.message || 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
          },
          message: providerPayload?.message || 'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
        };
        verificationMessage = buildSlipVerificationMessage(
          verificationStatus,
          providerPayload,
          'บัญชีผู้รับในสลิปไม่ตรงกับบัญชีร้าน',
        );
      } else {
        verificationStatus = 'failed';
        verificationMessage = buildSlipVerificationMessage(
          verificationStatus,
          providerPayload,
          `Slip OK responded with status ${slipResponse.status}`,
        );
      }
    } catch (error) {
      verificationStatus = 'error';
      providerPayload = {
        message: error instanceof Error ? error.message : String(error),
      };
      verificationMessage = buildSlipVerificationMessage(
        verificationStatus,
        providerPayload,
        'ส่งสลิปไปตรวจสอบไม่สำเร็จ',
      );
      logger.error('verifyOrderPaymentSlip failed', {
        orderIds,
        paymentGroupId,
        storagePath,
        message: verificationMessage,
      });
    }

    const slipOkFeedbackId = await writeSlipOkFeedbackLog({
      feedbackId: paymentGroupId,
      customerUid: request.auth.uid,
      orderIds,
      paymentGroupId,
      storagePath,
      fileName,
      contentType,
      expectedCombinedAmount,
      verifiedSlipAmount,
      verificationStatus,
      verificationMessage,
      responseCode,
      providerPayload,
      providerRawText,
    });

    for (const snapshot of snapshots) {
      const orderId = snapshot.id;
      const orderData = snapshot.data() || {};
      const orderRef = snapshot.ref;
      const existingDriverId = String(orderData.driverId || '').trim();
      const matchedRiderId = String(orderData?.riderSearch?.matchedRiderId || '').trim();
      const resolvedDriverId = existingDriverId || matchedRiderId;
      const hasAssignedRider = resolvedDriverId.isNotEmpty;
      const nextOrderStatus =
        verificationStatus === 'verified'
          ? (hasAssignedRider ? 'pending' : 'awaiting_rider')
          : verificationStatus === 'failed'
            ? 'payment_slip_rejected'
            : 'payment_slip_error';
      const nextOrderStatusLabel =
        verificationStatus === 'verified'
          ? (hasAssignedRider ? 'pending_customer_confirmation' : 'awaiting_nearest_rider')
          : verificationStatus === 'failed'
            ? 'awaiting_payment_slip_retry'
            : 'payment_slip_error';

      await orderRef.set(
        {
          status: nextOrderStatus,
          statusLabel: nextOrderStatusLabel,
          paymentStatus:
            verificationStatus === 'verified'
              ? 'verified'
              : verificationStatus === 'failed'
                ? 'slip_verification_failed'
                : 'slip_verification_error',
          paymentStatusLabel:
            verificationStatus === 'verified'
              ? 'ชำระเงินแล้ว'
              : verificationStatus === 'failed'
                ? 'สลิปไม่ผ่าน'
                : 'ส่งตรวจสลิปไม่สำเร็จ',
          paymentVerification: {
            provider: 'slipok',
            providerLabel: 'Slip OK',
            feedbackId: slipOkFeedbackId,
            paymentGroupId,
            expectedCombinedAmount,
            verifiedSlipAmount,
            status: verificationStatus,
            statusLabel:
              verificationStatus === 'verified'
                ? 'ตรวจสอบสลิปผ่าน'
                : verificationStatus === 'failed'
                  ? 'ตรวจสอบสลิปไม่ผ่าน'
                  : 'ส่งตรวจสลิปไม่สำเร็จ',
            message: verificationMessage,
            checkedAt: FieldValue.serverTimestamp(),
            responseCode,
            apiEndpoint: SLIPOK_ENDPOINT,
            response: providerPayload,
          },
          driverId: verificationStatus === 'verified'
            ? (hasAssignedRider ? resolvedDriverId : null)
            : null,
          driverName: null,
          driverPhone: null,
          assignedRiderAt:
            verificationStatus === 'verified' && hasAssignedRider
              ? (orderData.assignedRiderAt || FieldValue.serverTimestamp())
              : null,
          riderNotifyReady:
            verificationStatus === 'verified'
              ? hasAssignedRider
              : false,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await orderRef.collection('timeline').add({
        event:
          verificationStatus === 'verified'
            ? 'payment_slip_verified'
            : verificationStatus === 'failed'
              ? 'payment_slip_rejected'
              : 'payment_slip_error',
        eventLabel:
          verificationStatus === 'verified'
            ? 'ระบบตรวจสลิปผ่านแล้ว'
            : verificationStatus === 'failed'
              ? 'ระบบตรวจสลิปไม่ผ่าน'
              : 'ระบบส่งสลิปไปตรวจไม่สำเร็จ',
        orderId,
        paymentGroupId,
        actorRole: 'system',
        actorId: 'verifyOrderPaymentSlip',
        message: verificationMessage,
        timestamp: FieldValue.serverTimestamp(),
      });

      if (
        verificationStatus === 'verified' &&
        hasAssignedRider
      ) {
        try {
          await db.collection('app_notifications').add({
            targetApp: 'van3',
            recipientUid: resolvedDriverId,
            orderId,
            title: 'ชำระเงินแล้ว มีออเดอร์ใหม่',
            body: String(orderData.orderCode || '').trim().isNotEmpty
              ? `ออเดอร์ ${String(orderData.orderCode || '').trim()} ชำระเงินแล้ว`
              : 'มีออเดอร์ที่ชำระเงินแล้ว',
            read: false,
            createdAt: FieldValue.serverTimestamp(),
            source: 'van2_customer',
            sourceApp: 'van2_customer',
            action: 'order_payment_verified',
            riderNotifyReady: true,
          });
        } catch (error) {
          logger.warn('Failed to notify rider after slip verification', {
            orderId,
            driverId: resolvedDriverId,
            message: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    return {
      success: verificationStatus === 'verified',
      status: verificationStatus,
      message: verificationMessage,
      expectedCombinedAmount,
      orderIds,
    };
  },
);

async function resolveRecipientFcmToken(targetApp, recipientUid) {
  if (!recipientUid) return null;

  const primaryCollection = targetApp === 'van2'
    ? 'customer_users'
    : (targetApp === 'van3' ? 'riders' : 'users');
  try {
    const primaryDoc = await db.collection(primaryCollection).doc(recipientUid).get();
    const token = String(primaryDoc.data()?.fcmToken || '').trim();
    if (token) return token;
  } catch (_) {
    // Ignore and try fallbacks.
  }

  if (targetApp !== 'van2') {
    try {
      const usersDoc = await db.collection('users').doc(recipientUid).get();
      const usersToken = String(usersDoc.data()?.fcmToken || '').trim();
      if (usersToken) return usersToken;
    } catch (_) {
      // Ignore and try registration collections.
    }
  }

  for (const collection of REGISTRATION_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(recipientUid).get();
      const token = String(doc.data()?.shopFCMToken || '').trim();
      if (token) return token;
    } catch (_) {
      // Try next collection.
    }
  }

  return null;
}

async function resolveAnyRecipientFcmToken(recipientUid) {
  if (!recipientUid) return null;

  for (const collection of CUSTOMER_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(recipientUid).get();
      const token = String(doc.data()?.fcmToken || '').trim();
      if (token) return token;
    } catch (_) {
      // Try next collection.
    }
  }

  for (const collection of RIDER_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(recipientUid).get();
      const token = String(doc.data()?.fcmToken || '').trim();
      if (token) return token;
    } catch (_) {
      // Try next collection.
    }
  }

  for (const collection of REGISTRATION_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(recipientUid).get();
      const token = String(doc.data()?.shopFCMToken || '').trim();
      if (token) return token;
    } catch (_) {
      // Try next collection.
    }
  }

  try {
    const presenceDoc = await db.collection('admin_presence').doc(recipientUid).get();
    const adminToken = String(presenceDoc.data()?.fcmToken || '').trim();
    if (adminToken) return adminToken;
  } catch (_) {
    // Ignore.
  }

  return null;
}

function isRetryableFcmError(error) {
  const code = String(error?.code || error?.errorInfo?.code || '').trim();
  return code === 'messaging/unavailable'
    || code === 'messaging/internal-error'
    || code === 'messaging/server-unavailable'
    || code === 'messaging/unknown-error'
    || code === 'deadline-exceeded'
    || code === 'unavailable';
}

async function sendFcmWithRetry(message, maxAttempts = 3) {
  let lastError = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await admin.messaging().send(message);
    } catch (error) {
      lastError = error;
      if (!isRetryableFcmError(error) || attempt >= maxAttempts) {
        throw error;
      }
      await new Promise((resolve) => {
        setTimeout(resolve, 250 * (2 ** (attempt - 1)));
      });
    }
  }
  throw lastError;
}

function activeCallInviteRef(callerId, calleeId) {
  return db.collection(ACTIVE_CALL_INVITES_COLLECTION).doc(`${callerId}__${calleeId}`);
}

function maskSecret(secret, visible = 4) {
  if (!secret) return null;
  if (secret.length <= visible * 2) {
    return '*'.repeat(secret.length);
  }
  return `${secret.slice(0, visible)}***${secret.slice(-visible)}`;
}

function summarizeAgoraConfig() {
  const { appId, appCertificate, tokenTtl } = resolveAgoraConfig();
  return {
    appIdMasked: maskSecret(appId, 6),
    appIdLength: appId ? appId.length : 0,
    certificateLength: appCertificate ? appCertificate.length : 0,
    tokenTtl,
  };
}

function timestampToMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (typeof value._seconds === 'number') {
    return value._seconds * 1000;
  }
  return null;
}

function readDisplayName(data, fallback = 'ผู้ใช้ใหม่') {
  const candidates = [data?.displayName, data?.shopName, data?.name];
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim()) {
      return candidate.trim();
    }
  }
  return fallback;
}

function readPhotoUrl(data) {
  const candidates = [
    data?.photoUrl,
    data?.shopImageUrl,
    data?.imageUrl,
    data?.logoUrl,
    data?.profileImageUrl,
  ];
  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim()) {
      return candidate.trim();
    }
  }
  return null;
}

function normalizePhone(raw = '') {
  let clean = String(raw).replace(/[^0-9+]/g, '');
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

function buildProfileFromSource(data = {}, sourceCollection = '') {
  return {
    displayName: readDisplayName(data),
    photoUrl: readPhotoUrl(data),
    serviceType: String(data.serviceType || sourceCollection || '').trim(),
    phoneNumber: normalizePhone(data.phoneNumber || data.phone || ''),
    profileCompleted: data.profileCompleted === true || data.isProfileCompleted === true,
  };
}

async function getOrCreateUserProfile(uid) {
  for (const collection of PROFILE_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(uid).get();
      if (!doc.exists) {
        continue;
      }
      const normalized = buildProfileFromSource(doc.data() || {}, collection);
      await db.collection('users').doc(uid).set(
        {
          ...normalized,
          updatedAt: FieldValue.serverTimestamp(),
          sourceCollection: collection,
        },
        { merge: true },
      );
      return normalized;
    } catch (_) {
      // Try next collection.
    }
  }

  return null;
}

async function getProfileFromFriendDoc(ownerId, friendId) {
  for (const ownerCollection of CUSTOMER_COLLECTIONS) {
    try {
      const doc = await db
        .collection(ownerCollection)
        .doc(ownerId)
        .collection('friends')
        .doc(friendId)
        .get();
      if (!doc.exists) {
        continue;
      }
      const data = doc.data() || {};
      await db.collection('users').doc(friendId).set(
        {
          ...data,
          uid: friendId,
          updatedAt: FieldValue.serverTimestamp(),
          sourceCollection: `${ownerCollection}/friends`,
        },
        { merge: true },
      );
      return data;
    } catch (_) {
      // Try next collection.
    }
  }

  return null;
}

function resolveAgoraConfig() {
  const appId = (AGORA_APP_ID_SECRET.value() || process.env.AGORA_APP_ID || '').trim();
  const appCertificate = (AGORA_APP_CERT_SECRET.value() || process.env.AGORA_APP_CERTIFICATE || '').trim();
  const ttlRaw = (AGORA_TTL_SECRET.value() || process.env.AGORA_APP_TTL_SECONDS || '3600').trim();
  let tokenTtl = Number.parseInt(ttlRaw, 10);
  if (!Number.isFinite(tokenTtl) || tokenTtl <= 0) {
    tokenTtl = 3600;
  }
  return { appId, appCertificate, tokenTtl };
}

async function buildAgoraToken(channelId, uid = 0) {
  const { appId, appCertificate, tokenTtl } = resolveAgoraConfig();
  if (!appId || !appCertificate) {
    throw new HttpsError(
      'failed-precondition',
      'Agora credentials are not configured. Set secrets AGORA_APP_ID and AGORA_APP_CERTIFICATE.',
    );
  }

  const privilegeExpiredTs = Math.floor(Date.now() / 1000) + tokenTtl;
  try {
    logger.info('Building Agora token', {
      channelId,
      uid,
      privilegeExpiredTs,
      ...summarizeAgoraConfig(),
    });
    return RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelId,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpiredTs,
    );
  } catch (error) {
    logger.error('Failed to build Agora token', { channelId, message: error instanceof Error ? error.message : String(error) });
    throw new HttpsError('internal', 'Unable to create Agora token');
  }
}

async function resolveOrCreateActiveCallInvite({
  callerId,
  calleeId,
  isVideo,
  callType,
  calleeProfile,
}) {
  const inviteRef = activeCallInviteRef(callerId, calleeId);
  const inviteExpiry = admin.firestore.Timestamp.fromMillis(Date.now() + CALL_TTL_MS);
  const { appId } = resolveAgoraConfig();
  let invite = null;
  let created = false;

  await db.runTransaction(async (transaction) => {
    const now = Date.now();
    const inviteSnap = await transaction.get(inviteRef);

    if (inviteSnap.exists) {
      const existingInvite = inviteSnap.data() || {};
      const expiresAtMillis = timestampToMillis(existingInvite.expiresAt);
      if (existingInvite.channelId && expiresAtMillis != null && expiresAtMillis > now) {
        invite = existingInvite;
        return;
      }
      transaction.delete(inviteRef);
    }

    const channelId = `call_${calleeId}_${Date.now()}`;
    const token = await buildAgoraToken(channelId);
    invite = {
      channelId,
      token,
      appId,
      callerId,
      calleeId,
      isVideo,
      callType,
      calleeProfile: {
        displayName: calleeProfile.displayName || 'ผู้ใช้',
        photoUrl: calleeProfile.photoUrl || null,
        phoneNumber: calleeProfile.phoneNumber || null,
      },
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: inviteExpiry,
    };
    transaction.set(inviteRef, invite);
    created = true;
  });

  return { invite, created };
}

async function clearActiveCallInvite(callerId, calleeId) {
  if (!callerId || !calleeId) {
    return;
  }
  try {
    await activeCallInviteRef(callerId, calleeId).delete();
  } catch (error) {
    logger.warn('Failed to clear active call invite', {
      callerId,
      calleeId,
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

exports.normalizeVan2SlipOrders = onDocumentCreated(
  {
    region: DEFAULT_REGION,
    document: 'orders/{orderId}',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      logger.info('normalizeVan2SlipOrders skipped: missing data', {
        orderId: event.params.orderId,
      });
      return;
    }

    const sourceApp = String(data.sourceApp || '').trim();
    const paymentMethod = String(data.paymentMethod || '').trim();
    const paymentStatus = String(data.paymentStatus || '').trim();
    const riderNotifyReady = data.riderNotifyReady === true;
    const currentStatus = String(data.status || '').trim();

    const shouldHoldForSlipVerification =
      sourceApp === 'van2_customer' &&
      paymentMethod === 'promptpay_qr' &&
      paymentStatus === 'awaiting_slip_review' &&
      riderNotifyReady !== true &&
      currentStatus !== 'awaiting_payment_slip_review';

    logger.info('normalizeVan2SlipOrders evaluated order', {
      orderId: event.params.orderId,
      sourceApp,
      paymentMethod,
      paymentStatus,
      riderNotifyReady,
      currentStatus,
      shouldHoldForSlipVerification,
    });

    if (!shouldHoldForSlipVerification) {
      return;
    }

    await event.data.ref.set(
      {
        status: 'awaiting_payment_slip_review',
        statusLabel: 'awaiting_payment_slip_review',
        riderNotifyReady: false,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    logger.info('normalizeVan2SlipOrders held order for verification', {
      orderId: event.params.orderId,
    });

    try {
      await event.data.ref.collection('timeline').add({
        event: 'order_held_for_payment_verification',
        eventLabel: 'ระบบกักออเดอร์ไว้จนกว่าสลิปจะตรวจผ่าน',
        orderId: event.params.orderId,
        actorRole: 'system',
        actorId: 'normalizeVan2SlipOrders',
        timestamp: FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Do not fail the main normalization if timeline logging fails.
    }
  },
);

function normalizeOrderStatus(value) {
  return String(value || '').trim().toLowerCase();
}

function readOrderProductLines(data) {
  const rawProducts = data?.products ?? data?.items;
  if (!Array.isArray(rawProducts)) {
    return [];
  }

  const lines = [];
  for (const rawProduct of rawProducts) {
    if (!rawProduct || typeof rawProduct !== 'object') {
      continue;
    }

    const productId = String(
      rawProduct.productId ||
        rawProduct.product_id ||
        rawProduct.id ||
        rawProduct.docId ||
        rawProduct.documentId ||
        '',
    ).trim();
    if (!productId) {
      continue;
    }

    const quantityRaw = Number(rawProduct.quantity);
    const quantity = Number.isFinite(quantityRaw)
      ? Math.max(1, Math.min(999, Math.floor(quantityRaw)))
      : 1;
    lines.push({ productId, quantity });
  }

  return lines;
}

exports.applyProductStatsOnDelivered = onDocumentUpdated(
  {
    region: DEFAULT_REGION,
    document: 'orders/{orderId}',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) {
      return;
    }

    const beforeStatus = normalizeOrderStatus(before.status);
    const afterStatus = normalizeOrderStatus(after.status);
    if (beforeStatus === afterStatus || afterStatus !== 'delivered') {
      return;
    }
    if (after.statsApplied === true) {
      return;
    }

    const lines = readOrderProductLines(after);
    if (lines.length === 0) {
      logger.info('applyProductStatsOnDelivered skipped: no product lines', {
        orderId: event.params.orderId,
      });
      return;
    }

    const batch = db.batch();
    for (const line of lines) {
      batch.set(
        db.collection('product_stats').doc(line.productId),
        {
          soldCount: FieldValue.increment(line.quantity),
          lastSoldAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    batch.set(
      event.data.after.ref,
      {
        statsApplied: true,
        statsAppliedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await batch.commit();

    logger.info('applyProductStatsOnDelivered updated product stats', {
      orderId: event.params.orderId,
      lineCount: lines.length,
    });
  },
);

async function refreshReviewStats({
  collection,
  statsCollection,
  targetField,
  targetId,
}) {
  const id = String(targetId || '').trim();
  if (!id) {
    return;
  }

  const snapshot = await db
    .collection(collection)
    .where(targetField, '==', id)
    .where('status', '==', 'visible')
    .get();

  let ratingCount = 0;
  let ratingSum = 0;
  let lastReviewAt = null;
  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const rating = Number(data.rating);
    if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
      return;
    }
    ratingCount += 1;
    ratingSum += rating;
    const createdAt = data.updatedAt || data.createdAt;
    if (createdAt && typeof createdAt.toMillis === 'function') {
      if (!lastReviewAt || createdAt.toMillis() > lastReviewAt.toMillis()) {
        lastReviewAt = createdAt;
      }
    }
  });

  const ratingAverage = ratingCount > 0
    ? Math.round((ratingSum / ratingCount) * 10) / 10
    : 0;

  await db.collection(statsCollection).doc(id).set(
    {
      [targetField]: id,
      ratingCount,
      ratingSum,
      ratingAverage,
      lastReviewAt,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

exports.onProductReviewWrite = onDocumentWritten(
  {
    region: DEFAULT_REGION,
    document: 'product_reviews/{reviewId}',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const productIds = new Set();
    if (before?.productId) productIds.add(String(before.productId).trim());
    if (after?.productId) productIds.add(String(after.productId).trim());

    await Promise.all([...productIds].filter(Boolean).map((productId) =>
      refreshReviewStats({
        collection: 'product_reviews',
        statsCollection: 'product_review_stats',
        targetField: 'productId',
        targetId: productId,
      })));
  },
);

exports.onShopReviewWrite = onDocumentWritten(
  {
    region: DEFAULT_REGION,
    document: 'shop_reviews/{reviewId}',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const shopIds = new Set();
    if (before?.shopId) shopIds.add(String(before.shopId).trim());
    if (after?.shopId) shopIds.add(String(after.shopId).trim());

    await Promise.all([...shopIds].filter(Boolean).map((shopId) =>
      refreshReviewStats({
        collection: 'shop_reviews',
        statsCollection: 'shop_review_stats',
        targetField: 'shopId',
        targetId: shopId,
      })));
  },
);

exports.pushAppNotification = onDocumentCreated(
  {
    region: DEFAULT_REGION,
    document: 'app_notifications/{notificationId}',
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) {
      return;
    }

    const notificationId = event.params.notificationId;
    const targetApp = String(data.targetApp || '').trim();
    const recipientUid = String(data.recipientUid || '').trim();
    const title = String(data.title || 'แจ้งเตือนใหม่').trim();
    const body = String(data.body || '').trim();
    const orderId = String(data.orderId || '').trim();
    const action = String(data.action || '').trim();
    const sourceApp = String(data.sourceApp || '').trim();
    const customerConfirmed = data.customerConfirmed === true ? 'true' : 'false';
    const riderNotifyReady = data.riderNotifyReady === true ? 'true' : 'false';
    const senderId = String(data.senderId || '').trim();
    const senderName = String(data.senderName || title || 'ข้อความใหม่').trim();
    const chatId = String(data.chatId || '').trim();
    const chatMessage = String(data.message || body || '').trim();

    if (!recipientUid) {
      await event.data.ref.set(
        {
          deliveryStatus: 'failed',
          deliveryError: 'missing_recipient_uid',
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const token = await resolveRecipientFcmToken(targetApp, recipientUid)
      || await resolveAnyRecipientFcmToken(recipientUid);
    if (!token) {
      await event.data.ref.set(
        {
          deliveryStatus: 'no_token',
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const isChatNotification = action === 'chat_message';
    const isVan1UrgentOrderAlert =
      targetApp === 'van1' &&
      Boolean(orderId) &&
      action === 'order_accepted' &&
      !isChatNotification;
    const isVan3UrgentOrderAlert =
      targetApp === 'van3' &&
      Boolean(orderId) &&
      customerConfirmed === 'true' &&
      riderNotifyReady === 'true' &&
      !isChatNotification &&
      action !== 'admin_announcement';
    const isVan3LightStatusAlert =
      targetApp === 'van3' &&
      (action === 'shop_accepted_order' ||
        action === 'shop_rejected_order' ||
        action === 'payout_pending' ||
        action === 'payout_paid');
    const isVan1LightPayoutAlert =
      targetApp === 'van1' &&
      (action === 'payout_pending' || action === 'payout_paid');
    const isDataOnlyUrgentAlert = isVan1UrgentOrderAlert || isVan3UrgentOrderAlert;
    const includeNotificationPayload = !isChatNotification && !isDataOnlyUrgentAlert;
    const androidChannelId =
      action === 'admin_announcement' && targetApp === 'van3'
        ? 'rider_announcements'
        : isVan3LightStatusAlert
          ? 'rider_status_updates'
          : isVan1LightPayoutAlert
            ? 'order_channel'
            : targetApp === 'van3'
              ? 'rider_jobs_urgent_sound'
              : 'order_channel';
    const message = {
      token,
      ...(includeNotificationPayload
        ? {
            notification: {
              title,
              body: body || title,
            },
          }
        : {}),
      data: isChatNotification
        ? {
            type: 'chat',
            notificationId,
            targetApp,
            recipientUid,
            chatId,
            orderId,
            action,
            sourceApp,
            senderId,
            senderName,
            message: chatMessage,
            title: senderName,
            body: chatMessage,
          }
        : {
            type: 'app_notification',
            notificationId,
            targetApp,
            recipientUid,
            orderId,
            action,
            sourceApp,
            customerConfirmed,
            riderNotifyReady,
            title,
            body,
          },
      android: {
        priority: 'high',
        ...(isDataOnlyUrgentAlert ? { ttl: VAN3_ORDER_ALERT_TTL_MS } : {}),
        ...(includeNotificationPayload
          ? {
              notification: {
                channelId: androidChannelId,
                priority: 'HIGH',
                defaultSound: true,
                defaultVibrateTimings: true,
              },
            }
          : {}),
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: isChatNotification || isDataOnlyUrgentAlert
            ? {
                sound: 'default',
                contentAvailable: true,
              }
            : {
                alert: {
                  title,
                  body: body || title,
                },
                sound: 'default',
              },
        },
      },
    };

    try {
      const responseId = await sendFcmWithRetry(message);
      await event.data.ref.set(
        {
          deliveryStatus: 'sent',
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
          fcmMessageId: responseId,
        },
        { merge: true },
      );
    } catch (error) {
      logger.error('pushAppNotification failed', {
        notificationId,
        targetApp,
        recipientUid,
        message: error instanceof Error ? error.message : String(error),
      });
      await event.data.ref.set(
        {
          deliveryStatus: 'failed',
          deliveredAt: admin.firestore.FieldValue.serverTimestamp(),
          deliveryError: error instanceof Error ? error.message : String(error),
        },
        { merge: true },
      );
    }
  },
);

const ANNOUNCEMENT_CONTACT_EMAIL_FIELDS = [
  'email',
  'contactEmail',
  'contact_email',
  'shopEmail',
  'registrationEmail',
  'customerEmail',
];

// Registration/profile docs first — contact email from forms beats Auth pseudo emails.
const ANNOUNCEMENT_EMAIL_PROFILE_COLLECTIONS = [
  ...REGISTRATION_COLLECTIONS,
  'rider_registrations',
  'riders',
  'public_shops',
  'customer_users',
  'users',
];

const PSEUDO_EMAIL_SUFFIXES = ['@phone.vanmerchant.app'];

function isPseudoOrInternalEmail(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes('@')) {
    return true;
  }
  if (PSEUDO_EMAIL_SUFFIXES.some((suffix) => normalized.endsWith(suffix))) {
    return true;
  }
  const localPart = normalized.split('@')[0] || '';
  if (/^\d{9,15}$/.test(localPart)) {
    return true;
  }
  return false;
}

function pickContactEmailFromData(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }

  for (const field of ANNOUNCEMENT_CONTACT_EMAIL_FIELDS) {
    const candidate = normalizeEmail(data[field]);
    if (candidate.includes('@') && !isPseudoOrInternalEmail(candidate)) {
      return candidate;
    }
  }

  if (data.customerSnapshot && typeof data.customerSnapshot === 'object') {
    return pickContactEmailFromData(data.customerSnapshot);
  }

  return null;
}

function buildAnnouncementEmailHtml(title, body) {
  const safeTitle = String(title || 'ประกาศจาก Van Market')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
  const safeBody = String(body || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\n/g, '<br/>');

  return `
    <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #1f2937; max-width: 640px;">
      <h2 style="color: #ea580c; margin-bottom: 12px;">${safeTitle}</h2>
      <div style="margin: 16px 0;">${safeBody}</div>
      <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;" />
      <p style="font-size: 12px; color: #6b7280;">
        อีเมลนี้ส่งจากระบบ Van Market สำหรับแจ้งข้อมูลทางการเงินและประกาศสำคัญ
      </p>
    </div>
  `;
}

async function resolveProfileEmail(uid) {
  if (!uid) {
    return null;
  }

  for (const collection of ANNOUNCEMENT_EMAIL_PROFILE_COLLECTIONS) {
    try {
      const doc = await db.collection(collection).doc(uid).get();
      if (!doc.exists) {
        continue;
      }
      const email = pickContactEmailFromData(doc.data());
      if (email) {
        return email;
      }
    } catch (_) {
      // Try next collection.
    }
  }

  return null;
}

async function resolveAuthEmail(uid) {
  if (!uid) {
    return null;
  }

  try {
    const user = await admin.auth().getUser(uid);
    const email = normalizeEmail(user.email);
    if (email.includes('@') && !isPseudoOrInternalEmail(email)) {
      return email;
    }
    return null;
  } catch (_) {
    return null;
  }
}

async function resolveAnnouncementRecipientEmail(uid) {
  return (await resolveProfileEmail(uid)) || (await resolveAuthEmail(uid));
}

async function fetchAnnouncementRecipientUids(targetApp) {
  switch (targetApp) {
    case 'van1': {
      const snapshot = await db.collection('users').get();
      return snapshot.docs
        .filter((doc) => doc.data()?.isAdmin !== true)
        .map((doc) => doc.id)
        .filter((uid) => uid.trim().length > 0);
    }
    case 'van2': {
      const snapshot = await db.collection('customer_users').get();
      return snapshot.docs
        .map((doc) => doc.id)
        .filter((uid) => uid.trim().length > 0);
    }
    case 'van3': {
      const snapshot = await db.collection('riders').get();
      return snapshot.docs
        .filter((doc) => doc.data()?.registrationStatus === 'approved')
        .map((doc) => doc.id)
        .filter((uid) => uid.trim().length > 0);
    }
    default:
      return [];
  }
}

async function sendAnnouncementEmailBatch({
  transport,
  from,
  title,
  body,
  recipients,
}) {
  let sentCount = 0;
  let failedCount = 0;
  let skippedNoAddress = 0;
  const seenEmails = new Set();

  for (const recipientUid of recipients) {
    const email = await resolveAnnouncementRecipientEmail(recipientUid);
    if (!email || seenEmails.has(email)) {
      skippedNoAddress += 1;
      continue;
    }
    seenEmails.add(email);

    try {
      await transport.sendMail({
        from,
        to: email,
        subject: `[Van Market] ${title}`,
        text: `${title}\n\n${body}`,
        html: buildAnnouncementEmailHtml(title, body),
      });
      sentCount += 1;
    } catch (error) {
      failedCount += 1;
      logger.warn('sendAnnouncementEmails recipient failed', {
        recipientUid,
        email,
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return {
    sentCount,
    failedCount,
    skippedNoAddress,
    uniqueRecipientCount: seenEmails.size,
  };
}

exports.sendAnnouncementEmails = onDocumentCreated(
  {
    region: DEFAULT_REGION,
    document: 'platform_announcements/{announcementId}',
    secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM],
  },
  async (event) => {
    const data = event.data?.data();
    if (!data || data.sendEmail !== true) {
      return;
    }

    const announcementId = event.params.announcementId;
    const title = String(data.title || 'ประกาศจาก Van Market').trim();
    const body = String(data.body || '').trim();
    const targetApps = Array.isArray(data.targetApps)
      ? data.targetApps.map((item) => String(item || '').trim()).filter(Boolean)
      : [];

    if (!title || !body || targetApps.length === 0) {
      await event.data.ref.set(
        {
          emailDeliveryStatus: 'failed',
          emailDeliveryError: 'missing_title_body_or_targets',
          emailProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    await event.data.ref.set(
      {
        emailDeliveryStatus: 'in_progress',
        emailProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const recipientsByApp = {};
    let totalRecipientUids = 0;
    for (const targetApp of targetApps) {
      const uids = await fetchAnnouncementRecipientUids(targetApp);
      recipientsByApp[targetApp] = uids;
      totalRecipientUids += uids.length;
    }

    if (totalRecipientUids === 0) {
      await event.data.ref.set(
        {
          emailDeliveryStatus: 'skipped',
          emailDeliveryError: 'no_recipients',
          emailRecipientCount: 0,
          emailSentCount: 0,
          emailFailedCount: 0,
          emailSkippedNoAddress: 0,
          emailProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    let transport;
    let from;
    try {
      transport = buildTransport();
      from = readRequiredSecret(SMTP_FROM, 'SMTP_FROM');
    } catch (error) {
      logger.error('sendAnnouncementEmails SMTP unavailable', {
        announcementId,
        message: error instanceof Error ? error.message : String(error),
      });
      await event.data.ref.set(
        {
          emailDeliveryStatus: 'failed',
          emailDeliveryError: 'smtp_unavailable',
          emailRecipientCount: totalRecipientUids,
          emailProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const allUids = [...new Set(Object.values(recipientsByApp).flat())];
    const stats = await sendAnnouncementEmailBatch({
      transport,
      from,
      title,
      body,
      recipients: allUids,
    });

    await event.data.ref.set(
      {
        emailDeliveryStatus: stats.failedCount > 0 && stats.sentCount === 0
          ? 'failed'
          : 'completed',
        emailRecipientCount: totalRecipientUids,
        emailSentCount: stats.sentCount,
        emailFailedCount: stats.failedCount,
        emailSkippedNoAddress: stats.skippedNoAddress,
        emailUniqueAddressCount: stats.uniqueRecipientCount,
        emailProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    logger.info('sendAnnouncementEmails completed', {
      announcementId,
      targetApps,
      totalRecipientUids,
      ...stats,
    });
  },
);

exports.callUser = functions
  .region(DEFAULT_REGION)
  .runWith({ secrets: [AGORA_APP_ID_SECRET, AGORA_APP_CERT_SECRET, AGORA_TTL_SECRET] })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนโทร');
    }
    const callerId = String(data?.callerId || '').trim();
    if (!callerId || callerId !== context.auth.uid) {
      throw new HttpsError('permission-denied', 'callerId ไม่ตรงกับผู้ใช้');
    }
    const callerName = String(data?.callerName || '').trim();
    const callerPhotoUrl = String(data?.callerPhotoUrl || '').trim();
    const calleeFCMToken = String(data?.calleeFCMToken || '').trim();
    const callType = String(data?.callType || 'voice').trim() || 'voice';

    if (!callerId || !calleeFCMToken) {
      throw new HttpsError('invalid-argument', 'callerId and calleeFCMToken are required');
    }

    const channelId = `call_${callerId}_${Date.now()}`;
    const agoraToken = await buildAgoraToken(channelId);
    const { appId } = resolveAgoraConfig();

    const message = {
      data: {
        type: 'call',
        callerId,
        callerName: callerName || 'ผู้โทร',
        callerPhotoUrl,
        channelId,
        appId,
        callType,
        token: agoraToken,
        isVideo: callType === 'video' ? 'true' : 'false',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        ttl: CALL_TTL_MS,
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
            'content-available': 1,
            category: 'INCOMING_CALL',
          },
        },
      },
      token: calleeFCMToken,
    };

    await admin.messaging().send(message);
    return { success: true, channelId, token: agoraToken, appId };
  });

exports.initiateCall = functions
  .region(DEFAULT_REGION)
  .runWith({ secrets: [AGORA_APP_ID_SECRET, AGORA_APP_CERT_SECRET, AGORA_TTL_SECRET] })
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const calleeId = String(data?.calleeId || '').trim();
    const callerId = String(data?.callerId || data?.callerData?.uid || '').trim();
    if (callerId !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'callerId ไม่ตรงกับบัญชีที่เข้าสู่ระบบ');
    }
    const callerName = String(data?.callerName || data?.callerData?.displayName || '').trim();
    const callerPhotoUrl = String(data?.callerPhotoUrl || data?.callerData?.photoUrl || '').trim();
    const isVideo = data?.isVideo === true || String(data?.callType || '').trim() === 'video';
    const callType = String(data?.callType || (isVideo ? 'video' : 'voice')).trim() || 'voice';

    if (!calleeId) {
      throw new functions.https.HttpsError('invalid-argument', 'calleeId is required');
    }
    if (!callerId) {
      throw new functions.https.HttpsError('invalid-argument', 'callerId is required');
    }

    let calleeProfile = await getOrCreateUserProfile(calleeId);
    if (!calleeProfile) {
      calleeProfile = await getProfileFromFriendDoc(callerId, calleeId);
    }
    if (!calleeProfile) {
      throw new HttpsError('not-found', 'Callee not found');
    }

    const fcmToken = await resolveAnyRecipientFcmToken(calleeId);
    if (!fcmToken) {
      throw new HttpsError('failed-precondition', 'Callee has no FCM token');
    }

    const { invite, created } = await resolveOrCreateActiveCallInvite({
      callerId,
      calleeId,
      isVideo,
      callType,
      calleeProfile,
    });

    if (created) {
      const message = {
        data: {
          type: 'call',
          callerId,
          callerName: callerName || 'ผู้โทร',
          callerPhotoUrl,
          channelId: invite.channelId,
          appId: invite.appId,
          callType,
          isVideo: isVideo ? 'true' : 'false',
          token: invite.token,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        android: {
          priority: 'high',
          ttl: CALL_TTL_MS,
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
              'content-available': 1,
              category: 'INCOMING_CALL',
            },
          },
        },
        token: fcmToken,
      };

      try {
        await admin.messaging().send(message);
      } catch (error) {
        await clearActiveCallInvite(callerId, calleeId);
        throw error;
      }
    }

    return {
      channelId: invite.channelId,
      appId: invite.appId,
      token: invite.token,
      calleeProfile: {
        displayName: calleeProfile.displayName || 'ผู้ใช้',
        photoUrl: calleeProfile.photoUrl || null,
        phoneNumber: calleeProfile.phoneNumber || null,
      },
    };
  });

exports.cancelCallInvite = functions
  .region(DEFAULT_REGION)
  .https.onCall(async (data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
    }

    const channelId = String(data?.channelId || '').trim();
    const calleeId = String(data?.calleeId || '').trim();
    const callerId = String(data?.callerId || '').trim();
    if (callerId && callerId !== context.auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'callerId ไม่ตรงกับบัญชีที่เข้าสู่ระบบ');
    }

    if (!channelId || !calleeId) {
      throw new HttpsError('invalid-argument', 'channelId and calleeId are required');
    }

    const fcmToken = await resolveAnyRecipientFcmToken(calleeId);
    if (!fcmToken) {
      throw new HttpsError('failed-precondition', 'Callee token unavailable');
    }

    const message = {
      data: {
        type: 'call_cancel',
        channelId,
        callerId,
      },
      android: {
        priority: 'high',
        ttl: CALL_TTL_MS,
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
            'content-available': 1,
            category: 'INCOMING_CALL',
          },
        },
      },
      token: fcmToken,
    };

    await admin.messaging().send(message);
    await clearActiveCallInvite(callerId, calleeId);
    return { success: true };
  });

const VAN2_CART_SESSION_COLLECTION = 'van2_cart_sessions';
const VAN2_CART_HOLD_MS = 60 * 60 * 1000;

function readFiniteProductStock(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  return Math.max(0, Math.floor(parsed));
}

function normalizeVan2CartHoldItems(rawItems) {
  if (!Array.isArray(rawItems)) {
    return [];
  }

  const merged = new Map();
  for (const rawItem of rawItems) {
    const productId = String(rawItem?.productId || '').trim();
    if (!productId) {
      continue;
    }
    const quantityRaw = Number(rawItem?.quantity);
    const quantity = Number.isFinite(quantityRaw)
      ? Math.max(1, Math.min(999, Math.floor(quantityRaw)))
      : 1;
    merged.set(productId, (merged.get(productId) || 0) + quantity);
  }

  return [...merged.entries()].map(([productId, quantity]) => ({
    productId,
    quantity,
  }));
}

function readVan2CartSessionHolds(sessionData) {
  const holds = sessionData?.holds;
  if (!holds || typeof holds !== 'object') {
    return {};
  }

  const normalized = {};
  for (const [productId, rawQty] of Object.entries(holds)) {
    const quantity = Math.max(0, Math.floor(Number(rawQty) || 0));
    if (!productId || quantity <= 0) {
      continue;
    }
    normalized[productId] = quantity;
  }
  return normalized;
}

function buildVan2CartHoldMap(items) {
  const holds = {};
  for (const item of items) {
    const productId = String(item?.productId || '').trim();
    const quantity = Math.max(0, Math.floor(Number(item?.quantity) || 0));
    if (!productId || quantity <= 0) {
      continue;
    }
    holds[productId] = (holds[productId] || 0) + quantity;
  }
  return holds;
}

async function syncVan2CartStockHoldTransaction(transaction, sessionRef, items) {
  const sessionSnap = await transaction.get(sessionRef);
  const previousHolds = readVan2CartSessionHolds(sessionSnap.data());
  const nextHolds = buildVan2CartHoldMap(items);
  const productIds = new Set([
    ...Object.keys(previousHolds),
    ...Object.keys(nextHolds),
  ]);

  const productSnaps = new Map();
  for (const productId of productIds) {
    productSnaps.set(
      productId,
      await transaction.get(db.collection('products').doc(productId)),
    );
  }

  for (const productId of productIds) {
    const previousQty = previousHolds[productId] || 0;
    const nextQty = nextHolds[productId] || 0;
    if (previousQty === nextQty) {
      continue;
    }

    const productSnap = productSnaps.get(productId);
    if (nextQty > 0 && (!productSnap || !productSnap.exists)) {
      throw new HttpsError('not-found', `ไม่พบสินค้า ${productId}`);
    }
    if (!productSnap || !productSnap.exists) {
      continue;
    }

    const trackedStock = readFiniteProductStock(productSnap.data()?.stock);
    if (trackedStock === null) {
      continue;
    }

    const availableAfterRelease = trackedStock + previousQty;
    if (nextQty > availableAfterRelease) {
      throw new HttpsError(
        'failed-precondition',
        `สต๊อกไม่พอสำหรับสินค้า ${productId}`,
      );
    }

    const delta = previousQty - nextQty;
    transaction.update(db.collection('products').doc(productId), {
      stock: FieldValue.increment(delta),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  if (Object.keys(nextHolds).length === 0) {
    if (sessionSnap.exists) {
      transaction.delete(sessionRef);
    }
    return nextHolds;
  }

  transaction.set(
    sessionRef,
    {
      customerUid: sessionRef.id,
      holds: nextHolds,
      items,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + VAN2_CART_HOLD_MS),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: false },
  );

  return nextHolds;
}

exports.syncVan2CartStockHold = onCall(
  { region: DEFAULT_REGION, enforceAppCheck: true },
  async (request) => {
    const uid = String(request.auth?.uid || '').trim();
    if (!uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อนใช้ตะกร้า');
    }

    const releaseMode = String(request.data?.releaseMode || 'sync')
      .trim()
      .toLowerCase();
    const sessionRef = db.collection(VAN2_CART_SESSION_COLLECTION).doc(uid);

    if (releaseMode === 'consume') {
      await db.runTransaction(async (transaction) => {
        const sessionSnap = await transaction.get(sessionRef);
        if (sessionSnap.exists) {
          transaction.delete(sessionRef);
        }
      });
      return { ok: true, mode: 'consume' };
    }

    if (releaseMode === 'restore') {
      await db.runTransaction(async (transaction) => {
        const sessionSnap = await transaction.get(sessionRef);
        if (!sessionSnap.exists) {
          return;
        }
        await syncVan2CartStockHoldTransaction(transaction, sessionRef, []);
      });
      return { ok: true, mode: 'restore' };
    }

    const items = normalizeVan2CartHoldItems(request.data?.items);
    try {
      await db.runTransaction(async (transaction) => {
        await syncVan2CartStockHoldTransaction(transaction, sessionRef, items);
      });
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error('syncVan2CartStockHold failed', {
        uid,
        message: error instanceof Error ? error.message : String(error),
      });
      throw new HttpsError('internal', 'ไม่สามารถจองสต๊อกสินค้าได้ กรุณาลองใหม่');
    }

    return {
      ok: true,
      mode: 'sync',
      itemCount: items.length,
      expiresAtMs: Date.now() + VAN2_CART_HOLD_MS,
    };
  },
);

exports.releaseExpiredVan2CartSessions = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: DEFAULT_REGION,
    timeZone: 'Asia/Bangkok',
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const snapshot = await db
      .collection(VAN2_CART_SESSION_COLLECTION)
      .where('expiresAt', '<=', now)
      .limit(200)
      .get();

    if (snapshot.empty) {
      return;
    }

    for (const doc of snapshot.docs) {
      try {
        await db.runTransaction(async (transaction) => {
          const fresh = await transaction.get(doc.ref);
          if (!fresh.exists) {
            return;
          }
          const expiresAt = fresh.data()?.expiresAt;
          if (!expiresAt || expiresAt.toMillis() > Date.now()) {
            return;
          }
          await syncVan2CartStockHoldTransaction(transaction, doc.ref, []);
        });
      } catch (error) {
        logger.warn('releaseExpiredVan2CartSessions failed', {
          sessionId: doc.id,
          error: String(error),
        });
      }
    }

    logger.info('releaseExpiredVan2CartSessions processed', {
      count: snapshot.size,
    });
  },
);

// =============================================================================
// van4 Social Dashboard (Meta / YouTube / TikTok)
// =============================================================================
Object.assign(exports, require('./social'));

const riderOrders = require('./rider_orders');
riderOrders.init({ db, DEFAULT_REGION });
Object.assign(exports, riderOrders.registerHandlers());

const riderWallet = require('./rider_wallet');
riderWallet.init({ db, FieldValue, DEFAULT_REGION });
Object.assign(exports, riderWallet.registerHandlers());

const scheduledCreditReleases = require('./scheduled_credit_releases');
scheduledCreditReleases.init({
  db,
  FieldValue,
  Timestamp: admin.firestore.Timestamp,
  onSchedule,
  logger,
  DEFAULT_REGION,
});
Object.assign(exports, scheduledCreditReleases.registerHandlers());

const adminOrderClaims = require('./admin_order_claims');
adminOrderClaims.init({
  db,
  FieldValue,
  DEFAULT_REGION,
});
Object.assign(exports, adminOrderClaims.registerHandlers());

const adminCreditControl = require('./admin_credit_control');
adminCreditControl.init({
  db,
  FieldValue,
  DEFAULT_REGION,
});
Object.assign(exports, adminCreditControl.registerHandlers());

const { registerAdminProvisionHandlers } = require('./admin_provision');
Object.assign(exports, registerAdminProvisionHandlers());

const riderOrderOps = require('./rider_order_ops');
riderOrderOps.init({ db, FieldValue, HttpsError, DEFAULT_REGION });
Object.assign(exports, riderOrderOps.registerHandlers());

const customerOrderActions = require('./customer_order_actions');
customerOrderActions.init({ db, FieldValue, HttpsError, DEFAULT_REGION });
Object.assign(exports, customerOrderActions.registerHandlers());

const slipVerificationDeps = {
  readRequiredConfiguredSecret,
  getPaymentCollectionSettings,
  buildSlipVerificationMessage,
  amountsMatch,
  validateSlipReceiver,
  buildExpectedReceiverTargets,
  writeSlipOkFeedbackLog,
  parseNumber,
  SLIPOK_ENDPOINT,
};

Object.assign(
  exports,
  createSlipVerificationQueueHandlers({
    admin,
    db,
    FieldValue,
    logger,
    HttpsError,
    onCall,
    onDocumentCreated,
    DEFAULT_REGION,
    SLIPOK_API_KEY_SECRET,
    verifyStandaloneSlipCore,
    deps: slipVerificationDeps,
  }),
);

const { findNearestRiderForShop } = require('./checkout_orders');
const pendingOrderRiderMatch = require('./pending_order_rider_match');
pendingOrderRiderMatch.init({
  db,
  FieldValue,
  logger,
  findNearestRiderForShop,
});
Object.assign(
  exports,
  pendingOrderRiderMatch.registerHandlers({
    onSchedule,
    DEFAULT_REGION,
  }),
);

Object.assign(
  exports,
  createRiderAvailabilityHandlers({
    db,
    FieldValue,
    logger,
    onSchedule,
    onDocumentWritten,
    DEFAULT_REGION,
    onRiderBecameAvailable: (context) =>
      pendingOrderRiderMatch.matchPendingAwaitingRiderOrders(context),
  }),
);

const omisePayoutHandlers = createOmisePayoutHandlers({
  db,
  FieldValue,
  HttpsError,
  onCall,
  defineSecret,
  logger,
  DEFAULT_REGION,
});
const { loadPayoutProfile } = createPayoutProfileLoader(db, HttpsError);
const payoutLedger = createPayoutLedger({ db, FieldValue, HttpsError });
const { loadSettlementConfig } = createSettlementConfigLoader({ db });
const manualPayoutHandlers = createManualPayoutHandlers({
  admin,
  db,
  FieldValue,
  HttpsError,
  onCall,
  defineSecret,
  logger,
  DEFAULT_REGION,
  payoutLedger: { loadPayoutProfile, ...payoutLedger },
  loadSettlementConfig,
  verifyStandaloneSlipCore,
  slipVerificationDeps,
});
Object.assign(exports, {
  getWithdrawableBalance: manualPayoutHandlers.getWithdrawableBalance,
  requestManualWithdraw: manualPayoutHandlers.requestManualWithdraw,
  confirmManualWithdraw: manualPayoutHandlers.confirmManualWithdraw,
  rejectManualWithdraw: manualPayoutHandlers.rejectManualWithdraw,
  exportWithdrawBankCsv: manualPayoutHandlers.exportWithdrawBankCsv,
  requestOmiseWithdraw: omisePayoutHandlers.requestOmiseWithdraw,
});

Object.assign(
  exports,
  createOmisePaymentsHandlers({
    db,
    FieldValue,
    HttpsError,
    onCall,
    onRequest,
    defineSecret,
    logger,
    DEFAULT_REGION,
    handleTransferWebhook: omisePayoutHandlers.handleTransferWebhook,
  }),
);

Object.assign(
  exports,
  createPlatformFloatHandlers({
    db,
    FieldValue,
    onDocumentUpdated,
    onSchedule,
    logger,
    DEFAULT_REGION,
  }),
);

const ensureProductTranslationHandler = createEnsureProductTranslationHandler({
  db,
  FieldValue,
  HttpsError,
  logger,
  assertCallableRateLimit: (options) =>
    assertCallableRateLimit(db, admin, HttpsError, options),
});

exports.ensureProductTranslation = onCall(
  {
    region: DEFAULT_REGION,
    enforceAppCheck: true,
  },
  ensureProductTranslationHandler,
);

exports.productSharePreview = createProductSharePreviewExport({
  db,
  logger,
  onRequest,
  DEFAULT_REGION,
});

exports.productShareOgImage = createProductShareOgImageExport({
  db,
  logger,
  onRequest,
  DEFAULT_REGION,
});

// =============================================================================
// Security roadmap (Phase 2 / Phase 3 hooks)
// -----------------------------------------------------------------------------
// Phase 2 — createCheckoutOrders / createNationwideParcelOrder (onCall):
//   - Recompute totals via calculateCartTotals logic
//   - Write orders with Admin SDK; store checkout_quotes/{id} for rules validation
//   - Van2 client stops direct orders.set for checkout flows
//
// Phase 3 — harden auth callables (sendEmailOtp, lookupLoginIdentifier):
//   - enforceAppCheck: true once all apps register App Check
//   - Use auth_rate_limits / email_otp_rate_limits collections (rules: client write false)
// =============================================================================
