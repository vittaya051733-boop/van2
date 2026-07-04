const { google } = require('googleapis');

function createOAuthClient({ clientId, clientSecret, redirectUri }) {
  return new google.auth.OAuth2(clientId, clientSecret, redirectUri);
}

function getYouTubeAuthUrl(oauth2Client, state) {
  return oauth2Client.generateAuthUrl({
    access_type: 'offline',
    prompt: 'consent',
    scope: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.force-ssl',
      'https://www.googleapis.com/auth/youtube.readonly',
    ],
    state,
  });
}

async function exchangeYouTubeCode(oauth2Client, code) {
  const { tokens } = await oauth2Client.getToken(code);
  oauth2Client.setCredentials(tokens);
  return tokens;
}

async function refreshYouTubeTokens(oauth2Client, refreshToken) {
  oauth2Client.setCredentials({ refresh_token: refreshToken });
  const { credentials } = await oauth2Client.refreshAccessToken();
  return credentials;
}

async function getYouTubeChannelInfo(oauth2Client) {
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
  const response = await youtube.channels.list({
    part: ['snippet', 'contentDetails'],
    mine: true,
  });
  const channel = response.data.items?.[0];
  if (!channel) {
    throw new Error('YouTube channel not found for this account');
  }
  return {
    channelId: channel.id,
    title: channel.snippet?.title || 'YouTube',
    thumbnailUrl: channel.snippet?.thumbnails?.default?.url || '',
  };
}

async function uploadYouTubeVideo({
  oauth2Client,
  videoBuffer,
  title,
  description,
  tags = [],
}) {
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
  const response = await youtube.videos.insert({
    part: ['snippet', 'status'],
    requestBody: {
      snippet: {
        title: title || 'VANTALAD',
        description: description || '',
        tags,
        categoryId: '22',
      },
      status: {
        privacyStatus: 'public',
        selfDeclaredMadeForKids: false,
      },
    },
    media: {
      body: require('stream').Readable.from(videoBuffer),
    },
  });
  const videoId = response.data.id;
  return {
    videoId,
    url: videoId ? `https://www.youtube.com/watch?v=${videoId}` : '',
  };
}

async function fetchYouTubeComments({ oauth2Client, videoId }) {
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
  const response = await youtube.commentThreads.list({
    part: ['snippet'],
    videoId,
    maxResults: 50,
    order: 'time',
  });
  return (response.data.items || []).map((item) => {
    const top = item.snippet?.topLevelComment;
    return {
      id: top?.id || item.id,
      threadId: item.id,
      text: top?.snippet?.textDisplay || '',
      authorName: top?.snippet?.authorDisplayName || '',
      authorAvatarUrl: top?.snippet?.authorProfileImageUrl || '',
      createdAt: top?.snippet?.publishedAt || '',
    };
  });
}

async function replyYouTubeComment({ oauth2Client, parentId, message }) {
  const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
  const response = await youtube.comments.insert({
    part: ['snippet'],
    requestBody: {
      snippet: {
        parentId,
        textOriginal: message,
      },
    },
  });
  return response.data;
}

module.exports = {
  createOAuthClient,
  getYouTubeAuthUrl,
  exchangeYouTubeCode,
  refreshYouTubeTokens,
  getYouTubeChannelInfo,
  uploadYouTubeVideo,
  fetchYouTubeComments,
  replyYouTubeComment,
};
