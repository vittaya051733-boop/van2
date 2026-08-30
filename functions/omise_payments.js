const crypto = require('crypto');

const OMISE_API_BASE = 'https://api.omise.co';
const OMISE_VAULT_BASE = 'https://vault.omise.co';
const SESSION_TTL_MS = 30 * 60 * 1000;
const CUSTOMER_USERS_COLLECTION = 'customer_users';
const SAVED_CARDS_SUBCOLLECTION = 'saved_payment_methods';

const CHANNEL_CONFIG = {
  omise_promptpay: {
    label: 'พร้อมเพย์',
    sourceType: 'promptpay',
  },
  omise_truemoney: {
    label: 'TrueMoney',
    sourceType: 'truemoney',
  },
  omise_mobile_banking: {
    label: 'Mobile Banking',
    sourceType: 'mobile_banking_kbank',
  },
  omise_card: {
    label: 'บัตรเครดิต/เดบิต',
    sourceType: null,
  },
};

const MOBILE_BANK_CODES = {
  kbank: 'mobile_banking_kbank',
  scb: 'mobile_banking_scb',
  bbl: 'mobile_banking_bbl',
  ktb: 'mobile_banking_ktb',
  bay: 'mobile_banking_bay',
};

const DEFAULT_RETURN_URI = 'https://vantalad.web.app/payment/return';

function normalizeThaiPhoneNumber(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.length === 10 && digits.startsWith('0')) {
    return digits;
  }
  if (digits.length === 11 && digits.startsWith('66')) {
    return `0${digits.slice(2)}`;
  }
  if (digits.length === 9 && !digits.startsWith('0')) {
    return `0${digits}`;
  }
  return null;
}

function resolvePlatformType(raw) {
  const normalized = String(raw || '').trim().toUpperCase();
  if (normalized === 'IOS' || normalized === 'ANDROID') {
    return normalized;
  }
  return 'ANDROID';
}

function resolveReturnUri(raw) {
  const uri = String(raw || '').trim();
  if (uri.startsWith('http://') || uri.startsWith('https://')) {
    return uri;
  }
  return DEFAULT_RETURN_URI;
}

const WEBHOOK_MAX_AGE_SEC = 5 * 60;

function parseWebhookSecrets(rawValue) {
  return String(rawValue || '')
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function verifyOmiseWebhookSignature({ req, webhookSecrets }) {
  const signatureHeader = String(req.headers['omise-signature'] || '').trim();
  const timestampHeader = String(req.headers['omise-signature-timestamp'] || '').trim();

  if (!signatureHeader || !timestampHeader) {
    return { ok: false, reason: 'missing Omise-Signature headers' };
  }

  const rawBody = req.rawBody;
  if (!rawBody || !Buffer.isBuffer(rawBody)) {
    return { ok: false, reason: 'missing raw request body' };
  }

  const signedPayload = `${timestampHeader}.${rawBody.toString('utf8')}`;
  const headerSignatures = signatureHeader
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);

  for (const secretB64 of webhookSecrets) {
    let secretBuffer;
    try {
      secretBuffer = Buffer.from(secretB64, 'base64');
    } catch (error) {
      continue;
    }

    const expectedBuffer = crypto
      .createHmac('sha256', secretBuffer)
      .update(signedPayload)
      .digest();

    for (const signatureHex of headerSignatures) {
      try {
        const signatureBuffer = Buffer.from(signatureHex, 'hex');
        if (
          signatureBuffer.length === expectedBuffer.length &&
          crypto.timingSafeEqual(signatureBuffer, expectedBuffer)
        ) {
          const timestampSec = Number.parseInt(timestampHeader, 10);
          if (Number.isFinite(timestampSec)) {
            const ageSec = Math.abs(Math.floor(Date.now() / 1000) - timestampSec);
            if (ageSec > WEBHOOK_MAX_AGE_SEC) {
              return { ok: false, reason: 'signature timestamp too old' };
            }
          }
          return { ok: true };
        }
      } catch (error) {
        // Ignore malformed hex signatures and keep checking.
      }
    }
  }

  return { ok: false, reason: 'signature mismatch' };
}

function readMoney(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function toSatang(amountBaht) {
  const normalized = Math.round(readMoney(amountBaht) * 100);
  if (normalized < 2000) {
    throw new Error('ยอดชำระขั้นต่ำ 20 บาท');
  }
  return normalized;
}

function createOmisePaymentsHandlers(deps) {
  const {
    db,
    FieldValue,
    HttpsError,
    onCall,
    onRequest,
    defineSecret,
    logger,
    DEFAULT_REGION,
    handleTransferWebhook,
  } = deps;

  const OMISE_SECRET_KEY = defineSecret('OMISE_SECRET_KEY');
  const OMISE_PUBLIC_KEY = defineSecret('OMISE_PUBLIC_KEY');
  const OMISE_WEBHOOK_SECRET = defineSecret('OMISE_WEBHOOK_SECRET');

  function normalizeOmiseKey(raw) {
    return String(raw || '')
      .trim()
      .replace(/^['"]+|['"]+$/g, '')
      .replace(/\s+/g, '');
  }

  async function omiseRequest(secretKey, method, path, body) {
    const auth = Buffer.from(`${normalizeOmiseKey(secretKey)}:`).toString('base64');
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30_000);
    let response;
    try {
      response = await fetch(`${OMISE_API_BASE}${path}`, {
        method,
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/json',
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
        signal: controller.signal,
      });
    } catch (error) {
      if (error?.name === 'AbortError') {
        throw new Error('Omise request timed out');
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message =
        payload?.message ||
        payload?.error ||
        `Omise request failed (${response.status})`;
      throw new Error(message);
    }
    return payload;
  }

  function parseCardDetailsFromRequest(data) {
    const cardNumber = String(data?.cardNumber || '').replace(/\s+/g, '');
    const cardName = String(data?.cardName || '').trim();
    const expirationMonth = String(data?.expirationMonth || '').trim();
    let expirationYear = String(data?.expirationYear || '').trim();
    const securityCode = String(data?.securityCode || '').trim();

    if (!cardNumber || !expirationMonth || !expirationYear || !securityCode) {
      return null;
    }
    if (expirationYear.length === 2) {
      expirationYear = `20${expirationYear}`;
    }

    return buildOmiseCardPayload({
      cardName,
      cardNumber,
      expirationMonth,
      expirationYear,
      securityCode,
    });
  }

  function buildOmiseCardPayload({
    cardName,
    cardNumber,
    expirationMonth,
    expirationYear,
    securityCode,
  }) {
    return {
      name: cardName || 'Van Customer',
      number: cardNumber,
      expiration_month: Number.parseInt(expirationMonth, 10),
      expiration_year: Number.parseInt(expirationYear, 10),
      security_code: securityCode,
    };
  }

  function toHttpsErrorFromOmise(error, fallbackMessage) {
    if (error instanceof HttpsError) {
      return error;
    }
    const message = String(error?.message || error || fallbackMessage).trim();
    return new HttpsError('failed-precondition', message || fallbackMessage);
  }

  function extractQrDownloadUri(source, charge) {
    return (
      source?.scannable_code?.image?.download_uri ||
      charge?.source?.scannable_code?.image?.download_uri ||
      null
    );
  }

  function normalizeOmiseQrSvg(svg) {
    let normalized = String(svg || '');
    const peachFills = [
      '#fff5eb',
      '#fff3e8',
      '#fff0e6',
      '#ffe8d6',
      '#ffead9',
      '#fff5f0',
      '#fdf3ea',
      '#fceee3',
      '#fdead7',
      '#fff8f3',
      '#fff7ed',
      '#ffedd5',
    ];

    for (const color of peachFills) {
      const escaped = color.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      normalized = normalized.replace(
        new RegExp(`fill="${escaped}"`, 'gi'),
        'fill="#FFFFFF"',
      );
      normalized = normalized.replace(
        new RegExp(`fill='${escaped}'`, 'gi'),
        "fill='#FFFFFF'",
      );
    }

    normalized = normalized.replace(
      /fill="#(FFF[0-9A-F]{3}|FFE[0-9A-F]{3}|FFFD[0-9A-F]{2})"/gi,
      'fill="#FFFFFF"',
    );

    return normalized;
  }

  function svgToPngDataUrl(svgText) {
    try {
      const { Resvg } = require('@resvg/resvg-js');
      const normalizedSvg = normalizeOmiseQrSvg(svgText);
      const resvg = new Resvg(normalizedSvg, {
        fitTo: { mode: 'width', value: 900 },
        background: 'white',
      });
      const pngData = resvg.render().asPng();
      if (!pngData || pngData.length === 0) {
        return null;
      }
      return `data:image/png;base64,${Buffer.from(pngData).toString('base64')}`;
    } catch (error) {
      logger.warn('svgToPngDataUrl failed', {
        error: String(error?.message || error),
      });
      return null;
    }
  }

  async function fetchOmiseQrImageDataUrl(secretKey, downloadUri) {
    if (!downloadUri) {
      return null;
    }

    const auth = Buffer.from(`${secretKey}:`).toString('base64');
    const response = await fetch(downloadUri, {
      headers: {
        Authorization: `Basic ${auth}`,
      },
    });

    if (!response.ok) {
      logger.warn('fetchOmiseQrImageDataUrl failed', {
        status: response.status,
        downloadUri,
      });
      return null;
    }

    const contentType = String(response.headers.get('content-type') || 'image/png')
      .split(';')[0]
      .trim();
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length === 0) {
      return null;
    }

    const mimeType = contentType || 'image/png';
    if (
      mimeType.includes('svg') ||
      buffer.toString('utf8', 0, Math.min(buffer.length, 200)).includes('<svg')
    ) {
      const pngDataUrl = svgToPngDataUrl(buffer.toString('utf8'));
      if (pngDataUrl) {
        return pngDataUrl;
      }
      const normalizedSvg = normalizeOmiseQrSvg(buffer.toString('utf8'));
      return `data:image/svg+xml;base64,${Buffer.from(normalizedSvg, 'utf8').toString('base64')}`;
    }

    return `data:${mimeType};base64,${buffer.toString('base64')}`;
  }

  async function loadOmiseKeys() {
    const secretKey = normalizeOmiseKey(OMISE_SECRET_KEY.value());
    const publicKey = normalizeOmiseKey(OMISE_PUBLIC_KEY.value());
    if (!secretKey) {
      throw new HttpsError('failed-precondition', 'ยังไม่ได้ตั้งค่า OMISE_SECRET_KEY');
    }
    return { secretKey, publicKey: publicKey || null };
  }

  async function loadOmiseSecretKey() {
    const secretKey = normalizeOmiseKey(OMISE_SECRET_KEY.value());
    if (!secretKey) {
      throw new HttpsError('failed-precondition', 'ยังไม่ได้ตั้งค่า OMISE_SECRET_KEY');
    }
    return secretKey;
  }

  function resolveOmisePublicKey(rawPublicKey) {
    const publicKey = normalizeOmiseKey(rawPublicKey);
    if (!publicKey) {
      throw new HttpsError(
        'failed-precondition',
        'ยังไม่ได้ตั้งค่า OMISE_PUBLIC_KEY',
      );
    }
    if (!publicKey.startsWith('pkey_')) {
      throw new HttpsError(
        'failed-precondition',
        'OMISE_PUBLIC_KEY ไม่ถูกต้อง ต้องขึ้นต้นด้วย pkey_',
      );
    }
    return publicKey;
  }

  async function createOmiseCardTokenFromDetails(publicKey, cardPayload) {
    const key = resolveOmisePublicKey(publicKey);
    const auth = Buffer.from(`${normalizeOmiseKey(key)}:`).toString('base64');
    const form = new URLSearchParams();
    form.set('card[name]', cardPayload.name || 'Van Customer');
    form.set('card[number]', String(cardPayload.number || ''));
    form.set('card[expiration_month]', String(cardPayload.expiration_month || ''));
    form.set('card[expiration_year]', String(cardPayload.expiration_year || ''));
    form.set('card[security_code]', String(cardPayload.security_code || ''));

    const response = await fetch(`${OMISE_VAULT_BASE}/tokens`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form.toString(),
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const message =
        payload?.message ||
        payload?.error ||
        `Omise token request failed (${response.status})`;
      throw new Error(message);
    }

    const tokenId = String(payload?.id || '').trim();
    if (!tokenId) {
      throw new HttpsError('failed-precondition', 'ไม่สามารถสร้าง card token ได้');
    }
    return tokenId;
  }

  function buildOrderReference({ checkoutQuoteId, sessionId, purpose }) {
    const quote = String(checkoutQuoteId || '').trim();
    const session = String(sessionId || '').trim();
    const shortQuote =
      quote.length >= 6 ? quote.slice(-8).toUpperCase() : quote.toUpperCase();
    const shortSession =
      session.length >= 6 ? session.slice(-6).toUpperCase() : session.toUpperCase();
    if (purpose === 'travel') {
      return shortSession ? `TRAVEL-${shortSession}` : 'TRAVEL';
    }
    if (shortQuote) {
      return `QTE-${shortQuote}`;
    }
    return shortSession ? `SES-${shortSession}` : 'VAN-CHECKOUT';
  }

  function buildChargeDescription({ orderReference, amountBaht, channel }) {
    const label = CHANNEL_CONFIG[channel]?.label || channel;
    const amount = readMoney(amountBaht).toFixed(2);
    return `Van · ${orderReference} · ฿${amount} · ${label}`;
  }

  function buildChargeMetadata({
    checkoutQuoteId,
    sessionId,
    orderReference,
    purpose,
    uid,
    channel,
  }) {
    return {
      checkoutQuoteId: checkoutQuoteId || null,
      paymentSessionId: sessionId || null,
      orderReference: orderReference || null,
      purpose,
      uid,
      channel,
    };
  }

  function isOmiseChargePaid(charge) {
    if (!charge || typeof charge !== 'object') {
      return false;
    }
    const status = String(charge.status || '').trim().toLowerCase();
    if (status === 'successful') {
      return true;
    }
    if (charge.paid === true) {
      return true;
    }
    if (charge.paid_at != null && charge.paid_at !== '') {
      return true;
    }
    return false;
  }

  function isOmiseChargeFailed(charge) {
    if (!charge || typeof charge !== 'object') {
      return false;
    }
    return String(charge.status || '').trim().toLowerCase() === 'failed';
  }

  function isOmiseChargeExpired(charge) {
    if (!charge || typeof charge !== 'object') {
      return false;
    }
    return String(charge.status || '').trim().toLowerCase() === 'expired';
  }

  async function syncOmiseChargeToSession(sessionRef, data, secretKey, sessionId) {
    if (String(data.status || '') !== 'pending' || !data.omiseChargeId) {
      return data;
    }

    try {
      const charge = await omiseRequest(
        secretKey,
        'GET',
        `/charges/${data.omiseChargeId}`,
      );

      if (isOmiseChargePaid(charge)) {
        await sessionRef.set(
          {
            status: 'paid',
            paidAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            omiseChargeStatus: charge.status || 'successful',
          },
          { merge: true },
        );
        return { ...data, status: 'paid' };
      }

      if (isOmiseChargeFailed(charge)) {
        const failureMessage = charge.failure_message || 'charge failed';
        await sessionRef.set(
          {
            status: 'failed',
            failureMessage,
            updatedAt: FieldValue.serverTimestamp(),
            omiseChargeStatus: charge.status || 'failed',
          },
          { merge: true },
        );
        return { ...data, status: 'failed', failureMessage };
      }

      if (isOmiseChargeExpired(charge)) {
        const failureMessage = charge.failure_message || 'payment expired';
        await sessionRef.set(
          {
            status: 'expired',
            failureMessage,
            updatedAt: FieldValue.serverTimestamp(),
            omiseChargeStatus: charge.status || 'expired',
          },
          { merge: true },
        );
        return { ...data, status: 'expired', failureMessage };
      }

      logger.info('Omise charge still pending', {
        sessionId: sessionId || sessionRef.id,
        omiseChargeId: data.omiseChargeId,
        chargeStatus: charge.status,
        paid: charge.paid,
      });
    } catch (error) {
      logger.warn('syncOmiseChargeToSession failed', {
        sessionId: sessionId || sessionRef.id,
        omiseChargeId: data.omiseChargeId,
        error: String(error?.message || error),
      });
    }

    return data;
  }

  async function assertCheckoutQuote(checkoutQuoteId, uid, expectedAmount) {
    const quoteRef = db.collection('checkout_quotes').doc(checkoutQuoteId);
    const quoteDoc = await quoteRef.get();
    if (!quoteDoc.exists) {
      throw new HttpsError('failed-precondition', 'ไม่พบ checkout quote');
    }
    const quote = quoteDoc.data() || {};
    const quoteOwner = String(quote.customerId || quote.uid || '').trim();
    if (quoteOwner !== uid) {
      throw new HttpsError('permission-denied', 'checkout quote ไม่ตรงกับผู้ใช้');
    }
    if (quote.consumed === true) {
      throw new HttpsError('failed-precondition', 'checkout quote ถูกใช้แล้ว');
    }
    const expiresAt = Number(quote.expiresAt || 0);
    if (expiresAt > 0 && expiresAt < Date.now()) {
      throw new HttpsError('failed-precondition', 'checkout quote หมดอายุ');
    }
    const quoteAmount = readMoney(quote.grandTotal);
    if (Math.abs(quoteAmount - expectedAmount) > 0.01) {
      throw new HttpsError('failed-precondition', 'ยอดชำระไม่ตรงกับ quote');
    }
    return quoteDoc;
  }

  function sessionResponse(sessionId, data) {
    return {
      sessionId,
      status: data.status || 'pending',
      amount: readMoney(data.amount),
      channel: data.channel || '',
      qrImageUrl: data.qrImageUrl || null,
      qrImageDataUrl: data.qrImageDataUrl || null,
      authorizeUri: data.authorizeUri || null,
      publicKey: data.publicKey || null,
      needsCardToken: data.needsCardToken === true,
      omiseChargeId: data.omiseChargeId || null,
      checkoutQuoteId: data.checkoutQuoteId || null,
      orderReference: data.orderReference || null,
    };
  }

  async function createChargeForSession({
    secretKey,
    publicKey,
    uid,
    channel,
    amountBaht,
    checkoutQuoteId,
    cardToken,
    mobileBankCode,
    phoneNumber,
    returnUri,
    platformType,
    purpose = 'cart',
  }) {
    const config = CHANNEL_CONFIG[channel];
    if (!config) {
      throw new HttpsError('invalid-argument', 'ช่องทางชำระเงินไม่รองรับ');
    }

    const amountSatang = toSatang(amountBaht);
    const sessionRef = db.collection('payment_sessions').doc();
    const expiresAt = new Date(Date.now() + SESSION_TTL_MS);
    const orderReference = buildOrderReference({
      checkoutQuoteId,
      sessionId: sessionRef.id,
      purpose,
    });
    const chargeDescription = buildChargeDescription({
      orderReference,
      amountBaht,
      channel,
    });
    const chargeMetadata = buildChargeMetadata({
      checkoutQuoteId,
      sessionId: sessionRef.id,
      orderReference,
      purpose,
      uid,
      channel,
    });

    let qrImageUrl = null;
    let authorizeUri = null;
    let needsCardToken = false;
    let omiseChargeId = null;
    let omiseSourceId = null;

    if (channel === 'omise_card') {
      if (!cardToken) {
        await sessionRef.set({
          uid,
          channel,
          amount: amountBaht,
          amountSatang,
          checkoutQuoteId: checkoutQuoteId || null,
          orderReference,
          purpose,
          status: 'awaiting_card_token',
          needsCardToken: true,
          publicKey,
          expiresAt,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return sessionResponse(sessionRef.id, {
          status: 'awaiting_card_token',
          amount: amountBaht,
          channel,
          publicKey,
          needsCardToken: true,
          checkoutQuoteId: checkoutQuoteId || null,
          orderReference,
        });
      }

      const charge = await omiseRequest(secretKey, 'POST', '/charges', {
        amount: amountSatang,
        currency: 'thb',
        card: cardToken,
        description: chargeDescription,
        metadata: chargeMetadata,
      });
      omiseChargeId = charge.id;
      if (isOmiseChargePaid(charge)) {
        await sessionRef.set({
          uid,
          channel,
          amount: amountBaht,
          amountSatang,
          checkoutQuoteId: checkoutQuoteId || null,
          orderReference,
          purpose,
          status: 'paid',
          omiseChargeId,
          paidAt: FieldValue.serverTimestamp(),
          expiresAt,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return sessionResponse(sessionRef.id, {
          status: 'paid',
          amount: amountBaht,
          channel,
          omiseChargeId,
          checkoutQuoteId: checkoutQuoteId || null,
          orderReference,
        });
      }
      authorizeUri = charge.authorize_uri || null;
    } else {
      let sourceType = config.sourceType;
      if (channel === 'omise_mobile_banking') {
        const bank = String(mobileBankCode || 'kbank').trim().toLowerCase();
        sourceType = MOBILE_BANK_CODES[bank] || MOBILE_BANK_CODES.kbank;
      }

      const sourcePayload = {
        type: sourceType,
        amount: amountSatang,
        currency: 'thb',
      };

      if (channel === 'omise_truemoney') {
        const normalizedPhone = normalizeThaiPhoneNumber(phoneNumber);
        if (!normalizedPhone) {
          throw new HttpsError(
            'invalid-argument',
            'กรุณาระบุเบอร์ TrueMoney Wallet 10 หลัก',
          );
        }
        sourcePayload.phone_number = normalizedPhone;
      }

      if (channel === 'omise_mobile_banking') {
        sourcePayload.platform_type = resolvePlatformType(platformType);
      }

      let source;
      try {
        source = await omiseRequest(secretKey, 'POST', '/sources', sourcePayload);
      } catch (error) {
        logger.error('createChargeForSession source failed', {
          channel,
          error: String(error?.message || error),
        });
        throw new HttpsError(
          'failed-precondition',
          error?.message || 'ไม่สามารถเริ่มช่องทางชำระเงินได้',
        );
      }
      omiseSourceId = source.id;

      const chargePayload = {
        amount: amountSatang,
        currency: 'thb',
        source: source.id,
        description: chargeDescription,
        metadata: chargeMetadata,
      };

      if (channel === 'omise_truemoney' || channel === 'omise_mobile_banking') {
        chargePayload.return_uri = resolveReturnUri(returnUri);
      }

      let charge;
      try {
        charge = await omiseRequest(secretKey, 'POST', '/charges', chargePayload);
      } catch (error) {
        logger.error('createChargeForSession charge failed', {
          channel,
          omiseSourceId,
          error: String(error?.message || error),
        });
        throw new HttpsError(
          'failed-precondition',
          error?.message || 'ไม่สามารถสร้างรายการชำระเงินได้',
        );
      }
      omiseChargeId = charge.id;
      authorizeUri = charge.authorize_uri || source.authorize_uri || null;
      qrImageUrl = extractQrDownloadUri(source, charge);
    }

    let qrImageDataUrl = null;
    if (qrImageUrl) {
      qrImageDataUrl = await fetchOmiseQrImageDataUrl(secretKey, qrImageUrl);
      if (!qrImageDataUrl) {
        logger.warn('createChargeForSession QR proxy failed', {
          channel,
          qrImageUrl,
        });
      }
    }

    await sessionRef.set({
      uid,
      channel,
      amount: amountBaht,
      amountSatang,
      checkoutQuoteId: checkoutQuoteId || null,
      orderReference,
      purpose,
      status: 'pending',
      omiseChargeId,
      omiseSourceId,
      qrImageUrl,
      authorizeUri,
      publicKey,
      expiresAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return sessionResponse(sessionRef.id, {
      status: 'pending',
      amount: amountBaht,
      channel,
      qrImageUrl,
      qrImageDataUrl,
      authorizeUri,
      publicKey,
      omiseChargeId,
      checkoutQuoteId: checkoutQuoteId || null,
      orderReference,
    });
  }

  async function attachQrImageDataUrl(secretKey, data) {
    if (data.qrImageDataUrl) {
      return data;
    }
    const downloadUri = String(data.qrImageUrl || '').trim();
    if (!downloadUri) {
      return data;
    }
    const qrImageDataUrl = await fetchOmiseQrImageDataUrl(secretKey, downloadUri);
    if (!qrImageDataUrl) {
      return data;
    }
    return {
      ...data,
      qrImageDataUrl,
    };
  }

  const createOmisePaymentSession = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
      secrets: [OMISE_SECRET_KEY, OMISE_PUBLIC_KEY],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const channel = String(request.data?.channel || '').trim();
      const amount = readMoney(request.data?.amount);
      const checkoutQuoteId = String(request.data?.checkoutQuoteId || '').trim();
      const purpose = String(request.data?.purpose || 'cart').trim();
      const cardToken = String(request.data?.cardToken || '').trim();
      const mobileBankCode = String(request.data?.mobileBankCode || '').trim();
      const phoneNumber = String(request.data?.phoneNumber || '').trim();
      const returnUri = String(request.data?.returnUri || '').trim();
      const platformType = String(request.data?.platformType || '').trim();

      if (!channel || amount <= 0) {
        throw new HttpsError('invalid-argument', 'ข้อมูลชำระเงินไม่ครบ');
      }
      if (purpose === 'cart' && !checkoutQuoteId) {
        throw new HttpsError('invalid-argument', 'ต้องมี checkout quote');
      }

      const { secretKey, publicKey } = await loadOmiseKeys();
      if (purpose === 'cart') {
        await assertCheckoutQuote(checkoutQuoteId, request.auth.uid, amount);
      }

      try {
        return await createChargeForSession({
          secretKey,
          publicKey,
          uid: request.auth.uid,
          channel,
          amountBaht: amount,
          checkoutQuoteId: checkoutQuoteId || null,
          purpose,
          cardToken: cardToken || null,
          mobileBankCode: mobileBankCode || null,
          phoneNumber: phoneNumber || null,
          returnUri: returnUri || null,
          platformType: platformType || null,
        });
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        logger.error('createOmisePaymentSession failed', {
          channel,
          uid: request.auth.uid,
          error: String(error?.message || error),
        });
        throw new HttpsError(
          'failed-precondition',
          error?.message || 'ไม่สามารถเริ่มชำระเงินได้',
        );
      }
    },
  );

  const getOmisePaymentSession = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
      secrets: [OMISE_SECRET_KEY],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }
      const sessionId = String(request.data?.sessionId || '').trim();
      if (!sessionId) {
        throw new HttpsError('invalid-argument', 'ไม่พบ session');
      }

      const sessionDoc = await db.collection('payment_sessions').doc(sessionId).get();
      if (!sessionDoc.exists) {
        throw new HttpsError('not-found', 'ไม่พบ session');
      }
      let data = sessionDoc.data() || {};
      if (String(data.uid || '') !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์เข้าถึง session');
      }

      if (data.status === 'pending' && data.omiseChargeId) {
        const { secretKey } = await loadOmiseKeys();
        data = await syncOmiseChargeToSession(
          sessionDoc.ref,
          data,
          secretKey,
          sessionId,
        );
      }

      const { secretKey } = await loadOmiseKeys();
      const responseData = await attachQrImageDataUrl(secretKey, data);
      return sessionResponse(sessionId, responseData);
    },
  );

  const createOmiseCardToken = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
      secrets: [OMISE_PUBLIC_KEY],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      throw new HttpsError(
        'failed-precondition',
        'กรุณาสร้าง card token ฝั่งแอปเท่านั้น (ไม่ส่งเลขบัตรผ่านเซิร์ฟเวอร์)',
      );
    },
  );

  const omiseWebhook = onRequest(
    {
      region: DEFAULT_REGION,
      secrets: [OMISE_SECRET_KEY, OMISE_WEBHOOK_SECRET],
    },
    async (req, res) => {
      if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
      }

      try {
        const webhookSecrets = parseWebhookSecrets(OMISE_WEBHOOK_SECRET.value());
        if (webhookSecrets.length === 0) {
          logger.error('omiseWebhook rejected: OMISE_WEBHOOK_SECRET not configured');
          res.status(500).send('webhook secret not configured');
          return;
        }

        const verification = verifyOmiseWebhookSignature({ req, webhookSecrets });
        if (!verification.ok) {
          logger.warn('omiseWebhook signature verification failed', {
            reason: verification.reason,
          });
          res.status(401).send('invalid signature');
          return;
        }

        const event = req.body || {};
        const eventType = String(event?.key || event?.type || '').trim();

        if (eventType.startsWith('transfer.') && typeof handleTransferWebhook === 'function') {
          await handleTransferWebhook(event);
          res.status(200).send('ok');
          return;
        }

        const charge = event?.data || event?.object === 'charge' ? event : null;
        const chargeData = event?.data && typeof event.data === 'object' ? event.data : charge;
        const chargeId = chargeData?.id;

        if (!chargeId) {
          res.status(200).send('ignored');
          return;
        }

        const snapshot = await db
          .collection('payment_sessions')
          .where('omiseChargeId', '==', chargeId)
          .limit(1)
          .get();

        if (snapshot.empty) {
          res.status(200).send('no session');
          return;
        }

        const sessionRef = snapshot.docs[0].ref;
        const existingSession = snapshot.docs[0].data() || {};
        const isPaid =
          eventType === 'charge.complete' || isOmiseChargePaid(chargeData);

        if (isPaid) {
          if (existingSession.status === 'paid' && existingSession.consumed === true) {
            res.status(200).send('already processed');
            return;
          }
          if (existingSession.status === 'paid') {
            res.status(200).send('already paid');
            return;
          }
          await sessionRef.set(
            {
              status: 'paid',
              paidAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
              webhookEvent: eventType || 'charge.complete',
              omiseChargeStatus: chargeData?.status || 'successful',
            },
            { merge: true },
          );
        } else if (isOmiseChargeFailed(chargeData)) {
          await sessionRef.set(
            {
              status: 'failed',
              failureMessage: chargeData.failure_message || 'charge failed',
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }

        res.status(200).send('ok');
      } catch (error) {
        logger.error('omiseWebhook failed', { error: String(error?.message || error) });
        res.status(500).send('error');
      }
    },
  );

  async function assertPaidPaymentSession(paymentSessionId, uid, expectedAmount) {
    const sessionDoc = await db.collection('payment_sessions').doc(paymentSessionId).get();
    if (!sessionDoc.exists) {
      throw new HttpsError('failed-precondition', 'ไม่พบ payment session');
    }
    const session = sessionDoc.data() || {};
    if (String(session.uid || '') !== uid) {
      throw new HttpsError('permission-denied', 'payment session ไม่ตรงกับผู้ใช้');
    }
    if (session.status !== 'paid') {
      throw new HttpsError('failed-precondition', 'การชำระเงินยังไม่สำเร็จ');
    }
    if (Math.abs(readMoney(session.amount) - expectedAmount) > 0.01) {
      throw new HttpsError('failed-precondition', 'ยอดชำระไม่ตรงกับ session');
    }
    const channel = String(session.channel || '').trim();
    if (!CHANNEL_CONFIG[channel]) {
      throw new HttpsError('failed-precondition', 'ช่องทางชำระเงินไม่รองรับ');
    }
    return session;
  }

  async function getStoredOmiseCustomerId(uid) {
    const userDoc = await db.collection(CUSTOMER_USERS_COLLECTION).doc(uid).get();
    return String(userDoc.data()?.omiseCustomerId || '').trim() || null;
  }

  async function getOrCreateOmiseCustomer(secretKey, uid, email) {
    let customerId = await getStoredOmiseCustomerId(uid);
    if (customerId) {
      try {
        await omiseRequest(secretKey, 'GET', `/customers/${customerId}`);
        return customerId;
      } catch (error) {
        logger.warn('getOrCreateOmiseCustomer stale id', {
          uid,
          customerId,
          error: String(error?.message || error),
        });
      }
    }

    const customer = await omiseRequest(secretKey, 'POST', '/customers', {
      email: email || `${uid}@van-customer.local`,
      description: `van2 customer ${uid}`,
      metadata: { firebaseUid: uid },
    });
    customerId = String(customer.id || '').trim();
    if (!customerId) {
      throw new HttpsError('internal', 'ไม่สามารถสร้าง Omise customer ได้');
    }

    await db.collection(CUSTOMER_USERS_COLLECTION).doc(uid).set(
      {
        omiseCustomerId: customerId,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return customerId;
  }

  async function persistSavedCard(uid, omiseCustomerId, card) {
    const cardId = String(card?.id || '').trim();
    if (!cardId) {
      return;
    }
    await db
      .collection(CUSTOMER_USERS_COLLECTION)
      .doc(uid)
      .collection(SAVED_CARDS_SUBCOLLECTION)
      .doc(cardId)
      .set(
        {
          omiseCardId: cardId,
          omiseCustomerId,
          brand: String(card.brand || card.financing || 'card').toLowerCase(),
          lastDigits: String(card.last_digits || '').trim(),
          expMonth: Number(card.expiration_month || 0),
          expYear: Number(card.expiration_year || 0),
          name: String(card.name || '').trim(),
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }

  function extractAttachedCard(customer) {
    const cards = customer?.cards?.data;
    if (Array.isArray(cards) && cards.length > 0) {
      return cards[cards.length - 1];
    }
    const defaultCard = String(customer?.default_card || '').trim();
    if (defaultCard) {
      return { id: defaultCard };
    }
    return null;
  }

  async function finalizeCardChargeSession(sessionRef, sessionData, charge) {
    const omiseChargeId = charge.id;
    const authorizeUri = charge.authorize_uri || null;
    const isPaid = isOmiseChargePaid(charge);
    const patch = {
      omiseChargeId,
      authorizeUri,
      updatedAt: FieldValue.serverTimestamp(),
      status: isPaid ? 'paid' : 'pending',
    };
    if (isPaid) {
      patch.paidAt = FieldValue.serverTimestamp();
    }
    await sessionRef.set(patch, { merge: true });
    return {
      status: isPaid ? 'paid' : 'pending',
      amount: readMoney(sessionData.amount),
      channel: sessionData.channel,
      omiseChargeId,
      authorizeUri,
      checkoutQuoteId: sessionData.checkoutQuoteId || null,
      orderReference: sessionData.orderReference || null,
    };
  }

  async function loadAwaitingCardSession(sessionId, uid) {
    const sessionRef = db.collection('payment_sessions').doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) {
      throw new HttpsError('not-found', 'ไม่พบ payment session');
    }
    const sessionData = sessionDoc.data() || {};
    if (String(sessionData.uid || '') !== uid) {
      throw new HttpsError('permission-denied', 'ไม่มีสิทธิ์เข้าถึง session');
    }
    if (
      sessionData.status !== 'awaiting_card_token' &&
      sessionData.status !== 'pending'
    ) {
      throw new HttpsError('failed-precondition', 'session ไม่พร้อมชำระด้วยบัตร');
    }
    if (String(sessionData.channel || '') !== 'omise_card') {
      throw new HttpsError('failed-precondition', 'session ไม่ใช่ช่องทางบัตร');
    }
    return { sessionRef, sessionData };
  }

  const listOmiseSavedCards = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }
      const snapshot = await db
        .collection(CUSTOMER_USERS_COLLECTION)
        .doc(request.auth.uid)
        .collection(SAVED_CARDS_SUBCOLLECTION)
        .orderBy('updatedAt', 'desc')
        .limit(10)
        .get();

      return {
        cards: snapshot.docs.map((doc) => ({
          omiseCardId: doc.id,
          ...doc.data(),
        })),
      };
    },
  );

  const completeOmiseCardPayment = onCall(
    {
      region: DEFAULT_REGION,
      enforceAppCheck: true,
      secrets: [OMISE_SECRET_KEY, OMISE_PUBLIC_KEY],
    },
    async (request) => {
      if (!request.auth?.uid) {
        throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
      }

      const uid = request.auth.uid;
      const sessionId = String(request.data?.sessionId || '').trim();
      const saveCard = request.data?.saveCard === true;
      const savedCardId = String(request.data?.savedOmiseCardId || '').trim();
      const cardToken = String(request.data?.cardToken || '').trim();
      const cardPayload = parseCardDetailsFromRequest(request.data);
      const email = String(request.data?.email || '').trim();

      if (!sessionId) {
        throw new HttpsError('invalid-argument', 'ต้องมี sessionId');
      }
      if (cardPayload) {
        throw new HttpsError(
          'invalid-precondition',
          'กรุณาชำระด้วย card token ฝั่งแอปเท่านั้น',
        );
      }
      if (!savedCardId && !cardToken) {
        throw new HttpsError('invalid-argument', 'ต้องมี cardToken หรือ savedOmiseCardId');
      }

      try {
        const { sessionRef, sessionData } = await loadAwaitingCardSession(sessionId, uid);
        const secretKey = await loadOmiseSecretKey();
        const amountSatang =
          Number(sessionData.amountSatang) ||
          toSatang(readMoney(sessionData.amount));
        const metadata = buildChargeMetadata({
          checkoutQuoteId: sessionData.checkoutQuoteId || null,
          sessionId,
          orderReference:
            sessionData.orderReference ||
            buildOrderReference({
              checkoutQuoteId: sessionData.checkoutQuoteId,
              sessionId,
              purpose: sessionData.purpose || 'cart',
            }),
          purpose: sessionData.purpose || 'cart',
          uid,
          channel: 'omise_card',
        });
        const chargeDescription = buildChargeDescription({
          orderReference: metadata.orderReference,
          amountBaht: readMoney(sessionData.amount),
          channel: 'omise_card',
        });

        let charge;

        if (savedCardId) {
          const savedDoc = await db
            .collection(CUSTOMER_USERS_COLLECTION)
            .doc(uid)
            .collection(SAVED_CARDS_SUBCOLLECTION)
            .doc(savedCardId)
            .get();
          if (!savedDoc.exists) {
            throw new HttpsError('permission-denied', 'ไม่พบบัตรที่บันทึกไว้');
          }
          const omiseCustomerId =
            String(savedDoc.data()?.omiseCustomerId || '').trim() ||
            (await getStoredOmiseCustomerId(uid));
          if (!omiseCustomerId) {
            throw new HttpsError('failed-precondition', 'ไม่พบ Omise customer');
          }
          charge = await omiseRequest(secretKey, 'POST', '/charges', {
            amount: amountSatang,
            currency: 'thb',
            customer: omiseCustomerId,
            card: savedCardId,
            description: chargeDescription,
            metadata,
          });
        } else if (cardPayload) {
          throw new HttpsError(
            'invalid-precondition',
            'กรุณาชำระด้วย card token ฝั่งแอปเท่านั้น',
          );
        } else if (cardToken) {
          if (saveCard) {
            const omiseCustomerId = await getOrCreateOmiseCustomer(
              secretKey,
              uid,
              email || request.auth.token?.email || '',
            );
            const customer = await omiseRequest(
              secretKey,
              'PATCH',
              `/customers/${omiseCustomerId}`,
              { card: cardToken },
            );
            const attachedCard = extractAttachedCard(customer);
            if (attachedCard) {
              await persistSavedCard(uid, omiseCustomerId, attachedCard);
            }
            const cardId = String(attachedCard?.id || '').trim();
            charge = await omiseRequest(secretKey, 'POST', '/charges', {
              amount: amountSatang,
              currency: 'thb',
              customer: omiseCustomerId,
              card: cardId || cardToken,
              description: chargeDescription,
              metadata,
            });
          } else {
            charge = await omiseRequest(secretKey, 'POST', '/charges', {
              amount: amountSatang,
              currency: 'thb',
              card: cardToken,
              description: chargeDescription,
              metadata,
            });
          }
        } else {
          throw new HttpsError('invalid-argument', 'ต้องมีข้อมูลบัตร');
        }

        const result = await finalizeCardChargeSession(sessionRef, sessionData, charge);
        return sessionResponse(sessionId, result);
      } catch (error) {
        logger.error('completeOmiseCardPayment failed', {
          uid,
          sessionId,
          saveCard,
          savedCardId: savedCardId || null,
          hasCardToken: Boolean(cardToken),
          hasCardDetails: Boolean(cardPayload),
          error: String(error?.message || error),
        });
        throw toHttpsErrorFromOmise(error, 'ไม่สามารถชำระด้วยบัตรได้');
      }
    },
  );

  return {
    createOmisePaymentSession,
    getOmisePaymentSession,
    createOmiseCardToken,
    listOmiseSavedCards,
    completeOmiseCardPayment,
    omiseWebhook,
    assertPaidPaymentSession,
    CHANNEL_CONFIG,
  };
}

module.exports = {
  createOmisePaymentsHandlers,
};
