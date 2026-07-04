import '../models/chat_message.dart';
import '../models/user_profile.dart';

class _CacheEntry<T> {
  _CacheEntry(this.value, this.cachedAt);

  final T value;
  final DateTime cachedAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(cachedAt) <= ttl;
}

/// In-memory cache for chat profiles and recent messages (per app session).
class ChatWarmupCache {
  ChatWarmupCache._();

  static final ChatWarmupCache instance = ChatWarmupCache._();

  static const Duration messageTtl = Duration(minutes: 3);
  static const Duration profileTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry<List<ChatMessage>>> _messages =
      <String, _CacheEntry<List<ChatMessage>>>{};
  final Map<String, _CacheEntry<UserProfile>> _profiles =
      <String, _CacheEntry<UserProfile>>{};

  List<ChatMessage>? peekMessages(String chatId) {
    final entry = _messages[chatId];
    if (entry == null || !entry.isFresh(messageTtl)) {
      return null;
    }
    return List<ChatMessage>.from(entry.value);
  }

  void putMessages(String chatId, List<ChatMessage> messages) {
    _messages[chatId] = _CacheEntry<List<ChatMessage>>(
      List<ChatMessage>.from(messages),
      DateTime.now(),
    );
  }

  UserProfile? peekProfile(String uid) {
    final entry = _profiles[uid];
    if (entry == null || !entry.isFresh(profileTtl)) {
      return null;
    }
    return entry.value;
  }

  void cacheProfile(UserProfile profile) {
    if (profile.uid.trim().isEmpty) {
      return;
    }
    _profiles[profile.uid] = _CacheEntry<UserProfile>(profile, DateTime.now());
  }

  void invalidateChat(String chatId) {
    _messages.remove(chatId);
  }
}
