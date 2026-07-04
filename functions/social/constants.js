const DEFAULT_REGION = 'asia-southeast1';
const VAN4_DATABASE_ID = 'van4';
const VAN4_STORAGE_BUCKET = 'van-merchant-van4-storage-802503541368';

const COLLECTIONS = {
  ACCOUNTS: 'social_accounts',
  ACCOUNT_SECRETS: 'social_account_secrets',
  POSTS: 'social_posts',
  COMMENTS: 'social_comments',
  OAUTH_STATES: 'social_oauth_states',
};

const PLATFORMS = {
  META: 'meta',
  YOUTUBE: 'youtube',
  TIKTOK: 'tiktok',
};

const PLATFORM_TARGETS = {
  META_FB: 'meta_fb',
  META_IG: 'meta_ig',
  YOUTUBE: 'youtube',
  TIKTOK: 'tiktok',
};

const POST_STATUS = {
  DRAFT: 'draft',
  PUBLISHING: 'publishing',
  PUBLISHED: 'published',
  PARTIAL_FAILED: 'partial_failed',
  FAILED: 'failed',
};

const PLATFORM_RESULT_STATUS = {
  PENDING: 'pending',
  PUBLISHING: 'publishing',
  PUBLISHED: 'published',
  FAILED: 'failed',
  SKIPPED: 'skipped',
};

const COMMENT_REPLY_STATUS = {
  OPEN: 'open',
  REPLIED: 'replied',
  HIDDEN: 'hidden',
  DELETED: 'deleted',
};

const META_GRAPH_VERSION = 'v21.0';
const OAUTH_STATE_TTL_MS = 15 * 60 * 1000;

module.exports = {
  DEFAULT_REGION,
  VAN4_DATABASE_ID,
  VAN4_STORAGE_BUCKET,
  COLLECTIONS,
  PLATFORMS,
  PLATFORM_TARGETS,
  POST_STATUS,
  PLATFORM_RESULT_STATUS,
  COMMENT_REPLY_STATUS,
  META_GRAPH_VERSION,
  OAUTH_STATE_TTL_MS,
};
