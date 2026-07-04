const { META_GRAPH_VERSION } = require('./constants');

async function graphGet(path, accessToken, params = {}) {
  const url = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/${path}`);
  url.searchParams.set('access_token', accessToken);
  for (const [key, value] of Object.entries(params)) {
    if (value != null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error?.message || `Meta API error (${response.status})`);
  }
  return data;
}

async function graphPost(path, accessToken, body = {}) {
  const url = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/${path}`);
  url.searchParams.set('access_token', accessToken);
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error?.message || `Meta API error (${response.status})`);
  }
  return data;
}

async function exchangeMetaCode({ code, appId, appSecret, redirectUri }) {
  const url = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/oauth/access_token`);
  url.searchParams.set('client_id', appId);
  url.searchParams.set('client_secret', appSecret);
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('code', code);
  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error?.message || 'Meta token exchange failed');
  }
  return data;
}

async function exchangeMetaLongLivedToken({ shortToken, appId, appSecret }) {
  const url = new URL(`https://graph.facebook.com/${META_GRAPH_VERSION}/oauth/access_token`);
  url.searchParams.set('grant_type', 'fb_exchange_token');
  url.searchParams.set('client_id', appId);
  url.searchParams.set('client_secret', appSecret);
  url.searchParams.set('fb_exchange_token', shortToken);
  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok || data.error) {
    throw new Error(data.error?.message || 'Meta long-lived token failed');
  }
  return data;
}

async function listMetaPages(userAccessToken) {
  const data = await graphGet('me/accounts', userAccessToken, {
    fields: 'id,name,access_token,instagram_business_account{id,username}',
  });
  return Array.isArray(data.data) ? data.data : [];
}

async function publishFacebookVideo({ pageId, pageAccessToken, videoUrl, caption }) {
  return graphPost(`${pageId}/videos`, pageAccessToken, {
    file_url: videoUrl,
    description: caption || '',
    published: true,
  });
}

async function publishInstagramReel({
  igUserId,
  pageAccessToken,
  videoUrl,
  caption,
}) {
  const container = await graphPost(`${igUserId}/media`, pageAccessToken, {
    media_type: 'REELS',
    video_url: videoUrl,
    caption: caption || '',
  });
  const containerId = container.id;
  if (!containerId) {
    throw new Error('Instagram container creation failed');
  }

  for (let attempt = 0; attempt < 20; attempt += 1) {
    const status = await graphGet(containerId, pageAccessToken, {
      fields: 'status_code,status',
    });
    const code = String(status.status_code || status.status || '').toUpperCase();
    if (code === 'FINISHED' || code === 'PUBLISHED') {
      break;
    }
    if (code === 'ERROR') {
      throw new Error('Instagram media processing failed');
    }
    await new Promise((resolve) => setTimeout(resolve, 3000));
  }

  return graphPost(`${igUserId}/media_publish`, pageAccessToken, {
    creation_id: containerId,
  });
}

async function fetchMetaComments({ objectId, accessToken }) {
  const data = await graphGet(`${objectId}/comments`, accessToken, {
    fields: 'id,message,from{name,picture},created_time,comment_count',
    limit: '50',
  });
  return Array.isArray(data.data) ? data.data : [];
}

async function replyMetaComment({ commentId, accessToken, message }) {
  return graphPost(`${commentId}/comments`, accessToken, {
    message,
  });
}

async function hideMetaComment({ commentId, accessToken, hide }) {
  return graphPost(commentId, accessToken, {
    is_hidden: hide,
  });
}

module.exports = {
  exchangeMetaCode,
  exchangeMetaLongLivedToken,
  listMetaPages,
  publishFacebookVideo,
  publishInstagramReel,
  fetchMetaComments,
  replyMetaComment,
  hideMetaComment,
  graphGet,
};
