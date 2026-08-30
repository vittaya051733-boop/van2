const {
  DEFAULT_OG_IMAGE,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_WIDTH,
  buildCanonicalUrl,
  buildOgImageProxyUrl,
  isSocialCrawler,
  parseProductRequest,
} = require('./product_share_common');

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function formatPrice(data) {
  const price = Number(data?.price);
  if (!Number.isFinite(price) || price <= 0) {
    return null;
  }
  return `฿${Math.round(price).toLocaleString('en-US')}`;
}

function buildPreviewHtml({
  title,
  description,
  imageUrl,
  canonicalUrl,
  serveFlutterShell,
}) {
  const safeTitle = escapeHtml(title);
  const safeDescription = escapeHtml(description);
  const safeImage = escapeHtml(imageUrl || DEFAULT_OG_IMAGE);
  const safeUrl = escapeHtml(canonicalUrl);

  const flutterShell = serveFlutterShell
    ? `
  <base href="/">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Sans+Thai:wght@400;500;600;700;800;900&amp;display=swap">
  <link rel="icon" type="image/png" href="/favicon.png">
  <style>
    #flutter-loading {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: "Noto Sans Thai", sans-serif;
      color: #374151;
      background: #fff7ed;
    }
  </style>`
    : '';

  const flutterBody = serveFlutterShell
    ? `
<body>
  <div id="flutter-loading">กำลังโหลด แว๊นตลาด...</div>
  <script src="/flutter_bootstrap.js" async></script>
</body>`
    : `
<body>
  <p>${safeTitle}</p>
  <p><a href="${safeUrl}">เปิดในแว๊นตลาด</a></p>
</body>`;

  return `<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${safeTitle}</title>
  <meta name="description" content="${safeDescription}">
  <meta property="og:site_name" content="แว๊นตลาด">
  <meta property="og:type" content="website">
  <meta property="og:title" content="${safeTitle}">
  <meta property="og:description" content="${safeDescription}">
  <meta property="og:url" content="${safeUrl}">
  <meta property="og:image" content="${safeImage}">
  <meta property="og:image:secure_url" content="${safeImage}">
  <meta property="og:image:type" content="image/jpeg">
  <meta property="og:image:width" content="${OG_IMAGE_WIDTH}">
  <meta property="og:image:height" content="${OG_IMAGE_HEIGHT}">
  <meta property="og:locale" content="th_TH">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDescription}">
  <meta name="twitter:image" content="${safeImage}">
  <link rel="canonical" href="${safeUrl}">${flutterShell}
</head>${flutterBody}
</html>`;
}

function createProductSharePreviewHandler({ db, logger }) {
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
    const canonicalUrl = buildCanonicalUrl(productId, shopId);
    const ogImageUrl = buildOgImageProxyUrl(productId, shopId);

    try {
      const productSnap = await db.collection('products').doc(productId).get();
      if (!productSnap.exists) {
        const html = buildPreviewHtml({
          title: 'สินค้าไม่พบ — แว๊นตลาด',
          description: 'ลิงก์สินค้านี้อาจถูกลบหรือปิดการขายแล้ว',
          imageUrl: DEFAULT_OG_IMAGE,
          canonicalUrl,
          serveFlutterShell: !isSocialCrawler(req),
        });
        res.set('Cache-Control', 'public, max-age=120');
        res.status(404).type('html').send(html);
        return;
      }

      const product = productSnap.data() || {};
      const ownerUid = String(product.ownerUid || '').trim();
      const resolvedShopId = ownerUid || shopId || null;
      let shopName = 'ร้านค้า';
      if (resolvedShopId) {
        const shopSnap = await db.collection('public_shops').doc(resolvedShopId).get();
        if (shopSnap.exists) {
          const shop = shopSnap.data() || {};
          shopName =
            String(shop.shopName || shop.name || shop.displayName || '').trim() ||
            shopName;
        }
      }

      const productName = String(product.name || 'สินค้า').trim() || 'สินค้า';
      const priceLabel = formatPrice(product);
      const descriptionParts = [`ร้าน: ${shopName}`];
      if (priceLabel) {
        descriptionParts.push(`ราคา ${priceLabel}`);
      }
      descriptionParts.push('สั่งผ่านแว๊นตลาด');
      const description = descriptionParts.join(' · ');

      const html = buildPreviewHtml({
        title: `${productName} — แว๊นตลาด`,
        description,
        imageUrl: ogImageUrl,
        canonicalUrl,
        serveFlutterShell: !isSocialCrawler(req),
      });

      res.set('Cache-Control', 'public, max-age=300');
      if (req.method === 'HEAD') {
        res.status(200).end();
        return;
      }
      res.status(200).type('html').send(html);
    } catch (error) {
      logger.error('productSharePreview failed', {
        productId,
        shopId,
        error: error?.message || String(error),
      });
      res.status(500).send('Internal Server Error');
    }
  };
}

function createProductSharePreviewExport({
  db,
  logger,
  onRequest,
  DEFAULT_REGION,
}) {
  const handler = createProductSharePreviewHandler({ db, logger });
  return onRequest(
    {
      region: DEFAULT_REGION,
      invoker: 'public',
      memory: '256MiB',
      timeoutSeconds: 15,
    },
    handler,
  );
}

module.exports = {
  createProductSharePreviewExport,
  createProductSharePreviewHandler,
};
