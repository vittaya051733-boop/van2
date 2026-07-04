const TIKTOK_API_BASE = 'https://open.tiktokapis.com';

async function tiktokRequest(path, { method = 'GET', accessToken, body } = {}) {
  const response = await fetch(`${TIKTOK_API_BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json; charset=UTF-8',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.error?.code) {
    const message =
      data.error?.message || data.message || `TikTok API error (${response.status})`;
    throw new Error(message);
  }
  return data;
}

function getTikTokAuthUrl({ clientKey, redirectUri, state }) {
  const url = new URL('https://www.tiktok.com/v2/auth/authorize/');
  url.searchParams.set('client_key', clientKey);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', 'user.info.basic,video.publish,video.upload,comment.list,comment.list.manage');
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('state', state);
  return url.toString();
}

async function exchangeTikTokCode({ clientKey, clientSecret, code, redirectUri }) {
  const response = await fetch(`${TIKTOK_API_BASE}/v2/oauth/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_key: clientKey,
      client_secret: clientSecret,
      code,
      grant_type: 'authorization_code',
      redirect_uri: redirectUri,
    }),
  });
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error_description || data.error || 'TikTok token exchange failed');
  }
  return data;
}

async function refreshTikTokToken({ clientKey, clientSecret, refreshToken }) {
  const response = await fetch(`${TIKTOK_API_BASE}/v2/oauth/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_key: clientKey,
      client_secret: clientSecret,
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    }),
  });
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error_description || data.error || 'TikTok refresh failed');
  }
  return data;
}

async function getTikTokUserInfo(accessToken) {
  const data = await tiktokRequest('/v2/user/info/?fields=open_id,display_name,avatar_url', {
    accessToken,
  });
  return data.data?.user || {};
}

async function publishTikTokVideo({ accessToken, videoBuffer, caption }) {
  const init = await tiktokRequest('/v2/post/publish/video/init/', {
    method: 'POST',
    accessToken,
    body: {
      post_info: {
        title: caption || '',
        privacy_level: 'PUBLIC_TO_EVERYONE',
        disable_duet: false,
        disable_comment: false,
        disable_stitch: false,
      },
      source_info: {
        source: 'FILE_UPLOAD',
        video_size: videoBuffer.length,
        chunk_size: videoBuffer.length,
        total_chunk_count: 1,
      },
    },
  });

  const uploadUrl = init.data?.upload_url;
  const publishId = init.data?.publish_id;
  if (!uploadUrl || !publishId) {
    throw new Error('TikTok upload init failed');
  }

  const uploadResponse = await fetch(uploadUrl, {
    method: 'PUT',
    headers: {
      'Content-Type': 'video/mp4',
      'Content-Length': String(videoBuffer.length),
    },
    body: videoBuffer,
  });
  if (!uploadResponse.ok) {
    throw new Error(`TikTok video upload failed (${uploadResponse.status})`);
  }

  for (let attempt = 0; attempt < 30; attempt += 1) {
    const status = await tiktokRequest(
      `/v2/post/publish/status/fetch/?publish_id=${encodeURIComponent(publishId)}`,
      { accessToken },
    );
    const state = String(status.data?.status || '').toUpperCase();
    if (state === 'PUBLISH_COMPLETE') {
      return {
        publishId,
        url: status.data?.share_url || '',
      };
    }
    if (state === 'FAILED') {
      throw new Error(status.data?.fail_reason || 'TikTok publish failed');
    }
    await new Promise((resolve) => setTimeout(resolve, 3000));
  }

  throw new Error('TikTok publish timed out');
}

async function fetchTikTokComments({ accessToken, videoId }) {
  const data = await tiktokRequest('/v2/video/comment/list/', {
    method: 'POST',
    accessToken,
    body: { video_id: videoId, max_count: 50 },
  });
  return (data.data?.comments || []).map((item) => ({
    id: item.id,
    threadId: item.id,
    text: item.text || '',
    authorName: item.user?.display_name || '',
    authorAvatarUrl: item.user?.avatar_url || '',
    createdAt: item.create_time ? new Date(item.create_time * 1000).toISOString() : '',
  }));
}

async function replyTikTokComment({ accessToken, videoId, commentId, message }) {
  return tiktokRequest('/v2/video/comment/reply/', {
    method: 'POST',
    accessToken,
    body: {
      video_id: videoId,
      comment_id: commentId,
      text: message,
    },
  });
}

module.exports = {
  getTikTokAuthUrl,
  exchangeTikTokCode,
  refreshTikTokToken,
  getTikTokUserInfo,
  publishTikTokVideo,
  fetchTikTokComments,
  replyTikTokComment,
};
