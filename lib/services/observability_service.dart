import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

const bool kPilotObservabilityVerify = bool.fromEnvironment(
  'PILOT_OBSERVABILITY_VERIFY',
  defaultValue: false,
);

const bool kCrashlyticsPilotCrash = bool.fromEnvironment(
  'CRASHLYTICS_PILOT_CRASH',
  defaultValue: false,
);

/// Firebase Analytics + Crashlytics bootstrap shared across the van ecosystem.
class ObservabilityService {
  ObservabilityService._();

  static final ObservabilityService instance = ObservabilityService._();

  FirebaseAnalytics? _analytics;
  bool _ready = false;

  Future<void> initialize({required String appName}) async {
    if (_ready) {
      return;
    }

    try {
      _analytics = FirebaseAnalytics.instance;
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
      await crashlytics.setCustomKey('van_app', appName);

      final previousFlutterHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
        unawaited(crashlytics.recordFlutterFatalError(details));
        previousFlutterHandler?.call(details);
      };

      final previousPlatformHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        unawaited(crashlytics.recordError(error, stack, fatal: true));
        return previousPlatformHandler?.call(error, stack) ?? true;
      };

      await _analytics!.logEvent(
        name: 'app_start',
        parameters: <String, Object>{'van_app': appName},
      );
      _ready = true;
      await _runPilotVerificationIfRequested(appName: appName);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Observability init skipped: $error\n$stack');
      }
    }
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    if (!_ready || _analytics == null) {
      return;
    }

    try {
      final sanitized = <String, Object>{};
      for (final MapEntry<String, Object?> entry in parameters.entries) {
        final Object? value = entry.value;
        if (value == null) {
          continue;
        }
        if (value is String || value is num) {
          sanitized[entry.key] = value;
        } else {
          sanitized[entry.key] = value.toString();
        }
      }
      await _analytics!.logEvent(name: name, parameters: sanitized);
    } catch (_) {}
  }

  Future<void> logScreenView(String screenName) async {
    if (!_ready || _analytics == null) {
      return;
    }

    try {
      await _analytics!.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
  }) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: fatal,
      );
    } catch (_) {}
  }

  Future<void> _runPilotVerificationIfRequested({required String appName}) async {
    if (!kPilotObservabilityVerify) {
      return;
    }

    if (!kReleaseMode) {
      debugPrint(
        'PILOT_OBSERVABILITY_VERIFY ignored in debug — use flutter run --release',
      );
      return;
    }

    await logEvent(
      'pilot_observability_verify',
      parameters: <String, Object?>{'van_app': appName},
    );
    await recordError(
      Exception('van_pilot_nonfatal_$appName'),
      StackTrace.current,
      fatal: false,
    );

    if (kCrashlyticsPilotCrash) {
      Future<void>.delayed(const Duration(seconds: 5), () {
        FirebaseCrashlytics.instance.crash();
      });
    }
  }
}
