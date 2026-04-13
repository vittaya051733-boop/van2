import 'dart:async';

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models/user_profile.dart';
import 'services/notification_service.dart';
import 'widgets/cached_app_image.dart';

class CallScreen extends StatefulWidget {
  final String channelName;
  final bool isVideo;
  final UserProfile targetProfile;
  final bool isIncoming;
  final String? appIdOverride;
  final String? tokenOverride;
  final String? channelOverride;
  const CallScreen({
    super.key,
    required this.channelName,
    required this.isVideo,
    required this.targetProfile,
    this.isIncoming = false,
    this.appIdOverride,
    this.tokenOverride,
    this.channelOverride,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RtcEngine? _engine;
  bool _joined = false;
  int? _remoteUid;
  bool _speakerOn = false;
  bool _micMuted = false;
  bool _videoMuted = true;
  late final String _activeToken;
  late final String _activeChannelId;
  bool _incomingAccepted = false;
  bool _acceptingIncoming = false;
  bool _remoteConnected = false;
  bool _remoteAccepted = false;
  DateTime? _callStart;
  bool _resultSent = false;
  Timer? _durationTimer;
  bool _cancelSignalSent = false;

  AudioPlayer? _ringbackPlayer;
  String? _fatalError;

  DocumentReference<Map<String, dynamic>>? _sessionDocRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSubscription;
  bool _callSessionMarkedEnded = false;

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // Agora App ID
  static const String appId = '37050f5308fd450ba070b53c01596c06';

  String get _effectiveAppId {
    final override = widget.appIdOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return appId;
  }

  @override
  void initState() {
    super.initState();
    // เปิดกล้องเฉพาะเมื่อผู้ใช้กดอนุญาตเอง
    _videoMuted = widget.isVideo;
    _activeToken = widget.tokenOverride?.trim() ?? '';
    final overrideChannel = widget.channelOverride?.trim();
    _activeChannelId = (overrideChannel != null && overrideChannel.isNotEmpty)
        ? overrideChannel
        : widget.channelName.trim();

    if (_activeToken.isEmpty || _activeChannelId.isEmpty) {
      _fatalError = 'ไม่พบข้อมูลการโทรจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
      return;
    }

    _setupCallSessionTracking();

    if (!widget.isIncoming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startOutgoingCall();
      });
    } else {
      // ฝั่งผู้รับเล่นเสียงเรียกเข้าจากไฟล์ K-pop
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRingtone('k-pop-ringtone-no-copyright-357142.mp3');
      });
    }
  }

  Future<void> _startOutgoingCall() async {
    if (!await _ensurePermissions()) return;
    await _initAgora();
    if (!mounted || _fatalError != null) return;
    _startRingtone('topping-pop-sound-245150.mp3');
  }

  Future<bool> _ensurePermissions() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showPermissionError('ไมโครโฟน');
      return false;
    }
    if (widget.isVideo) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showPermissionError('กล้อง');
        return false;
      }
    }
    return true;
  }

  void _showPermissionError(String permissionName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ต้องอนุญาต$permissionNameก่อนจึงจะใช้การโทรได้')),
    );
  }

  Future<void> _initAgora() async {
    if (_engine != null) return;
    RtcEngine? engine;
    try {
      engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(
        appId: _effectiveAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
      engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print('Agora: onJoinChannelSuccess channel=${connection.channelId} uid=${connection.localUid}');
          if (!mounted) return;
          setState(() {
            _joined = true;
          });
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          if (connection.channelId != _activeChannelId) return;
          print('Agora: onUserJoined remoteUid=$remoteUid in channel ${connection.channelId}');
          if (!mounted) return;
          setState(() {
            _remoteUid = remoteUid;
            _remoteConnected = true;
            _callStart = DateTime.now();
          });
          unawaited(_updateCallSessionStatus('connected', extra: {
            'connectedAt': FieldValue.serverTimestamp(),
            'remoteAgoraUid': remoteUid,
          }));
          _startDurationTicker();
          _stopRingback(); // หยุดเสียงรอสายเมื่ออีกฝ่ายรับสาย
        },
        onUserOffline: (connection, remoteUid, reason) {
          print('Agora: onUserOffline remoteUid=$remoteUid reason=$reason');
          if (!mounted) return;
          setState(() {
            _remoteUid = null;
            _remoteConnected = false;
          });
          _stopDurationTicker();
          _endCall(remoteEnded: true);
        },
        onError: (err, msg) {
          print('Agora: onError code=$err msg=$msg');
          if (err == ErrorCodeType.errInvalidToken) {
            if (!mounted) return;
            setState(() {
              _fatalError = 'Agora token ไม่ถูกต้องหรือไม่ตรงกับ App ID';
            });
            unawaited(_endCall(declined: true));
          }
        },
      ),
    );
      if (widget.isVideo) {
        await engine.enableVideo();
        if (_videoMuted) {
          await engine.enableLocalVideo(false);
          await engine.muteLocalVideoStream(true);
        }
      } else {
        await engine.enableAudio();
      }
      await engine.joinChannel(
        token: _activeToken,
        channelId: _activeChannelId,
        uid: 0,
        options: ChannelMediaOptions(
          publishCameraTrack: widget.isVideo && !_videoMuted,
          publishMicrophoneTrack: true,
        ),
      );
      if (!mounted) {
        await engine.leaveChannel();
        await engine.release();
        return;
      }
      setState(() {
        _engine = engine;
      });
    } catch (error) {
      print('Agora init error: $error');
      if (!mounted) {
        if (engine != null) {
          await engine.release();
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _fatalError = 'ไม่สามารถเชื่อมต่อบริการโทรได้ ($error)';
      });
    }
  }

  void _startRingtone(String assetName) {
    _ringbackPlayer?.stop();
    _ringbackPlayer?.dispose();
    _ringbackPlayer = AudioPlayer();
    _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
    _ringbackPlayer!.play(AssetSource(assetName));
  }

  void _stopRingback() {
    _ringbackPlayer?.stop();
    _ringbackPlayer?.dispose();
    _ringbackPlayer = null;
  }

  void _setupCallSessionTracking() {
    if (_activeChannelId.isEmpty) return;
    _sessionDocRef = FirebaseFirestore.instance.collection('call_sessions').doc(_activeChannelId);
    _sessionSubscription = _sessionDocRef!
        .snapshots()
        .listen(_handleSessionSnapshot, onError: (error, stack) {
      debugPrint('call session listen error: $error');
    });
    if (!widget.isIncoming) {
      _createCallSessionDocument();
    }
  }

  void _handleSessionSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;
    final status = data['status'] as String?;
    if (status == 'accepted') {
      if (!mounted) return;
      setState(() {
        _remoteAccepted = true;
      });
      if (!widget.isIncoming) {
        _stopRingback();
      }
      return;
    }
    if (status == 'connected') {
      if (!mounted) return;
      setState(() {
        _remoteAccepted = true;
      });
      if (!widget.isIncoming) {
        _stopRingback();
      }
      return;
    }
    if (status == 'ended') {
      final endedBy = data['endedBy'] as String?;
      if (endedBy != null && endedBy == _currentUserId) return;
      _endCall(remoteEnded: true);
    }
  }

  Future<void> _createCallSessionDocument() async {
    final docRef = _sessionDocRef;
    if (docRef == null) return;
    final payload = <String, dynamic>{
      'channelId': _activeChannelId,
      'status': 'ringing',
      'isVideo': widget.isVideo,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'callerId': _currentUserId,
      if (widget.targetProfile.uid.isNotEmpty) 'calleeId': widget.targetProfile.uid,
    };
    await docRef.set(payload, SetOptions(merge: true));
  }

  Future<void> _updateCallSessionStatus(
    String status, {
    Map<String, dynamic>? extra,
    bool allowDuplicateEnd = false,
  }) async {
    final docRef = _sessionDocRef;
    if (docRef == null) return;
    if (status == 'ended' && _callSessionMarkedEnded && !allowDuplicateEnd) {
      return;
    }
    final data = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'lastUpdatedBy': _currentUserId,
      ...?extra,
    };
    if (status == 'ended' && !_callSessionMarkedEnded) {
      _callSessionMarkedEnded = true;
      data['endedAt'] = FieldValue.serverTimestamp();
      if (_currentUserId != null) {
        data['endedBy'] = _currentUserId;
      }
    }
    await docRef.set(data, SetOptions(merge: true));
  }

  String _resolveSessionEndReason(bool declined, bool answered) {
    if (declined) return 'declined';
    if (answered) return 'completed';
    return widget.isIncoming ? 'missed' : 'cancelled';
  }

  void _toggleSpeaker() {
    final engine = _engine;
    if (engine == null) return;
    engine.setEnableSpeakerphone(!_speakerOn);
    setState(() => _speakerOn = !_speakerOn);
  }

  void _toggleMute() {
    final engine = _engine;
    if (engine == null) return;
    engine.muteLocalAudioStream(!_micMuted);
    setState(() => _micMuted = !_micMuted);
  }

  @override
  void dispose() {
    _stopRingback();
    _stopDurationTicker();
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _engine?.leaveChannel();
    _engine?.release();
    _endCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1F252B),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    _fatalError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _endCall(declined: true),
                    child: const Text('ปิด'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (widget.isIncoming && !_incomingAccepted) {
      return Scaffold(
        backgroundColor: widget.isVideo ? Colors.black : const Color(0xFFF5F5F7),
        body: _buildIncomingContent(),
      );
    }
    return WillPopScope(
      onWillPop: () async {
        _endCall();
        return false;
      },
      child: Scaffold(
        backgroundColor: widget.isVideo ? Colors.black : const Color(0xFFF5F5F7),
        body: widget.isVideo ? _buildVideoContent() : _buildVoiceContent(),
      ),
    );
  }

  Future<void> _acceptIncomingCall() async {
    if (_acceptingIncoming) return;
    setState(() {
      _acceptingIncoming = true;
      _incomingAccepted = true;
    });
    _stopRingback();
    unawaited(_updateCallSessionStatus('accepted', extra: {
      'acceptedAt': FieldValue.serverTimestamp(),
      if (_currentUserId != null) 'acceptedBy': _currentUserId,
    }));
    if (!await _ensurePermissions()) {
      if (!mounted) return;
      await _endCall(declined: true);
      return;
    }
    await _initAgora();
    if (!mounted) return;
    setState(() {
      _acceptingIncoming = false;
    });
  }

  Widget _buildIncomingContent() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF374049), Color(0xFF1F252B)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  Text('มีสายเข้า', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 12),
                  Text(
                    widget.targetProfile.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
              child: ClipOval(
                child: widget.targetProfile.photoUrl != null
                  ? CachedAppImage(imageUrl: widget.targetProfile.photoUrl!, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          widget.targetProfile.displayName.characters.first.toUpperCase(),
                          style: const TextStyle(fontSize: 64, color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: Icons.call,
                    label: 'รับสาย',
                    color: const Color(0xFF00B900),
                    onTap: _acceptIncomingCall,
                  ),
                  const SizedBox(width: 32),
                  _CallActionButton(
                    icon: Icons.call_end,
                    label: 'ไม่รับ',
                    color: Colors.redAccent,
                    onTap: () => _endCall(declined: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    final durationText = _activeDurationText;
    final statusText = _statusText(isVideo: true);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF23272A), Color(0xFF181A1B)],
        ),
      ),
      child: Stack(
        children: [
          // Remote video (full screen)
          Positioned.fill(child: remoteVideoView),
          // Local video (small corner)
          Positioned(
            top: 40,
            right: 20,
            child: SafeArea(
              child: SizedBox(
                width: 100,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: localVideoView,
                ),
              ),
            ),
          ),
          // Controls
          _buildCallControls(statusText, durationText),
        ],
      ),
    );
  }

  Widget _buildVoiceContent() {
    final statusText = _statusText(isVideo: false);
    final durationText = _activeDurationText;

    return _buildCallUI(
      statusText: statusText,
      durationText: durationText,
      centerContent: _buildCallingStatus(),
      bottomControls: _buildVoiceCallButtons(),
    );
  }

  Widget _buildCallUI({
    required String statusText,
    String? durationText,
    required Widget centerContent,
    required Widget bottomControls,
  }) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF374049), Color(0xFF1F252B)],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  Text(statusText, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (durationText != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(48),
                      ),
                      child: Text(
                        durationText,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    widget.targetProfile.displayName,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            centerContent,
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: bottomControls,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallingStatus() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
          child: ClipOval(
            child: widget.targetProfile.photoUrl != null
              ? CachedAppImage(imageUrl: widget.targetProfile.photoUrl!, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      widget.targetProfile.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 64, color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        if (_remoteUid == null) const CircularProgressIndicator(color: Colors.white),
      ],
    );
  }

  Widget _buildCallControls(String statusText, String? durationText) {
    return _buildCallUI(
      statusText: statusText,
      durationText: durationText,
      centerContent: const SizedBox.shrink(), // Center is covered by video
      bottomControls: _buildVideoCallButtons(),
    );
  }
  
  Widget get localVideoView {
    final engine = _engine;
    if (_joined && !_videoMuted && engine != null) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    }
    return Container(color: Colors.grey[800], child: const Center(child: Text('คุณปิดกล้อง', style: TextStyle(color: Colors.white))));
  }

  Widget get remoteVideoView {
    final engine = _engine;
    if (_remoteUid != null && engine != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: _remoteUid!),
          connection: RtcConnection(channelId: _activeChannelId),
        ),
      );
    }
    return Container(color: Colors.grey[900], child: Center(child: Text('กำลังรอคู่สนทนา...', style: TextStyle(color: Colors.white))));
  }

  void _toggleVideo() {
    final engine = _engine;
    if (engine == null) return;
    final nextMuted = !_videoMuted;
    engine.enableLocalVideo(!nextMuted);
    engine.muteLocalVideoStream(nextMuted);
    engine.updateChannelMediaOptions(
      ChannelMediaOptions(publishCameraTrack: !nextMuted),
    );
    setState(() => _videoMuted = nextMuted);
  }

  Widget _buildVideoCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallActionButton(
          icon: _videoMuted ? Icons.videocam_off : Icons.videocam,
          label: _videoMuted ? 'เปิดกล้อง' : 'ปิดกล้อง',
          color: Colors.white24,
          onTap: _toggleVideo,
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'วางสาย',
          color: Colors.redAccent,
          onTap: _endCall,
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: _micMuted ? Icons.mic_off : Icons.mic,
          label: _micMuted ? 'เปิดไมค์' : 'ปิดไมค์',
          color: Colors.white24,
          onTap: _toggleMute,
        ),
      ],
    );
  }

  Widget _buildVoiceCallButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallActionButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
          label: 'ลำโพง',
          color: Colors.white24,
          onTap: _toggleSpeaker,
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'วางสาย',
          color: Colors.redAccent,
          onTap: _endCall,
        ),
        const SizedBox(width: 24),
        _CallActionButton(
          icon: _micMuted ? Icons.mic_off : Icons.mic,
          label: _micMuted ? 'เปิดไมค์' : 'ปิดไมค์',
          color: Colors.white24,
          onTap: _toggleMute,
        ),
      ],
    );
  }

  Duration? get _callDuration {
    final start = _callStart;
    if (start == null) return null;
    return DateTime.now().difference(start);
  }

  String? get _activeDurationText {
    if (!_remoteConnected) return null;
    final duration = _callDuration;
    if (duration == null) return null;
    return _formatDuration(duration);
  }

  String _statusText({required bool isVideo}) {
    if (!_joined) return 'กำลังเชื่อมต่อ...';
    if (!_remoteConnected) {
      if (_remoteAccepted) {
        return 'อีกฝ่ายรับสายแล้ว กำลังเชื่อมต่อ...';
      }
      return isVideo ? 'กำลังโทรหา (วิดีโอ)' : 'กำลังโทรหา';
    }
    return 'กำลังสนทนากับ';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      final hoursStr = hours.toString().padLeft(2, '0');
      return '$hoursStr:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _startDurationTicker() {
    if (_durationTimer != null || _callStart == null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _stopDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Future<void> _endCall({bool declined = false, bool remoteEnded = false}) async {
    if (_resultSent) return;
    final duration = _callDuration;
    final answered = _remoteConnected && _remoteUid != null;
    if (!remoteEnded) {
      final reason = _resolveSessionEndReason(declined, answered);
      await _updateCallSessionStatus('ended', extra: {
        'endedReason': reason,
        'answered': answered,
        'declined': declined,
      });
    }
    if (!widget.isIncoming && !answered && !remoteEnded) {
      unawaited(_notifyCallCancelled());
    }
    final result = {
      'answered': answered,
      if (duration != null && answered) 'durationMillis': duration.inMilliseconds,
      'isVideo': widget.isVideo,
      if (declined) 'declined': true,
    };
    _resultSent = true;
    _stopDurationTicker();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _notifyCallCancelled() async {
    if (_cancelSignalSent || _activeChannelId.isEmpty || widget.targetProfile.uid.isEmpty) {
      return;
    }
    _cancelSignalSent = true;
    await NotificationService().cancelCallInvite(
      channelId: _activeChannelId,
      calleeId: widget.targetProfile.uid,
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
