import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_profile.dart';
import '../call_screen.dart';
import '../main.dart';
import '../widgets/chat_message_popup.dart';
import '../chat_room_screen.dart';


class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _callIntentChannel = MethodChannel('van.merchant/call_intents');
  static const MethodChannel _appStateChannel = MethodChannel('van.merchant/app_state');
  static const String _methodDrainPending = 'drain_pending_intents';
  static const String _methodCanUseFullScreenIntent = 'can_use_full_screen_intent';
  static const String _methodOpenFullScreenIntentSettings = 'open_full_screen_intent_settings';
  static const String _methodCanDrawOverlays = 'can_draw_overlays';
  static const String _methodOpenOverlaySettings = 'open_overlay_settings';

  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];
  static const String _customerUsersCollection = 'customer_users';

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentFcmToken;
  bool _incomingCallVisible = false;
  bool _callIntentBridgeAttached = false;
  String? _activeIncomingChannelId;
  final Set<String> _cancelledChannelIds = <String>{};
  String? _backgroundReturnChannelId;
  bool _shouldReturnAppToBackground = false;
  StreamSubscription<User?>? _authSubscription;

  /// เริ่มต้นระบบ Notification
  Future<void> initialize() async {
    if (_initialized) return;

    final systemPermissionGranted = await _ensureSystemNotificationPermission();
    if (!systemPermissionGranted) {
      debugPrint('Notification permission denied at system level');
    }

    // Request permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
    }

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _ensureAndroidNotificationChannel();
    await _ensureAndroidIncomingCallPresentationPermission();
    await _ensureAndroidOverlayPermission();

    // Get FCM token
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _saveFCMToken(token);
    }

    // Listen to token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveFCMToken);

    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null || user.isAnonymous) {
        return;
      }
      final token = _currentFcmToken ?? await _firebaseMessaging.getToken();
      if (token == null || token.isEmpty) {
        return;
      }
      await saveUserFcmToken(user.uid);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _setupCallIntentBridge();
    _initialized = true;
  }

  Future<bool> _ensureSystemNotificationPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) {
      return true;
    }
    if (status.isPermanentlyDenied) {
      return false;
    }
    final requested = await Permission.notification.request();
    return requested.isGranted || requested.isLimited;
  }

  Future<void> _ensureAndroidNotificationChannel() async {
    if (!Platform.isAndroid) {
      return;
    }
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      return;
    }
    const channel = AndroidNotificationChannel(
      'order_channel',
      'การแจ้งเตือนทั่วไป',
      description: 'ใช้สำหรับแจ้งเตือนข้อความและออเดอร์',
      importance: Importance.high,
      playSound: true,
    );
    await androidPlugin.createNotificationChannel(channel);
  }

  Future<void> _ensureAndroidIncomingCallPresentationPermission() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final bool canUseFullScreenIntent =
          await _appStateChannel.invokeMethod<bool>(_methodCanUseFullScreenIntent) ?? true;
      if (canUseFullScreenIntent) {
        return;
      }
      debugPrint('Full-screen intent permission not granted. Opening app settings.');
      await _appStateChannel.invokeMethod<void>(_methodOpenFullScreenIntentSettings);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to verify full-screen intent permission: $error');
      }
    }
  }

  Future<void> _ensureAndroidOverlayPermission() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final bool canDrawOverlays =
          await _appStateChannel.invokeMethod<bool>(_methodCanDrawOverlays) ?? true;
      if (canDrawOverlays) {
        return;
      }
      debugPrint('Overlay permission not granted. Opening overlay settings.');
      await _appStateChannel.invokeMethod<void>(_methodOpenOverlaySettings);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to verify overlay permission: $error');
      }
    }
  }

  /// บันทึก FCM Token ลง Firestore
  Future<void> _saveFCMToken(String token) async {
    try {
      if (_currentFcmToken == token) {
        debugPrint('FCM Token unchanged, skip update');
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (user.isAnonymous) {
        _currentFcmToken = token;
        debugPrint('Skip persisting FCM token for anonymous user');
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final String? registrationCollection = await _resolveRegistrationCollection(user.uid);

      if (registrationCollection != null) {
        final docRef =
            FirebaseFirestore.instance.collection(registrationCollection).doc(user.uid);
        batch.set(docRef, {'shopFCMToken': token}, SetOptions(merge: true));
      } else {
        debugPrint('⚠️ ไม่พบคอลเลกชันร้านค้าของ ${user.uid} ข้ามการอัปเดต shopFCMToken');
      }

      // อัพเดทในคอลเลกชัน customer_users (สร้างหรืออัปเดตได้เสมอ)
      final userDocRef = FirebaseFirestore.instance
          .collection(_customerUsersCollection)
          .doc(user.uid);
      batch.set(userDocRef, {'fcmToken': token}, SetOptions(merge: true));

      await batch.commit();
      _currentFcmToken = token;
      debugPrint('FCM Token saved successfully');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  Future<String?> _resolveRegistrationCollection(String userId) async {
    String? collection;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(_customerUsersCollection)
          .doc(userId)
          .get();
      collection = _collectionFromServiceType(
        (userDoc.data()?['serviceType'] as String?)?.trim(),
      );
      if (collection != null) return collection;
    } catch (_) {}

    try {
      final contractDoc =
          await FirebaseFirestore.instance.collection('contracts').doc(userId).get();
      collection = _collectionFromServiceType(
        (contractDoc.data()?['serviceType'] as String?)?.trim(),
      );
      if (collection != null) return collection;
    } catch (_) {}

    for (final candidate in _registrationCollections) {
      final snapshot =
          await FirebaseFirestore.instance.collection(candidate).doc(userId).get();
      if (snapshot.exists) {
        return candidate;
      }
    }
    return null;
  }

  String? _collectionFromServiceType(String? serviceType) {
    if (serviceType == null || serviceType.isEmpty) return null;
    switch (serviceType) {
      case 'ตลาด':
      case 'market':
      case 'market_registrations':
        return 'market_registrations';
      case 'ร้านค้า':
      case 'shop':
      case 'shop_registrations':
        return 'shop_registrations';
      case 'ร้านอาหาร':
      case 'restaurant':
      case 'restaurant_registrations':
        return 'restaurant_registrations';
      case 'ร้านขายยา':
      case 'pharmacy':
      case 'pharmacy_registrations':
        return 'pharmacy_registrations';
      case 'อื่นๆ':
      case 'other':
      case 'other_registrations':
        return 'other_registrations';
      default:
        return null;
    }
  }

  /// บันทึก FCM token ของผู้ใช้ลง Firestore
  Future<void> saveUserFcmToken(String userId) async {
    final token = await _firebaseMessaging.getToken();
    if (token == null) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        await _saveFCMToken(token);
        return;
      }

      await FirebaseFirestore.instance.collection(_customerUsersCollection).doc(userId).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error saving user FCM token directly: $e');
    }
  }

  /// จัดการ notification เมื่อแอพอยู่ foreground
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint(
      'Received foreground message: ${message.messageId} '
      'type=${message.data['type']} channel=${message.data['channelId']} '
      'appId=${message.data['appId']}',
    );

    final notification = message.notification;
    final data = message.data;

    if (data['type'] == 'call_cancel') {
      _handleCallCancelFromNative(data['channelId'] as String?);
      return;
    }

    // แจ้งเตือนข้อความแชตเข้า
    if (data['type'] == 'chat') {
      final context = MyApp.navigatorKey.currentState?.context;
      final senderName = data['senderName'] ?? 'ข้อความใหม่';
      final messageText = data['message'] ?? '';
      void handleTap() {
        _openChatFromNotificationData(data);
      }
      if (context != null) {
        ChatMessagePopup.show(
          context,
          senderName: senderName,
          message: messageText,
          onTap: handleTap,
        );
      } else {
        await _showLocalNotification(
          title: senderName,
          body: messageText,
          payload: jsonEncode({
            'type': 'chat',
            'chatId': data['chatId'],
            'senderId': data['senderId'],
            'senderName': senderName,
            'orderId': data['orderId'],
          }),
        );
      }
      return;
    }

    // แจ้งเตือนสายเข้า/วิดีโอคอลจริง
    if (data['type'] == 'call') {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final callerId = data['callerId'] ?? data['caller_id'];
      if (currentUid != null && callerId != null && currentUid == callerId) {
        debugPrint('Skip showing incoming UI for own outgoing call');
        return;
      }
      if (Platform.isAndroid) {
        debugPrint('Android native fullscreen incoming-call UI will present this call');
        return;
      }
      _navigateToIncomingCall(
        channelId: data['channelId'] ?? '',
        appId: data['appId'],
        token: data['token'],
        callerId: data['callerId'] ?? data['caller_id'] ?? '',
        callerName: data['callerName'] ?? 'ผู้โทร',
        callerPhotoUrl: data['callerPhotoUrl'],
        isVideo: _resolveIsVideoFlag(data),
      );
      return;
    }

    if (notification != null) {
      await _showLocalNotification(
        title: notification.title ?? 'แจ้งเตือน',
        body: notification.body ?? '',
        payload: data['orderId'],
      );
    }

    // เปิดหน้ารับสายอัตโนมัติถ้าเป็น notification ประเภท call
    // ลบโค้ดซ้ำซ้อนที่เปิด CallScreen อัตโนมัติ (จัดการใน showDialog ด้านบนแล้ว)
  }

  /// ดึง navigatorKey จาก MyApp (ต้องตั้ง navigatorKey ใน MaterialApp)
  // หมายเหตุ: วิธีนี้อาจไม่เสถียร ควรใช้ DI หรือ Service Locator ในแอปขนาดใหญ่
  // ลบฟังก์ชัน _getNavigatorKey ที่ไม่ได้ใช้งาน

  /// แสดง local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'order_channel',
      'การแจ้งเตือนออเดอร์',
      channelDescription: 'แจ้งเตือนเกี่ยวกับสถานะออเดอร์',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// จัดการเมื่อกด notification
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        if (decoded['type'] == 'call') {
          _navigateToIncomingCall(
            channelId: decoded['channelId'] as String? ?? '',
            appId: decoded['appId'] as String?,
            token: decoded['token'] as String?,
            callerId: decoded['callerId'] as String? ?? '',
            callerName: decoded['callerName'] as String? ?? 'ผู้โทร',
            callerPhotoUrl: decoded['callerPhotoUrl'] as String?,
            isVideo: decoded['isVideo'] == true,
          );
          return;
        }
        if (decoded['type'] == 'chat') {
          _openChatFromNotificationData(decoded);
          return;
        }
      }
      debugPrint('Notification tapped with payload: $payload');
    } catch (error) {
      debugPrint('Failed to parse notification payload: $error');
    }
  }

  /// จัดการเมื่อกด notification จาก background
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped from background: ${message.messageId}');
    final orderId = message.data['orderId'];
    if (orderId != null) {
      // TODO: Navigate to order details
    }

    // เปิดหน้ารับสายอัตโนมัติเมื่อแตะ notification ประเภท call
    if (message.data['type'] == 'call') {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final callerId = message.data['callerId'] ?? message.data['caller_id'];
      if (currentUid != null && callerId != null && currentUid == callerId) {
        debugPrint('Skip navigating to CallScreen for self-originated notification');
        return;
      }
      if (Platform.isAndroid) {
        debugPrint('Android native fullscreen incoming-call UI handles notification taps');
        return;
      }
      _navigateToIncomingCall(
        channelId: message.data['channelId'] ?? '',
        appId: message.data['appId'],
        token: message.data['token'],
        callerId: message.data['callerId'] ?? message.data['caller_id'] ?? '',
        callerName: message.data['callerName'] ?? 'ผู้โทร',
        callerPhotoUrl: message.data['callerPhotoUrl'],
        isVideo: _resolveIsVideoFlag(message.data),
      );
    }

    if (message.data['type'] == 'call_cancel') {
      _handleCallCancelFromNative(message.data['channelId'] as String?);
      return;
    }

    if (message.data['type'] == 'chat') {
      _openChatFromNotificationData(message.data);
    }
  }

  void _setupCallIntentBridge() {
    if ((!Platform.isAndroid && !Platform.isIOS) || _callIntentBridgeAttached) {
      return;
    }
    _callIntentBridgeAttached = true;
    _callIntentChannel.setMethodCallHandler((call) async {
      if (call.method != 'incoming_call_intent') {
        return;
      }
      _handleIncomingCallPayload(call.arguments);
    });
    _drainPendingPlatformIntents();
  }

  Map<String, dynamic>? _normalizePlatformPayload(dynamic arguments) {
    if (arguments is! Map) {
      return null;
    }
    final normalized = <String, dynamic>{};
    arguments.forEach((key, value) {
      normalized[key.toString()] = value;
    });
    return normalized;
  }

  Future<void> _drainPendingPlatformIntents() async {
    try {
      final List<dynamic>? pending =
          await _callIntentChannel.invokeListMethod<dynamic>(_methodDrainPending);
      if (pending == null) return;
      for (final dynamic rawPayload in pending) {
        _handleIncomingCallPayload(rawPayload);
      }
    } catch (error) {
      debugPrint('Unable to drain call intents: $error');
    }
  }

  void _handleIncomingCallPayload(dynamic payloadData) {
    final payload = _normalizePlatformPayload(payloadData);
    if (payload == null) {
      return;
    }
    if (payload['cancelOnly'] == true) {
      _handleCallCancelFromNative(payload['channelId'] as String?);
      return;
    }
    final bool minimizeOnEnd = payload['appWasForeground'] == false;
    _navigateToIncomingCall(
      channelId: payload['channelId'] as String? ?? '',
      appId: payload['appId'] as String?,
      token: payload['token'] as String?,
      callerId: payload['callerId'] as String? ?? '',
      callerName: payload['callerName'] as String? ?? 'ผู้โทร',
      callerPhotoUrl: payload['callerPhotoUrl'] as String?,
      isVideo: payload['isVideo'] == true,
      minimizeOnEnd: minimizeOnEnd,
    );
  }

  void _handleCallCancelFromNative(String? channelId) {
    if (channelId != null) {
      _cancelledChannelIds.add(channelId);
    }
    _dismissIncomingCallUI(channelId: channelId);
  }

  void _dismissIncomingCallUI({String? channelId}) {
    if (!_incomingCallVisible) {
      return;
    }
    if (_activeIncomingChannelId != null && channelId != null && _activeIncomingChannelId != channelId) {
      return;
    }
    final navigatorState = MyApp.navigatorKey.currentState;
    if (navigatorState != null) {
      navigatorState.maybePop();
    }
    _incomingCallVisible = false;
    _activeIncomingChannelId = null;
    _maybeReturnAppToBackground(channelId: channelId);
  }

  void _navigateToIncomingCall({
    required String channelId,
    required String? appId,
    required String? token,
    required String callerId,
    required String callerName,
    String? callerPhotoUrl,
    required bool isVideo,
    int retryCount = 30,
    bool minimizeOnEnd = false,
  }) {
    if (channelId.isEmpty || token == null || token.isEmpty) {
      debugPrint('Incoming call payload missing channel/token, skip UI presentation');
      return;
    }
    if (_cancelledChannelIds.contains(channelId)) {
      debugPrint('Call $channelId already cancelled, skip presenting UI');
      return;
    }
    if (_incomingCallVisible) {
      debugPrint('Incoming call UI already visible, skip duplicate navigation');
      return;
    }
    final navigatorState = MyApp.navigatorKey.currentState;
    if (navigatorState == null) {
      if (retryCount <= 0) {
        debugPrint('Navigator not ready, cannot open CallScreen');
        return;
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigateToIncomingCall(
          channelId: channelId,
          appId: appId,
          token: token,
          callerId: callerId,
          callerName: callerName,
          callerPhotoUrl: callerPhotoUrl,
          isVideo: isVideo,
          retryCount: retryCount - 1,
          minimizeOnEnd: minimizeOnEnd,
        );
      });
      return;
    }

    _incomingCallVisible = true;
    _activeIncomingChannelId = channelId;
    if (minimizeOnEnd) {
      _backgroundReturnChannelId = channelId;
      _shouldReturnAppToBackground = true;
    }
    navigatorState!.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          channelName: channelId,
          targetProfile: UserProfile.fromMap(
            callerId,
            {
              'displayName': callerName,
              'photoUrl': callerPhotoUrl,
            },
          ),
          isVideo: isVideo,
          isIncoming: true,
          appIdOverride: appId,
          tokenOverride: token,
        ),
      ),
    ).whenComplete(() {
      _incomingCallVisible = false;
      if (_activeIncomingChannelId == channelId) {
        _activeIncomingChannelId = null;
      }
      _cancelledChannelIds.remove(channelId);
      _maybeReturnAppToBackground(channelId: channelId);
    });
  }

  bool _resolveIsVideoFlag(Map<String, dynamic> data) {
    final raw = data['callType'] ?? data['isVideo'];
    if (raw is bool) return raw;
    if (raw is String) {
      final lower = raw.toLowerCase();
      return lower == 'video' || lower == 'true';
    }
    return false;
  }

  /// ส่ง notification แบบ manual (สำหรับทดสอบ)
  Future<void> sendTestNotification() async {
    await _showLocalNotification(
      title: 'ทดสอบการแจ้งเตือน',
      body: 'นี่คือการแจ้งเตือนทดสอบจากระบบ',
    );
  }

  Future<void> _maybeReturnAppToBackground({String? channelId}) async {
    if (!_shouldReturnAppToBackground) {
      return;
    }
    if (_backgroundReturnChannelId != null && channelId != null && _backgroundReturnChannelId != channelId) {
      return;
    }
    _shouldReturnAppToBackground = false;
    _backgroundReturnChannelId = null;
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _appStateChannel.invokeMethod('move_task_to_back');
    } catch (error) {
      debugPrint('Unable to return app to background: $error');
    }
  }

  Future<void> _openChatFromNotificationData(
    Map<String, dynamic> data, {
    int retryCount = 6,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint('Skip navigating to chat: no authenticated user');
      return;
    }
    final navigatorState = MyApp.navigatorKey.currentState;
    if (navigatorState == null) {
      if (retryCount <= 0) {
        debugPrint('Navigator not ready, cannot navigate to chat');
        return;
      }
      Future.delayed(const Duration(milliseconds: 250), () {
        _openChatFromNotificationData(data, retryCount: retryCount - 1);
      });
      return;
    }

    final senderIdRaw = data['senderId'] ?? data['sender_id'];
    final String? senderId = senderIdRaw?.toString();
    final senderName = (data['senderName'] ?? data['title'] ?? 'คู่สนทนา').toString();
    final orderId = data['orderId']?.toString().trim();

    UserProfile? profile;
    if (senderId != null && senderId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(_customerUsersCollection)
            .doc(senderId)
            .get();
        if (doc.exists) {
          profile = UserProfile.fromSnapshot(doc);
        }
      } catch (error) {
        debugPrint('Failed to load chat profile for $senderId: $error');
      }
    }

    profile ??= UserProfile(
      uid: senderId ?? 'unknown',
      displayName: senderName,
    );

    navigatorState.push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          friendProfile: profile!,
          orderId: orderId != null && orderId.isNotEmpty ? orderId : null,
        ),
      ),
    );
  }

  // ฟังก์ชันสำหรับโทรจริง (voice/video call)
  // เรียก Cloud Function callUser
  Future<void> callUser({
    required String callerId,
    required String callerName,
    required String callerPhotoUrl,
    required String calleeId,
    required String calleeFCMToken,
    required String callType, // 'voice' หรือ 'video'
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('callUser');
    final result = await callable.call({
      'callerId': callerId,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl,
      'calleeId': calleeId,
      'calleeFCMToken': calleeFCMToken,
      'callType': callType,
    });
    print('Call result: ${result.data}');
  }

  Future<void> cancelCallInvite({
    required String channelId,
    required String calleeId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('cancelCallInvite');
      await callable.call({
        'channelId': channelId,
        'calleeId': calleeId,
        'callerId': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (error) {
      debugPrint('Failed to cancel call invite: $error');
    }
  }

  /// เริ่มการโทรโดยเรียก Cloud Function เพื่อสร้าง token และส่ง notification
  Future<Map<String, dynamic>> initiateCall({
    required UserProfile caller,
    required UserProfile callee,
    required bool isVideo,
  }) async {
    const List<String> preferredRegions = <String>['asia-southeast1', 'us-central1'];
    FirebaseFunctionsException? lastError;

    for (final region in preferredRegions) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: region).httpsCallable('initiateCall');
        final result = await callable.call(<String, dynamic>{
          'calleeId': callee.uid,
          'callerId': caller.uid,
          'callerName': caller.displayName,
          'callerPhotoUrl': caller.photoUrl,
          'isVideo': isVideo,
          'callType': isVideo ? 'video' : 'voice',
          'callerData': caller.toFirestore()..['uid'] = caller.uid,
        });
        return Map<String, dynamic>.from(result.data);
      } on FirebaseFunctionsException catch (e) {
        lastError = e;
        debugPrint('Error initiating call via $region: ${e.code} - ${e.message}');
        if (e.code != 'not-found') {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    throw FirebaseFunctionsException(code: 'unknown', message: 'Unknown error initiating call');
  }
}

/// Background message handler (ต้องเป็น top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
  // ไม่ต้องทำอะไร เพราะ Cloud Functions จะจัดการให้
}
