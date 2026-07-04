const admin = require('firebase-admin');
const logger = require('firebase-functions/logger');
const {
  COLLECTIONS,
  PLATFORM_TARGETS,
  COMMENT_REPLY_STATUS,
  PLATFORMS,
} = require('./constants');
const { getVan4Firestore } = require('./db');
const { loadAccountSecrets } = require('./oauth_state');
const metaAdapter = require('./meta_adapter');
const youtubeAdapter = require('./youtube_adapter');
const tiktokAdapter = require('./tiktok_adapter');

function commentDocId(platform, externalCommentId) {
  return `${platform}_${externalCommentId}`.replace(/[^\w-]/g, '_').slice(0, 500);
}

async function upsertComment({
  postId,
  platform,
  externalCommentId,
  threadId,
  authorName,
  authorAvatarUrl,
  text,
  createdAt,
}) {
  const db = getVan4Firestore();
  const id = commentDocId(platform, externalCommentId);
  const ref = db.collection(COLLECTIONS.COMMENTS).doc(id);
  const existing = await ref.get();
  const preserveReply = existing.exists ? existing.data()?.replyStatus : COMMENT_REPLY_STATUS.OPEN;

  await ref.set(
    {
      postId,
      platform,
      externalCommentId,
      threadId: threadId || externalCommentId,
      authorName: authorName || '',
      authorAvatarUrl: authorAvatarUrl || '',
      text: text || '',
      createdAt: createdAt ? new Date(createdAt) : admin.firestore.FieldValue.serverTimestamp(),
      replyStatus: preserveReply || COMMENT_REPLY_STATUS.OPEN,
      syncedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function syncMetaCommentsForPost(postDoc) {
  const postData = postDoc.data() || {};
  const results = postData.platformResults || {};
  const fb = results[PLATFORM_TARGETS.META_FB];
  const ig = results[PLATFORM_TARGETS.META_IG];
  const externalPostId = fb?.externalPostId || ig?.externalPostId;
  if (!externalPostId) {
    return;
  }

  const db = getVan4Firestore();
  const accountSnap = await db
    .collection(COLLECTIONS.ACCOUNTS)
    .where('platform', '==', PLATFORMS.META)
    .where('connectedByUid', '==', postData.createdBy)
    .where('active', '==', true)
    .limit(1)
    .get();
  if (accountSnap.empty) {
    return;
  }

  const account = accountSnap.docs[0];
  const secrets = await loadAccountSecrets(account.id);
  const token = secrets?.pageAccessToken;
  if (!token) {
    return;
  }

  const comments = await metaAdapter.fetchMetaComments({
    objectId: externalPostId,
    accessToken: token,
  });

  for (const item of comments) {
    await upsertComment({
      postId: postDoc.id,
      platform: PLATFORM_TARGETS.META_FB,
      externalCommentId: item.id,
      threadId: item.id,
      authorName: item.from?.name || '',
      authorAvatarUrl: item.from?.picture?.data?.url || '',
      text: item.message || '',
      createdAt: item.created_time,
    });
  }
}

async function syncYouTubeCommentsForPost(postDoc, oauthConfig) {
  const postData = postDoc.data() || {};
  const result = postData.platformResults?.[PLATFORM_TARGETS.YOUTUBE];
  const videoId = result?.externalPostId;
  if (!videoId) {
    return;
  }

  const db = getVan4Firestore();
  const accountSnap = await db
    .collection(COLLECTIONS.ACCOUNTS)
    .where('platform', '==', PLATFORMS.YOUTUBE)
    .where('connectedByUid', '==', postData.createdBy)
    .where('active', '==', true)
    .limit(1)
    .get();
  if (accountSnap.empty) {
    return;
  }

  const secrets = await loadAccountSecrets(accountSnap.docs[0].id);
  if (!secrets?.refreshToken) {
    return;
  }

  const oauth2Client = youtubeAdapter.createOAuthClient(oauthConfig);
  const tokens = await youtubeAdapter.refreshYouTubeTokens(
    oauth2Client,
    secrets.refreshToken,
  );
  oauth2Client.setCredentials(tokens);

  const comments = await youtubeAdapter.fetchYouTubeComments({
    oauth2Client,
    videoId,
  });

  for (const item of comments) {
    await upsertComment({
      postId: postDoc.id,
      platform: PLATFORM_TARGETS.YOUTUBE,
      externalCommentId: item.id,
      threadId: item.threadId,
      authorName: item.authorName,
      authorAvatarUrl: item.authorAvatarUrl,
      text: item.text,
      createdAt: item.createdAt,
    });
  }
}

async function syncTikTokCommentsForPost(postDoc, tiktokConfig) {
  const postData = postDoc.data() || {};
  const result = postData.platformResults?.[PLATFORM_TARGETS.TIKTOK];
  const videoId = result?.externalPostId;
  if (!videoId) {
    return;
  }

  const db = getVan4Firestore();
  const accountSnap = await db
    .collection(COLLECTIONS.ACCOUNTS)
    .where('platform', '==', PLATFORMS.TIKTOK)
    .where('connectedByUid', '==', postData.createdBy)
    .where('active', '==', true)
    .limit(1)
    .get();
  if (accountSnap.empty) {
    return;
  }

  const secrets = await loadAccountSecrets(accountSnap.docs[0].id);
  let accessToken = secrets?.accessToken;
  if (!accessToken && secrets?.refreshToken) {
    const refreshed = await tiktokAdapter.refreshTikTokToken({
      clientKey: tiktokConfig.clientKey,
      clientSecret: tiktokConfig.clientSecret,
      refreshToken: secrets.refreshToken,
    });
    accessToken = refreshed.access_token;
  }
  if (!accessToken) {
    return;
  }

  const comments = await tiktokAdapter.fetchTikTokComments({
    accessToken,
    videoId,
  });

  for (const item of comments) {
    await upsertComment({
      postId: postDoc.id,
      platform: PLATFORM_TARGETS.TIKTOK,
      externalCommentId: item.id,
      threadId: item.threadId,
      authorName: item.authorName,
      authorAvatarUrl: item.authorAvatarUrl,
      text: item.text,
      createdAt: item.createdAt,
    });
  }
}

async function syncAllSocialComments(oauthConfig, tiktokConfig) {
  const db = getVan4Firestore();
  const posts = await db
    .collection(COLLECTIONS.POSTS)
    .where('status', 'in', ['published', 'partial_failed'])
    .orderBy('createdAt', 'desc')
    .limit(30)
    .get();

  for (const postDoc of posts.docs) {
    try {
      await syncMetaCommentsForPost(postDoc);
      await syncYouTubeCommentsForPost(postDoc, oauthConfig);
      await syncTikTokCommentsForPost(postDoc, tiktokConfig);
    } catch (error) {
      logger.warn('sync comments for post failed', {
        postId: postDoc.id,
        error: String(error),
      });
    }
  }
}

async function replyToComment({
  commentId,
  message,
  adminUid,
  adminEmail,
  oauthConfig,
  tiktokConfig,
}) {
  const db = getVan4Firestore();
  const ref = db.collection(COLLECTIONS.COMMENTS).doc(commentId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new Error('Comment not found');
  }
  const data = snap.data() || {};
  const postSnap = await db.collection(COLLECTIONS.POSTS).doc(data.postId).get();
  const postData = postSnap.data() || {};

  if (postData.createdBy !== adminUid) {
    throw new Error('Permission denied');
  }

  const platform = data.platform;
  if (platform === PLATFORM_TARGETS.META_FB || platform === PLATFORM_TARGETS.META_IG) {
    const accountSnap = await db
      .collection(COLLECTIONS.ACCOUNTS)
      .where('platform', '==', PLATFORMS.META)
      .where('connectedByUid', '==', adminUid)
      .limit(1)
      .get();
    const secrets = await loadAccountSecrets(accountSnap.docs[0]?.id);
    await metaAdapter.replyMetaComment({
      commentId: data.externalCommentId,
      accessToken: secrets.pageAccessToken,
      message,
    });
  } else if (platform === PLATFORM_TARGETS.YOUTUBE) {
    const accountSnap = await db
      .collection(COLLECTIONS.ACCOUNTS)
      .where('platform', '==', PLATFORMS.YOUTUBE)
      .where('connectedByUid', '==', adminUid)
      .limit(1)
      .get();
    const secrets = await loadAccountSecrets(accountSnap.docs[0]?.id);
    const oauth2Client = youtubeAdapter.createOAuthClient(oauthConfig);
    const tokens = await youtubeAdapter.refreshYouTubeTokens(
      oauth2Client,
      secrets.refreshToken,
    );
    oauth2Client.setCredentials(tokens);
    await youtubeAdapter.replyYouTubeComment({
      oauth2Client,
      parentId: data.externalCommentId,
      message,
    });
  } else if (platform === PLATFORM_TARGETS.TIKTOK) {
    const accountSnap = await db
      .collection(COLLECTIONS.ACCOUNTS)
      .where('platform', '==', PLATFORMS.TIKTOK)
      .where('connectedByUid', '==', adminUid)
      .limit(1)
      .get();
    const secrets = await loadAccountSecrets(accountSnap.docs[0]?.id);
    const videoId =
      postData.platformResults?.[PLATFORM_TARGETS.TIKTOK]?.externalPostId;
    await tiktokAdapter.replyTikTokComment({
      accessToken: secrets.accessToken,
      videoId,
      commentId: data.externalCommentId,
      message,
    });
  } else {
    throw new Error(`Unsupported platform: ${platform}`);
  }

  await ref.set(
    {
      replyStatus: COMMENT_REPLY_STATUS.REPLIED,
      ourReply: message,
      repliedAt: admin.firestore.FieldValue.serverTimestamp(),
      repliedBy: adminEmail,
    },
    { merge: true },
  );
}

async function ingestMetaWebhookEntry(entry) {
  const changes = entry.changes || [];
  for (const change of changes) {
    const value = change.value || {};
    const commentId = value.comment_id || value.id;
    const postId = value.post_id || value.media?.id || value.video_id;
    if (!commentId || !postId) {
      continue;
    }

    const db = getVan4Firestore();
    const posts = await db
      .collection(COLLECTIONS.POSTS)
      .where(`platformResults.${PLATFORM_TARGETS.META_FB}.externalPostId`, '==', postId)
      .limit(1)
      .get();

    let resolvedPostId = posts.docs[0]?.id;
    if (!resolvedPostId) {
      const igPosts = await db
        .collection(COLLECTIONS.POSTS)
        .where(`platformResults.${PLATFORM_TARGETS.META_IG}.externalPostId`, '==', postId)
        .limit(1)
        .get();
      resolvedPostId = igPosts.docs[0]?.id;
    }
    if (!resolvedPostId) {
      continue;
    }

    await upsertComment({
      postId: resolvedPostId,
      platform: PLATFORM_TARGETS.META_FB,
      externalCommentId: commentId,
      threadId: commentId,
      authorName: value.from?.name || value.sender_name || '',
      authorAvatarUrl: '',
      text: value.message || value.text || '',
      createdAt: value.created_time || new Date().toISOString(),
    });
  }
}

module.exports = {
  syncAllSocialComments,
  replyToComment,
  ingestMetaWebhookEntry,
  upsertComment,
};
