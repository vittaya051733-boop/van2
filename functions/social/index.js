const crypto = require('crypto');
const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const { defineSecret } = require('firebase-functions/params');
const { HttpsError, onCall, onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');

const {
  DEFAULT_REGION,
  VAN4_DATABASE_ID,
  COLLECTIONS,
  PLATFORMS,
  PLATFORM_TARGETS,
  POST_STATUS,
  PLATFORM_RESULT_STATUS,
} = require('./constants');
const { getVan4Firestore } = require('./db');
const { assertVan4Admin } = require('./admin_guard');
const {
  signOAuthState,
  verifyOAuthState,
  storeOAuthState,
  saveAccountSecrets,
  loadAccountSecrets,
  deleteAccountSecrets,
} = require('./oauth_state');
const metaAdapter = require('./meta_adapter');
const youtubeAdapter = require('./youtube_adapter');
const tiktokAdapter = require('./tiktok_adapter');
const { publishSocialPostDocument, retryPlatformPublish } = require('./publisher');
const {
  syncAllSocialComments,
  replyToComment,
  ingestMetaWebhookEntry,
} = require('./comment_sync');

const SOCIAL_META_APP_ID = defineSecret('SOCIAL_META_APP_ID');
const SOCIAL_META_APP_SECRET = defineSecret('SOCIAL_META_APP_SECRET');
const SOCIAL_GOOGLE_OAUTH_CLIENT_ID = defineSecret('SOCIAL_GOOGLE_OAUTH_CLIENT_ID');
const SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET = defineSecret(
  'SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET',
);
const SOCIAL_TIKTOK_CLIENT_KEY = defineSecret('SOCIAL_TIKTOK_CLIENT_KEY');
const SOCIAL_TIKTOK_CLIENT_SECRET = defineSecret('SOCIAL_TIKTOK_CLIENT_SECRET');
const SOCIAL_OAUTH_STATE_SECRET = defineSecret('SOCIAL_OAUTH_STATE_SECRET');
const SOCIAL_META_WEBHOOK_VERIFY_TOKEN = defineSecret(
  'SOCIAL_META_WEBHOOK_VERIFY_TOKEN',
);

const SOCIAL_SECRETS = [
  SOCIAL_META_APP_ID,
  SOCIAL_META_APP_SECRET,
  SOCIAL_GOOGLE_OAUTH_CLIENT_ID,
  SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET,
  SOCIAL_TIKTOK_CLIENT_KEY,
  SOCIAL_TIKTOK_CLIENT_SECRET,
  SOCIAL_OAUTH_STATE_SECRET,
  SOCIAL_META_WEBHOOK_VERIFY_TOKEN,
];

function getOAuthRedirectUri() {
  return `https://${DEFAULT_REGION}-van-merchant.cloudfunctions.net/socialOAuthCallback`;
}

function getYouTubeOAuthConfig() {
  return {
    clientId: SOCIAL_GOOGLE_OAUTH_CLIENT_ID.value(),
    clientSecret: SOCIAL_GOOGLE_OAUTH_CLIENT_SECRET.value(),
    redirectUri: getOAuthRedirectUri(),
  };
}

function getTikTokConfig() {
  return {
    clientKey: SOCIAL_TIKTOK_CLIENT_KEY.value(),
    clientSecret: SOCIAL_TIKTOK_CLIENT_SECRET.value(),
    redirectUri: getOAuthRedirectUri(),
  };
}

function normalizePlatform(value) {
  const platform = String(value || '').trim().toLowerCase();
  if (![PLATFORMS.META, PLATFORMS.YOUTUBE, PLATFORMS.TIKTOK].includes(platform)) {
    throw new HttpsError('invalid-argument', 'แพลตฟอร์มไม่ถูกต้อง');
  }
  return platform;
}

function buildInitialPlatformResults(selectedPlatforms) {
  const results = {};
  for (const target of selectedPlatforms) {
    results[target] = { status: PLATFORM_RESULT_STATUS.PENDING };
  }
  return results;
}

exports.getSocialOAuthUrl = onCall(
  {
    region: DEFAULT_REGION,
    secrets: SOCIAL_SECRETS,
  },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const platform = normalizePlatform(request.data?.platform);
    const returnUrl = String(request.data?.returnUrl || '').trim();
    if (!returnUrl) {
      throw new HttpsError('invalid-argument', 'ไม่พบ returnUrl');
    }

    const stateId = crypto.randomUUID();
    const payload = {
      stateId,
      platform,
      uid: adminUser.uid,
      email: adminUser.email,
      returnUrl,
    };
    const state = signOAuthState(payload, SOCIAL_OAUTH_STATE_SECRET.value());
    await storeOAuthState(stateId, payload);

    const redirectUri = getOAuthRedirectUri();
    let url = '';

    if (platform === PLATFORMS.META) {
      const oauthUrl = new URL(
        `https://www.facebook.com/v21.0/dialog/oauth`,
      );
      oauthUrl.searchParams.set('client_id', SOCIAL_META_APP_ID.value());
      oauthUrl.searchParams.set('redirect_uri', redirectUri);
      oauthUrl.searchParams.set(
        'scope',
        [
          'pages_show_list',
          'pages_manage_posts',
          'pages_read_engagement',
          'instagram_basic',
          'instagram_content_publish',
        ].join(','),
      );
      oauthUrl.searchParams.set('state', state);
      url = oauthUrl.toString();
    } else if (platform === PLATFORMS.YOUTUBE) {
      const oauth2Client = youtubeAdapter.createOAuthClient(
        getYouTubeOAuthConfig(),
      );
      url = youtubeAdapter.getYouTubeAuthUrl(oauth2Client, state);
    } else if (platform === PLATFORMS.TIKTOK) {
      url = tiktokAdapter.getTikTokAuthUrl({
        clientKey: SOCIAL_TIKTOK_CLIENT_KEY.value(),
        redirectUri,
        state,
      });
    }

    return { url, platform };
  },
);

exports.socialOAuthCallback = onRequest(
  {
    region: DEFAULT_REGION,
    secrets: SOCIAL_SECRETS,
  },
  async (req, res) => {
    try {
      const code = String(req.query.code || '').trim();
      const stateRaw = String(req.query.state || '').trim();
      const oauthError = String(req.query.error || '').trim();

      const payload = verifyOAuthState(stateRaw, SOCIAL_OAUTH_STATE_SECRET.value());
      if (!payload?.stateId) {
        res.status(400).send('Invalid OAuth state');
        return;
      }

      const returnUrl = payload.returnUrl || '/';
      if (oauthError) {
        res.redirect(`${returnUrl}?social_oauth=error&reason=${encodeURIComponent(oauthError)}`);
        return;
      }
      if (!code) {
        res.redirect(`${returnUrl}?social_oauth=error&reason=missing_code`);
        return;
      }

      const db = getVan4Firestore();
      const redirectUri = getOAuthRedirectUri();
      const platform = payload.platform;

      if (platform === PLATFORMS.META) {
        const short = await metaAdapter.exchangeMetaCode({
          code,
          appId: SOCIAL_META_APP_ID.value(),
          appSecret: SOCIAL_META_APP_SECRET.value(),
          redirectUri,
        });
        const long = await metaAdapter.exchangeMetaLongLivedToken({
          shortToken: short.access_token,
          appId: SOCIAL_META_APP_ID.value(),
          appSecret: SOCIAL_META_APP_SECRET.value(),
        });
        const pages = await metaAdapter.listMetaPages(long.access_token);
        const page = pages[0];
        if (!page) {
          res.redirect(`${returnUrl}?social_oauth=error&reason=no_facebook_page`);
          return;
        }

        const accountRef = db.collection(COLLECTIONS.ACCOUNTS).doc(`meta_${page.id}`);
        await accountRef.set(
          {
            platform: PLATFORMS.META,
            displayName: page.name || 'Facebook Page',
            externalPageId: page.id,
            externalIgUserId: page.instagram_business_account?.id || '',
            igUsername: page.instagram_business_account?.username || '',
            connectedByUid: payload.uid,
            connectedByEmail: payload.email,
            active: true,
            connectedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await saveAccountSecrets(accountRef.id, {
          userAccessToken: long.access_token,
          pageAccessToken: page.access_token,
        });
      } else if (platform === PLATFORMS.YOUTUBE) {
        const oauth2Client = youtubeAdapter.createOAuthClient(
          getYouTubeOAuthConfig(),
        );
        const tokens = await youtubeAdapter.exchangeYouTubeCode(oauth2Client, code);
        const oauth2WithToken = youtubeAdapter.createOAuthClient(
          getYouTubeOAuthConfig(),
        );
        oauth2WithToken.setCredentials(tokens);
        const channel = await youtubeAdapter.getYouTubeChannelInfo(oauth2WithToken);

        const accountRef = db
          .collection(COLLECTIONS.ACCOUNTS)
          .doc(`youtube_${channel.channelId}`);
        await accountRef.set(
          {
            platform: PLATFORMS.YOUTUBE,
            displayName: channel.title,
            externalPageId: channel.channelId,
            thumbnailUrl: channel.thumbnailUrl,
            connectedByUid: payload.uid,
            connectedByEmail: payload.email,
            active: true,
            connectedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await saveAccountSecrets(accountRef.id, {
          refreshToken: tokens.refresh_token,
          accessToken: tokens.access_token,
        });
      } else if (platform === PLATFORMS.TIKTOK) {
        const tokenData = await tiktokAdapter.exchangeTikTokCode({
          clientKey: SOCIAL_TIKTOK_CLIENT_KEY.value(),
          clientSecret: SOCIAL_TIKTOK_CLIENT_SECRET.value(),
          code,
          redirectUri,
        });
        const user = await tiktokAdapter.getTikTokUserInfo(tokenData.access_token);
        const openId = user.open_id || crypto.randomUUID();
        const accountRef = db.collection(COLLECTIONS.ACCOUNTS).doc(`tiktok_${openId}`);
        await accountRef.set(
          {
            platform: PLATFORMS.TIKTOK,
            displayName: user.display_name || 'TikTok',
            externalPageId: openId,
            thumbnailUrl: user.avatar_url || '',
            connectedByUid: payload.uid,
            connectedByEmail: payload.email,
            active: true,
            connectedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await saveAccountSecrets(accountRef.id, {
          accessToken: tokenData.access_token,
          refreshToken: tokenData.refresh_token,
        });
      }

      res.redirect(`${returnUrl}?social_oauth=success&platform=${encodeURIComponent(platform)}`);
    } catch (error) {
      logger.error('socialOAuthCallback failed', { error: String(error) });
      res.status(500).send('OAuth callback failed');
    }
  },
);

exports.listSocialAccounts = onCall(
  { region: DEFAULT_REGION },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const db = getVan4Firestore();
    const snap = await db
      .collection(COLLECTIONS.ACCOUNTS)
      .where('connectedByUid', '==', adminUser.uid)
      .where('active', '==', true)
      .get();

    const accounts = snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        platform: data.platform,
        displayName: data.displayName || '',
        externalPageId: data.externalPageId || '',
        igUsername: data.igUsername || '',
        thumbnailUrl: data.thumbnailUrl || '',
        connectedAt: data.connectedAt?.toDate?.()?.toISOString?.() || null,
      };
    });
    return { accounts };
  },
);

exports.disconnectSocialAccount = onCall(
  { region: DEFAULT_REGION },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const accountId = String(request.data?.accountId || '').trim();
    if (!accountId) {
      throw new HttpsError('invalid-argument', 'ไม่พบ accountId');
    }

    const db = getVan4Firestore();
    const ref = db.collection(COLLECTIONS.ACCOUNTS).doc(accountId);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.connectedByUid !== adminUser.uid) {
      throw new HttpsError('permission-denied', 'ไม่พบบัญชี');
    }

    await ref.set(
      {
        active: false,
        disconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await deleteAccountSecrets(accountId);
    return { success: true };
  },
);

exports.createSocialPost = onCall(
  { region: DEFAULT_REGION },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const postId = String(request.data?.postId || '').trim();
    const caption = String(request.data?.caption || '').trim();
    const sourceVideoPath = String(request.data?.sourceVideoPath || '').trim();
    const thumbnailPath = String(request.data?.thumbnailPath || '').trim();
    const rawPlatforms = request.data?.selectedPlatforms;
    const rawHashtags = request.data?.hashtags;

    if (!postId || !sourceVideoPath) {
      throw new HttpsError('invalid-argument', 'ต้องมี postId และ sourceVideoPath');
    }
    if (!caption) {
      throw new HttpsError('invalid-argument', 'กรุณาใส่ caption');
    }

    const allowedTargets = Object.values(PLATFORM_TARGETS);
    const selectedPlatforms = Array.isArray(rawPlatforms)
      ? rawPlatforms
          .map((item) => String(item).trim())
          .filter((item) => allowedTargets.includes(item))
      : [];
    if (selectedPlatforms.length === 0) {
      throw new HttpsError('invalid-argument', 'เลือกอย่างน้อย 1 แพลตฟอร์ม');
    }

    const hashtags = Array.isArray(rawHashtags)
      ? rawHashtags.map((item) => String(item).trim()).filter(Boolean)
      : [];

    const db = getVan4Firestore();
    await db.collection(COLLECTIONS.POSTS).doc(postId).set(
      {
        createdBy: adminUser.uid,
        createdByEmail: adminUser.email,
        caption,
        hashtags,
        sourceVideoPath,
        thumbnailPath: thumbnailPath || null,
        selectedPlatforms,
        platformResults: buildInitialPlatformResults(selectedPlatforms),
        status: POST_STATUS.PUBLISHING,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { postId, status: POST_STATUS.PUBLISHING };
  },
);

exports.publishSocialPostWorker = onDocumentCreated(
  {
    document: `${COLLECTIONS.POSTS}/{postId}`,
    database: VAN4_DATABASE_ID,
    region: DEFAULT_REGION,
    secrets: SOCIAL_SECRETS,
  },
  async (event) => {
    const postId = event.params.postId;
    const data = event.data?.data();
    if (!data || data.status !== POST_STATUS.PUBLISHING) {
      return;
    }
    await publishSocialPostDocument(
      postId,
      getYouTubeOAuthConfig(),
      getTikTokConfig(),
    );
  },
);

exports.retrySocialPostPlatform = onCall(
  {
    region: DEFAULT_REGION,
    secrets: SOCIAL_SECRETS,
  },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const postId = String(request.data?.postId || '').trim();
    const target = String(request.data?.platformTarget || '').trim();
    if (!postId || !Object.values(PLATFORM_TARGETS).includes(target)) {
      throw new HttpsError('invalid-argument', 'ข้อมูลไม่ครบ');
    }

    const db = getVan4Firestore();
    const snap = await db.collection(COLLECTIONS.POSTS).doc(postId).get();
    if (!snap.exists || snap.data()?.createdBy !== adminUser.uid) {
      throw new HttpsError('permission-denied', 'ไม่พบโพสต์');
    }

    await retryPlatformPublish(
      postId,
      target,
      getYouTubeOAuthConfig(),
      getTikTokConfig(),
    );
    return { success: true };
  },
);

exports.metaSocialWebhook = onRequest(
  {
    region: DEFAULT_REGION,
    secrets: [SOCIAL_META_WEBHOOK_VERIFY_TOKEN],
  },
  async (req, res) => {
    if (req.method === 'GET') {
      const mode = req.query['hub.mode'];
      const token = req.query['hub.verify_token'];
      const challenge = req.query['hub.challenge'];
      if (
        mode === 'subscribe' &&
        token === SOCIAL_META_WEBHOOK_VERIFY_TOKEN.value()
      ) {
        res.status(200).send(challenge);
        return;
      }
      res.status(403).send('Forbidden');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).send('Method not allowed');
      return;
    }

    try {
      const body = req.body || {};
      for (const entry of body.entry || []) {
        await ingestMetaWebhookEntry(entry);
      }
      res.status(200).json({ success: true });
    } catch (error) {
      logger.error('metaSocialWebhook failed', { error: String(error) });
      res.status(500).json({ success: false });
    }
  },
);

exports.syncSocialComments = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: DEFAULT_REGION,
    timeZone: 'Asia/Bangkok',
    secrets: SOCIAL_SECRETS,
  },
  async () => {
    await syncAllSocialComments(getYouTubeOAuthConfig(), getTikTokConfig());
  },
);

exports.replySocialComment = onCall(
  {
    region: DEFAULT_REGION,
    secrets: SOCIAL_SECRETS,
  },
  async (request) => {
    const adminUser = await assertVan4Admin(request);
    const commentId = String(request.data?.commentId || '').trim();
    const message = String(request.data?.message || '').trim();
    if (!commentId || !message) {
      throw new HttpsError('invalid-argument', 'ข้อมูลไม่ครบ');
    }

    await replyToComment({
      commentId,
      message,
      adminUid: adminUser.uid,
      adminEmail: adminUser.email,
      oauthConfig: getYouTubeOAuthConfig(),
      tiktokConfig: getTikTokConfig(),
    });
    return { success: true };
  },
);
