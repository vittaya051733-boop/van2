const { GoogleAuth } = require('google-auth-library');

const translationAuth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/cloud-platform'],
});

const MAX_TEXT_LENGTH = 4000;
const MAX_BATCH = 8;

function normalizeText(value) {
  const text = String(value || '').trim();
  if (!text) {
    return '';
  }
  return text.length > MAX_TEXT_LENGTH ? text.slice(0, MAX_TEXT_LENGTH) : text;
}

async function translateThToEnBatch(texts) {
  const queue = texts
    .map((entry) => normalizeText(entry))
    .filter((entry) => entry.length > 0);
  if (queue.length === 0) {
    return [];
  }
  if (queue.length > MAX_BATCH) {
    throw new Error('translation batch too large');
  }

  const client = await translationAuth.getClient();
  const response = await client.request({
    url: 'https://translation.googleapis.com/language/translate/v2',
    method: 'POST',
    data: {
      q: queue,
      source: 'th',
      target: 'en',
      format: 'text',
    },
  });

  const translations = response?.data?.data?.translations;
  if (!Array.isArray(translations)) {
    throw new Error('unexpected translation response');
  }

  return translations.map((entry) => String(entry?.translatedText || '').trim());
}

function cachedTranslationFields(data) {
  const nameEn = normalizeText(data?.nameEn);
  const descriptionEn = normalizeText(data?.descriptionEn);
  return {
    nameEn,
    descriptionEn,
    hasName: nameEn.length > 0,
    hasDescription: descriptionEn.length > 0,
  };
}

function createEnsureProductTranslationHandler({
  db,
  FieldValue,
  HttpsError,
  logger,
  assertCallableRateLimit,
}) {
  return async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
    }

    const productId = String(request.data?.productId || '').trim();
    if (!productId) {
      throw new HttpsError('invalid-argument', 'productId ไม่ถูกต้อง');
    }

    const forceRefresh = request.data?.forceRefresh === true;
    await assertCallableRateLimit({
      key: `ensureProductTranslation:${request.auth.uid}`,
      maxAttempts: 60,
      windowMs: 60 * 1000,
      message: 'คำขอแปลสินค้ามากเกินไป กรุณารอสักครู่แล้วลองใหม่',
    });

    const productRef = db.collection('products').doc(productId);
    const snapshot = await productRef.get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'ไม่พบสินค้า');
    }

    const data = snapshot.data() || {};
    const sourceName = normalizeText(data.name);
    const sourceDescription = normalizeText(data.description);
    const cached = cachedTranslationFields(data);

    if (!forceRefresh && cached.hasName) {
      const needsDescription =
        sourceDescription.length > 0 && !cached.hasDescription;
      if (!needsDescription) {
        return {
          productId,
          cached: true,
          nameEn: cached.nameEn,
          descriptionEn: cached.descriptionEn,
        };
      }
    }

    const toTranslate = [];
    const fields = [];
    if (sourceName && (forceRefresh || !cached.hasName)) {
      toTranslate.push(sourceName);
      fields.push('name');
    }
    if (sourceDescription && (forceRefresh || !cached.hasDescription)) {
      toTranslate.push(sourceDescription);
      fields.push('description');
    }

    if (toTranslate.length === 0) {
      return {
        productId,
        cached: true,
        nameEn: cached.nameEn,
        descriptionEn: cached.descriptionEn,
      };
    }

    let translated;
    try {
      translated = await translateThToEnBatch(toTranslate);
    } catch (error) {
      logger.error('ensureProductTranslation translate failed', {
        productId,
        message: error instanceof Error ? error.message : String(error),
      });
      throw new HttpsError('unavailable', 'แปลข้อความไม่สำเร็จ กรุณาลองใหม่');
    }

    const updates = {
      translationSource: 'google',
      translatedAt: FieldValue.serverTimestamp(),
    };
    let nameEn = cached.nameEn;
    let descriptionEn = cached.descriptionEn;

    fields.forEach((field, index) => {
      const value = translated[index] || '';
      if (field === 'name') {
        nameEn = value || sourceName;
        updates.nameEn = nameEn;
      } else if (field === 'description') {
        descriptionEn = value || sourceDescription;
        updates.descriptionEn = descriptionEn;
      }
    });

    await productRef.set(updates, { merge: true });

    return {
      productId,
      cached: false,
      nameEn,
      descriptionEn,
    };
  };
}

module.exports = {
  createEnsureProductTranslationHandler,
  translateThToEnBatch,
};
