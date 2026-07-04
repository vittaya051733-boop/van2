import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'chat_service.dart';
import 'chat_warmup_cache.dart';
import 'friend_service.dart';

/// Prefetch chat data before navigation so the room opens with cached content.
class ChatWarmup {
  ChatWarmup._();

  static final Set<String> _prefetchedRooms = <String>{};

  static void prefetchRoom({
    required String myUid,
    required UserProfile peer,
    ChatService? chatService,
    FriendService? friendService,
    int messageLimit = 50,
  }) {
    if (myUid.trim().isEmpty || peer.uid.trim().isEmpty) {
      return;
    }

    final service = chatService ?? ChatService();
    final chatId = service.chatIdFor(myUid, peer.uid);
    final roomKey = '$myUid:${peer.uid}';
    if (_prefetchedRooms.contains(roomKey)) {
      return;
    }
    _prefetchedRooms.add(roomKey);

    ChatWarmupCache.instance.cacheProfile(peer);

    unawaited(service.prefetchMessages(chatId, limit: messageLimit));

    final friends = friendService ?? FriendService();
    unawaited(
      friends.getProfile(peer.uid).then((profile) {
        if (profile != null) {
          ChatWarmupCache.instance.cacheProfile(profile);
        }
      }),
    );
  }

  static void prefetchRoomsForFriends(
    List<UserProfile> peers, {
    int maxRooms = 8,
    ChatService? chatService,
    FriendService? friendService,
  }) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.trim().isEmpty || peers.isEmpty) {
      return;
    }

    for (final peer in peers.take(maxRooms)) {
      prefetchRoom(
        myUid: myUid,
        peer: peer,
        chatService: chatService,
        friendService: friendService,
      );
    }
  }
}
