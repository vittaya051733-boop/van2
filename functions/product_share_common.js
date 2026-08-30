const DEFAULT_SITE = 'https://vantalad.web.app';
const DEFAULT_OG_IMAGE = `${DEFAULT_SITE}/icons/Icon-512.png`;
const OG_IMAGE_WIDTH = 1200;
const OG_IMAGE_HEIGHT = 630;

const SOCIAL_CRAWLER_PATTERN =
  /facebookexternalhit|facebot|meta-inspector|twitterbot|linkedinbot|slackbot|telegrambot|line-poker|whatsapp|discordbot|googlebot|bingpreview|applebot|pinterest|vkshare|embedly|quora/i;

function parseProductPath(rawPath) {
  const segments = String(rawPath || '')
    .split('/')
    .map((segment) => segment.trim())
    .filter(Boolean);
  const productIndex = segments.findIndex(
    (segment) => segment.toLowerCase() === 'product',
  );
  if (productIndex < 0 || productIndex + 1 >= segments.length) {
    return null;
  }

  let productId = segments[productIndex + 1];
  try {
    productId = decodeURIComponent(productId);
  } catch (_) {}
  productId = String(productId || '').trim();
  if (!productId) {
    return null;
  }

  return productId;
}

function parseProductRequest(req) {
  const shopId = String(req.query?.shop || '').trim() || null;
  const candidates = [req.path, req.url, req.originalUrl]
    .filter(Boolean)
    .map((value) => String(value).split('?')[0]);

  for (const rawPath of candidates) {
    const productId = parseProductPath(rawPath);
    if (productId) {
      return { productId, shopId };
    }
  }

  return null;
}

function readOgSourceImageUrl(data) {
  if (!data || typeof data !== 'object') {
    return null;
  }

  const videoUrl = String(data.videoUrl || '').trim();
  const videoThumb = String(data.videoThumbnailUrl || '').trim();

  const images = data.imageUrls;
  if (Array.isArray(images)) {
    for (const entry of images) {
      const url = String(entry || '').trim();
      if (url && url !== videoUrl && url !== videoThumb) {
        return url;
      }
    }
  }

  const thumbnails = data.thumbnailUrls;
  if (Array.isArray(thumbnails)) {
    for (const entry of thumbnails) {
      const url = String(entry || '').trim();
      if (url) {
        return url;
      }
    }
  }

  for (const key of ['imageUrl', 'photoUrl', 'productImage']) {
    const url = String(data[key] || '').trim();
    if (url && url !== videoUrl && url !== videoThumb) {
      return url;
    }
  }

  if (videoThumb) {
    return videoThumb;
  }

  return null;
}

function buildCanonicalUrl(productId, shopId) {
  const path = `/product/${encodeURIComponent(productId)}`;
  const query = shopId ? `?shop=${encodeURIComponent(shopId)}` : '';
  return `${DEFAULT_SITE}${path}${query}`;
}

function buildOgImageProxyUrl(productId, shopId) {
  const path = `/product/${encodeURIComponent(productId)}/og.jpg`;
  const query = new URLSearchParams({ card: '2' });
  if (shopId) {
    query.set('shop', shopId);
  }
  return `${DEFAULT_SITE}${path}?${query.toString()}`;
}

function isSocialCrawler(req) {
  const userAgent = String(
    req.get?.('user-agent') || req.headers?.['user-agent'] || '',
  );
  return SOCIAL_CRAWLER_PATTERN.test(userAgent);
}

module.exports = {
  DEFAULT_SITE,
  DEFAULT_OG_IMAGE,
  OG_IMAGE_WIDTH,
  OG_IMAGE_HEIGHT,
  SOCIAL_CRAWLER_PATTERN,
  parseProductPath,
  parseProductRequest,
  readOgSourceImageUrl,
  buildCanonicalUrl,
  buildOgImageProxyUrl,
  isSocialCrawler,
};
