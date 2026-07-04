const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {
  COLLECTIONS,
  PLATFORM_TARGETS,
  POST_STATUS,
  PLATFORM_RESULT_STATUS,
  PLATFORMS,
} = require('./constants');
const { getVan4Firestore, getVan4StorageBucket } = require('./db');
const { loadAccountSecrets, saveAccountSecrets } = require('./oauth_state');
const metaAdapter = require('./meta_adapter');
const youtubeAdapter = require('./youtube_adapter');
const tiktokAdapter = require('./tiktok_adapter');

async function downloadSourceVideo(storagePath) {
  const bucket = getVan4StorageBucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new Error(`Video not found: ${storagePath}`);
  }
  const [buffer] = await file.download();
  return buffer;
}

async function getSignedVideoUrl(storagePath, expiresMs = 60 * 60 * 1000) {
  const bucket = getVan4StorageBucket();
  const file = bucket.file(storagePath);
  const [url] = await file.getSignedUrl({
    action: 'read',
    expires: Date.now() + expiresMs,
  });
  return url;
}

async function findAccountByPlatform(platform, adminUid) {
  const db = getVan4Firestore();
  const snap = await db
    .collection(COLLECTIONS.ACCOUNTS)
    .where('platform', '==', platform)
    .where('connectedByUid', '==', adminUid)
    .where('active', '==', true)
    .limit(1)
    .get();
  if (snap.empty) {
    return null;
  }
  const doc = snap.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function updatePlatformResult(postRef, target, patch) {
  await postRef.set(
    {
      [`platformResults.${target}`]: patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function finalizePostStatus(postRef, postData) {
  const results = postData.platformResults || {};
  const values = Object.values(results);
  const allPublished = values.every(
    (item) =>
      item?.status === PLATFORM_RESULT_STATUS.PUBLISHED ||
      item?.status === PLATFORM_RESULT_STATUS.SKIPPED,
  );
  const anyPublished = values.some(
    (item) => item?.status === PLATFORM_RESULT_STATUS.PUBLISHED,
  );
  const allFailed = values.every(
    (item) =>
      item?.status === PLATFORM_RESULT_STATUS.FAILED ||
      item?.status === PLATFORM_RESULT_STATUS.SKIPPED,
  );

  let status = POST_STATUS.PUBLISHING;
  if (allPublished && anyPublished) {
    status = POST_STATUS.PUBLISHED;
  } else if (anyPublished) {
    status = POST_STATUS.PARTIAL_FAILED;
  } else if (allFailed) {
    status = POST_STATUS.FAILED;
  }

  await postRef.set(
    {
      status,
      publishedAt:
        anyPublished && status !== POST_STATUS.PUBLISHING
          ? admin.firestore.FieldValue.serverTimestamp()
          : postData.publishedAt || null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function publishMetaTargets({ postRef, postData, adminUid, videoUrl }) {
  const account = await findAccountByPlatform(PLATFORMS.META, adminUid);
  if (!account) {
    for (const target of [PLATFORM_TARGETS.META_FB, PLATFORM_TARGETS.META_IG]) {
      if (postData.selectedPlatforms?.includes(target)) {
        await updatePlatformResult(postRef, target, {
          status: PLATFORM_RESULT_STATUS.FAILED,
          error: 'ยังไม่ได้เชื่อมบัญชี Meta',
        });
      }
    }
    return;
  }

  const secrets = await loadAccountSecrets(account.id);
  const pageAccessToken = secrets?.pageAccessToken;
  const pageId = account.externalPageId;
  const igUserId = account.externalIgUserId;

  if (!pageAccessToken || !pageId) {
    throw new Error('Meta account missing page token');
  }

  const caption = [postData.caption, ...(postData.hashtags || [])]
    .filter(Boolean)
    .join(' ');

  if (postData.selectedPlatforms?.includes(PLATFORM_TARGETS.META_FB)) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.META_FB, {
      status: PLATFORM_RESULT_STATUS.PUBLISHING,
    });
    try {
      const result = await metaAdapter.publishFacebookVideo({
        pageId,
        pageAccessToken,
        videoUrl,
        caption,
      });
      await updatePlatformResult(postRef, PLATFORM_TARGETS.META_FB, {
        status: PLATFORM_RESULT_STATUS.PUBLISHED,
        externalPostId: result.id || '',
        url: result.id ? `https://facebook.com/${result.id}` : '',
      });
    } catch (error) {
      await updatePlatformResult(postRef, PLATFORM_TARGETS.META_FB, {
        status: PLATFORM_RESULT_STATUS.FAILED,
        error: error.message || String(error),
      });
    }
  }

  if (postData.selectedPlatforms?.includes(PLATFORM_TARGETS.META_IG)) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.META_IG, {
      status: PLATFORM_RESULT_STATUS.PUBLISHING,
    });
    if (!igUserId) {
      await updatePlatformResult(postRef, PLATFORM_TARGETS.META_IG, {
        status: PLATFORM_RESULT_STATUS.FAILED,
        error: 'Page ไม่มี Instagram Business เชื่อมอยู่',
      });
    } else {
      try {
        const result = await metaAdapter.publishInstagramReel({
          igUserId,
          pageAccessToken,
          videoUrl,
          caption,
        });
        await updatePlatformResult(postRef, PLATFORM_TARGETS.META_IG, {
          status: PLATFORM_RESULT_STATUS.PUBLISHED,
          externalPostId: result.id || '',
          url: '',
        });
      } catch (error) {
        await updatePlatformResult(postRef, PLATFORM_TARGETS.META_IG, {
          status: PLATFORM_RESULT_STATUS.FAILED,
          error: error.message || String(error),
        });
      }
    }
  }
}

async function publishYouTubeTarget({
  postRef,
  postData,
  adminUid,
  videoBuffer,
  oauthConfig,
}) {
  if (!postData.selectedPlatforms?.includes(PLATFORM_TARGETS.YOUTUBE)) {
    return;
  }

  const account = await findAccountByPlatform(PLATFORMS.YOUTUBE, adminUid);
  if (!account) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.YOUTUBE, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: 'ยังไม่ได้เชื่อม YouTube',
    });
    return;
  }

  const secrets = await loadAccountSecrets(account.id);
  if (!secrets?.refreshToken) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.YOUTUBE, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: 'YouTube token หมดอายุ — เชื่อมใหม่',
    });
    return;
  }

  await updatePlatformResult(postRef, PLATFORM_TARGETS.YOUTUBE, {
    status: PLATFORM_RESULT_STATUS.PUBLISHING,
  });

  try {
    const oauth2Client = youtubeAdapter.createOAuthClient(oauthConfig);
    const tokens = await youtubeAdapter.refreshYouTubeTokens(
      oauth2Client,
      secrets.refreshToken,
    );
    if (tokens.refresh_token) {
      await saveAccountSecrets(account.id, {
        refreshToken: tokens.refresh_token,
        accessToken: tokens.access_token,
      });
    }
    oauth2Client.setCredentials(tokens);

    const caption = postData.caption || 'VANTALAD';
    const result = await youtubeAdapter.uploadYouTubeVideo({
      oauth2Client,
      videoBuffer,
      title: caption.slice(0, 100),
      description: caption,
      tags: postData.hashtags || [],
    });

    await updatePlatformResult(postRef, PLATFORM_TARGETS.YOUTUBE, {
      status: PLATFORM_RESULT_STATUS.PUBLISHED,
      externalPostId: result.videoId,
      url: result.url,
    });
  } catch (error) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.YOUTUBE, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: error.message || String(error),
    });
  }
}

async function publishTikTokTarget({
  postRef,
  postData,
  adminUid,
  videoBuffer,
  tiktokConfig,
}) {
  if (!postData.selectedPlatforms?.includes(PLATFORM_TARGETS.TIKTOK)) {
    return;
  }

  const account = await findAccountByPlatform(PLATFORMS.TIKTOK, adminUid);
  if (!account) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.TIKTOK, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: 'ยังไม่ได้เชื่อม TikTok',
    });
    return;
  }

  const secrets = await loadAccountSecrets(account.id);
  let accessToken = secrets?.accessToken;
  if (!accessToken && secrets?.refreshToken) {
    const refreshed = await tiktokAdapter.refreshTikTokToken({
      clientKey: tiktokConfig.clientKey,
      clientSecret: tiktokConfig.clientSecret,
      refreshToken: secrets.refreshToken,
    });
    accessToken = refreshed.access_token;
    await saveAccountSecrets(account.id, {
      accessToken: refreshed.access_token,
      refreshToken: refreshed.refresh_token || secrets.refreshToken,
    });
  }

  if (!accessToken) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.TIKTOK, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: 'TikTok token หมดอายุ — เชื่อมใหม่',
    });
    return;
  }

  await updatePlatformResult(postRef, PLATFORM_TARGETS.TIKTOK, {
    status: PLATFORM_RESULT_STATUS.PUBLISHING,
  });

  try {
    const caption = postData.caption || '';
    const result = await tiktokAdapter.publishTikTokVideo({
      accessToken,
      videoBuffer,
      caption,
    });
    await updatePlatformResult(postRef, PLATFORM_TARGETS.TIKTOK, {
      status: PLATFORM_RESULT_STATUS.PUBLISHED,
      externalPostId: result.publishId,
      url: result.url,
    });
  } catch (error) {
    await updatePlatformResult(postRef, PLATFORM_TARGETS.TIKTOK, {
      status: PLATFORM_RESULT_STATUS.FAILED,
      error: error.message || String(error),
    });
  }
}

async function publishSocialPostDocument(postId, oauthConfig, tiktokConfig) {
  const db = getVan4Firestore();
  const postRef = db.collection(COLLECTIONS.POSTS).doc(postId);
  const snap = await postRef.get();
  if (!snap.exists) {
    return;
  }

  const postData = snap.data() || {};
  if (postData.status !== POST_STATUS.PUBLISHING) {
    return;
  }

  const adminUid = postData.createdBy;
  const storagePath = postData.sourceVideoPath;
  if (!storagePath) {
    await postRef.set(
      {
        status: POST_STATUS.FAILED,
        error: 'ไม่พบไฟล์วิดีโอ',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  try {
    const [videoUrl, videoBuffer] = await Promise.all([
      getSignedVideoUrl(storagePath),
      downloadSourceVideo(storagePath),
    ]);

    await publishMetaTargets({ postRef, postData, adminUid, videoUrl });
    await publishYouTubeTarget({
      postRef,
      postData,
      adminUid,
      videoBuffer,
      oauthConfig,
    });
    await publishTikTokTarget({
      postRef,
      postData,
      adminUid,
      videoBuffer,
      tiktokConfig,
    });

    const refreshed = await postRef.get();
    await finalizePostStatus(postRef, refreshed.data() || {});
  } catch (error) {
    logger.error('publishSocialPostDocument failed', { postId, error: String(error) });
    await postRef.set(
      {
        status: POST_STATUS.FAILED,
        error: error.message || String(error),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function retryPlatformPublish(postId, target, oauthConfig, tiktokConfig) {
  const db = getVan4Firestore();
  const postRef = db.collection(COLLECTIONS.POSTS).doc(postId);
  const snap = await postRef.get();
  if (!snap.exists) {
    throw new Error('Post not found');
  }
  const postData = snap.data() || {};
  const storagePath = postData.sourceVideoPath;
  const videoUrl = await getSignedVideoUrl(storagePath);
  const videoBuffer = await downloadSourceVideo(storagePath);

  if (target === PLATFORM_TARGETS.META_FB || target === PLATFORM_TARGETS.META_IG) {
    const narrowed = {
      ...postData,
      selectedPlatforms: [target],
    };
    await publishMetaTargets({
      postRef,
      postData: narrowed,
      adminUid: postData.createdBy,
      videoUrl,
    });
  } else if (target === PLATFORM_TARGETS.YOUTUBE) {
    await publishYouTubeTarget({
      postRef,
      postData: { ...postData, selectedPlatforms: [PLATFORM_TARGETS.YOUTUBE] },
      adminUid: postData.createdBy,
      videoBuffer,
      oauthConfig,
    });
  } else if (target === PLATFORM_TARGETS.TIKTOK) {
    await publishTikTokTarget({
      postRef,
      postData: { ...postData, selectedPlatforms: [PLATFORM_TARGETS.TIKTOK] },
      adminUid: postData.createdBy,
      videoBuffer,
      tiktokConfig,
    });
  }

  const refreshed = await postRef.get();
  await finalizePostStatus(postRef, refreshed.data() || {});
}

module.exports = {
  publishSocialPostDocument,
  retryPlatformPublish,
  getSignedVideoUrl,
};
