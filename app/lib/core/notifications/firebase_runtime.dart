import 'dart:async';
import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

abstract final class FirebaseRuntime {
  static bool _crashHandlersInstalled = false;

  static bool get isEnabled =>
      const bool.fromEnvironment('FIREBASE_ENABLED', defaultValue: false);

  static bool get _crashReportingEnabled => const bool.fromEnvironment(
        'CRASH_REPORTING_ENABLED',
        defaultValue: false,
      );

  static bool get analyticsEnabled => const bool.fromEnvironment(
        'PRODUCT_ANALYTICS_ENABLED',
        defaultValue: false,
      );

  static Future<bool> initialize() async {
    if (!isEnabled || !_isMobilePlatform) return false;

    try {
      await Firebase.initializeApp();
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(_crashReportingEnabled);
      await FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(analyticsEnabled);
      if (_crashReportingEnabled) _installContentFreeCrashHandlers();
      return true;
    } catch (_) {
      // Firebase is optional until a project and native app configuration exist.
      return false;
    }
  }

  static bool get _isMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static void _installContentFreeCrashHandlers() {
    if (_crashHandlersInstalled) return;
    _crashHandlersInstalled = true;

    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterErrorHandler?.call(details);
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          const _ContentFreeCrashSignal('Flutter framework error'),
          details.stack ?? StackTrace.current,
          fatal: false,
        ),
      );
    };

    final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(
          const _ContentFreeCrashSignal('Uncaught platform error'),
          stack,
          fatal: true,
        ),
      );
      return previousPlatformErrorHandler?.call(error, stack) ?? false;
    };
  }
}

final class _ContentFreeCrashSignal implements Exception {
  const _ContentFreeCrashSignal(this.category);

  final String category;

  @override
  String toString() => category;
}
