import 'package:agora_rtc_engine/agora_rtc_engine.dart';

/// Shared Agora audio/video tuning for 1:1 voice and video calls.
abstract final class AgoraCallAudio {
  static const AudioScenarioType _scenario =
      AudioScenarioType.audioScenarioMeeting;
  static const AudioProfileType _profile =
      AudioProfileType.audioProfileSpeechStandard;

  static Future<void> configureCallEngine(
    RtcEngine engine, {
    required bool isVideo,
  }) async {
    await engine.setAudioScenario(_scenario);
    await engine.setAudioProfile(
      profile: _profile,
      scenario: _scenario,
    );

    if (isVideo) {
      await engine.enableVideo();
      await engine.setVideoEncoderConfiguration(
        const VideoEncoderConfiguration(
          dimensions: VideoDimensions(width: 640, height: 480),
          frameRate: 15,
          bitrate: 600,
          degradationPreference: DegradationPreference.maintainFramerate,
        ),
      );
      await engine.enableDualStreamMode(enabled: true);
      await engine.setRemoteSubscribeFallbackOption(
        StreamFallbackOptions.streamFallbackOptionVideoStreamLow,
      );
    } else {
      await engine.enableAudio();
    }
  }

  static ChannelMediaOptions ringingMediaOptions() {
    return const ChannelMediaOptions(
      publishCameraTrack: false,
      publishMicrophoneTrack: false,
    );
  }

  static ChannelMediaOptions talkMediaOptions({
    required bool isVideo,
    required bool videoMuted,
    required bool micMuted,
  }) {
    return ChannelMediaOptions(
      publishCameraTrack: isVideo && !videoMuted,
      publishMicrophoneTrack: !micMuted,
    );
  }

  /// Unmute/publish mic (and camera when applicable) after both sides are connected.
  static Future<void> startTalkPhase(
    RtcEngine engine, {
    required bool isVideo,
    required bool videoMuted,
  }) async {
    if (isVideo && !videoMuted) {
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
    }

    await engine.muteLocalAudioStream(false);
    await engine.updateChannelMediaOptions(
      talkMediaOptions(
        isVideo: isVideo,
        videoMuted: videoMuted,
        micMuted: false,
      ),
    );
    await engine.setEnableSpeakerphone(isVideo);
  }
}
