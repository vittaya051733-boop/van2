const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const {
  DEFAULT_OG_IMAGE,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_WIDTH,
  parseProductRequest,
  readOgSourceImageUrl,
} = require('./product_share_common');

const thaiFontBase64 = fs
  .readFileSync(path.join(__dirname, 'assets', 'NotoSansThai.ttf'))
  .toString('base64');

function escapeXml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function truncateText(value, maxLength) {
  const normalized = String(value || '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, Math.max(0, maxLength - 1)).trim()}…`;
}

function wrapText(value, maxCharacters, maxLines) {
  const text = String(value || '').replace(/\s+/g, ' ').trim();
  if (!text) {
    return [];
  }

  const words = text.split(' ');
  const lines = [];
  let current = '';
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= maxCharacters) {
      current = candidate;
      continue;
    }
    if (current) {
      lines.push(current);
    }
    current = word;
    if (lines.length === maxLines - 1) {
      break;
    }
  }
  if (current && lines.length < maxLines) {
    lines.push(current);
  }

  const consumed = lines.join(' ').length;
  if (consumed < text.length && lines.length > 0) {
    lines[lines.length - 1] = truncateText(
      lines[lines.length - 1],
      maxCharacters,
    );
  }
  return lines;
}

function buildPriceLabel(product) {
  const price = Number(product?.price);
  if (!Number.isFinite(price) || price < 0) {
    return 'ดูราคาที่แว๊นตลาด';
  }
  const discount = Number(product?.discountPercent);
  const discountLabel =
    Number.isFinite(discount) && discount > 0 ? `  ลด ${discount}%` : '';
  return `ราคา ฿${Math.round(price).toLocaleString('en-US')}${discountLabel}`;
}

async function fetchImageBuffer(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': 'vantalad-og-image-proxy/1.0',
      Accept: 'image/*',
    },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) {
    throw new Error(`image fetch failed: ${response.status}`);
  }
  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

async function fetchFallbackImageBuffer() {
  return fetchImageBuffer(DEFAULT_OG_IMAGE);
}

async function buildOgJpeg(sourceBuffer, details = {}) {
  const photoHeight = 360;
  const photo = await sharp(sourceBuffer)
    .rotate()
    .resize(OG_IMAGE_WIDTH, photoHeight, {
      fit: 'cover',
      position: 'centre',
    })
    .toBuffer();

  const title = truncateText(details.name || 'สินค้า', 42);
  const shopName = truncateText(details.shopName || 'ร้านค้า', 48);
  const priceLabel = buildPriceLabel(details.product || {});
  const descriptionLines = wrapText(details.description, 66, 2);
  const descriptionSvg = descriptionLines
    .map(
      (line, index) =>
        `<tspan x="48" dy="${index === 0 ? 0 : 32}">${escapeXml(line)}</tspan>`,
    )
    .join('');

  const overlay = Buffer.from(`
    <svg width="${OG_IMAGE_WIDTH}" height="${OG_IMAGE_HEIGHT}" xmlns="http://www.w3.org/2000/svg">
      <style>
        @font-face {
          font-family: "Noto Sans Thai";
          src: url("data:font/ttf;base64,${thaiFontBase64}") format("truetype");
        }
        text { font-family: "Noto Sans Thai", sans-serif; }
      </style>
      <rect y="${photoHeight}" width="${OG_IMAGE_WIDTH}" height="${OG_IMAGE_HEIGHT - photoHeight}" fill="#fffaf3"/>
      <rect y="${photoHeight}" width="${OG_IMAGE_WIDTH}" height="6" fill="#f57c00"/>
      <text x="48" y="420" font-size="42" font-weight="800" fill="#111827">${escapeXml(title)}</text>
      <text x="48" y="466" font-size="26" font-weight="600" fill="#374151">ร้าน: ${escapeXml(shopName)}</text>
      <text x="1152" y="466" text-anchor="end" font-size="34" font-weight="800" fill="#f57c00">${escapeXml(priceLabel)}</text>
      <text x="48" y="516" font-size="24" font-weight="400" fill="#374151">${descriptionSvg}</text>
      <text x="1152" y="602" text-anchor="end" font-size="22" font-weight="600" fill="#6b7280">ดูสินค้าและสั่งซื้อที่ vantalad.web.app</text>
    </svg>
  `);

  return sharp({
    create: {
      width: OG_IMAGE_WIDTH,
      height: OG_IMAGE_HEIGHT,
      channels: 3,
      background: '#fffaf3',
    },
  })
    .composite([
      { input: photo, top: 0, left: 0 },
      { input: overlay, top: 0, left: 0 },
    ])
    .jpeg({ quality: 92, chromaSubsampling: '4:4:4', mozjpeg: true })
    .toBuffer();
}

async function buildShareJpeg(sourceBuffer) {
  return sharp(sourceBuffer)
    .rotate()
    .jpeg({ quality: 96, chromaSubsampling: '4:4:4' })
    .toBuffer();
}

function createProductShareOgImageHandler({ db, logger }) {
  return async (req, res) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const parsed = parseProductRequest(req);
    if (!parsed) {
      res.status(404).send('Not Found');
      return;
    }

    const { productId, shopId } = parsed;
    const isFullShareImage = /\/share\.jpg(?:\?|$)/i.test(
      String(req.originalUrl || req.url || req.path || ''),
    );

    try {
      let jpegBuffer = null;
      const productSnap = await db.collection('products').doc(productId).get();
      if (productSnap.exists) {
        const product = productSnap.data() || {};
        const sourceUrl = readOgSourceImageUrl(product);
        if (sourceUrl) {
          try {
            const sourceBuffer = await fetchImageBuffer(sourceUrl);
            if (isFullShareImage) {
              jpegBuffer = await buildShareJpeg(sourceBuffer);
            } else {
              const ownerUid = String(product.ownerUid || shopId || '').trim();
              let shopName =
                String(
                  product.shopName ||
                    product.storeName ||
                    product.merchantName ||
                    '',
                ).trim() || 'ร้านค้า';
              if (ownerUid && shopName === 'ร้านค้า') {
                const shopSnap = await db
                  .collection('public_shops')
                  .doc(ownerUid)
                  .get();
                if (shopSnap.exists) {
                  const shop = shopSnap.data() || {};
                  shopName =
                    String(
                      shop.shopName || shop.name || shop.displayName || '',
                    ).trim() || shopName;
                }
              }
              jpegBuffer = await buildOgJpeg(sourceBuffer, {
                name: product.name,
                shopName,
                description: product.description,
                product,
              });
            }
          } catch (error) {
            logger.warn('productShareOgImage source conversion failed', {
              productId,
              shopId,
              error: error?.message || String(error),
            });
          }
        }
      }

      if (!jpegBuffer) {
        try {
          const fallbackBuffer = await fetchFallbackImageBuffer();
          jpegBuffer = isFullShareImage
            ? await buildShareJpeg(fallbackBuffer)
            : await buildOgJpeg(fallbackBuffer);
        } catch (error) {
          logger.error('productShareOgImage fallback failed', {
            productId,
            error: error?.message || String(error),
          });
          res.redirect(302, DEFAULT_OG_IMAGE);
          return;
        }
      }

      res.set('Cache-Control', 'public, max-age=3600');
      res.set('Content-Type', 'image/jpeg');
      if (req.method === 'HEAD') {
        res.set('Content-Length', String(jpegBuffer.length));
        res.status(200).end();
        return;
      }
      res.status(200).send(jpegBuffer);
    } catch (error) {
      logger.error('productShareOgImage failed', {
        productId,
        shopId,
        error: error?.message || String(error),
      });
      res.redirect(302, DEFAULT_OG_IMAGE);
    }
  };
}

function createProductShareOgImageExport({
  db,
  logger,
  onRequest,
  DEFAULT_REGION,
}) {
  const handler = createProductShareOgImageHandler({ db, logger });
  return onRequest(
    {
      region: DEFAULT_REGION,
      invoker: 'public',
      memory: '512MiB',
      timeoutSeconds: 30,
    },
    handler,
  );
}

module.exports = {
  createProductShareOgImageExport,
  createProductShareOgImageHandler,
  buildOgJpeg,
  buildShareJpeg,
};
