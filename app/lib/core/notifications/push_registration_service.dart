import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';

final class PushRegistrationService {
  PushRegistrationService(this._client)
      : _messaging = FirebaseMessaging.instance;

  static const _deviceKeyPreference = 'push_device_key_hash_v1';

  final ApiClient _client;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokenSubscription;
  bool? _desiredEnabled;
  bool _desiredPermissionPrompt = false;
  bool _syncing = false;
  bool _disposed = false;

  Future<void> sync(bool enabled, {bool requestPermission = false}) async {
    if (_disposed) return;
    _desiredEnabled = enabled;
    _desiredPermissionPrompt = requestPermission;
    if (_syncing) return;

    _syncing = true;
    try {
      while (_desiredEnabled != null) {
        final desired = _desiredEnabled!;
        final shouldPrompt = _desiredPermissionPrompt;
        _desiredEnabled = null;
        _desiredPermissionPrompt = false;
        await _apply(desired, requestPermission: shouldPrompt);
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _apply(bool enabled, {required bool requestPermission}) async {
    if (!enabled || !_client.session.hasSession) {
      await _disableAndUnregister();
      return;
    }

    final userId = _client.session.userId;
    if (userId == null) return;
    var permission = await _messaging.getNotificationSettings();
    if (permission.authorizationStatus == AuthorizationStatus.notDetermined &&
        requestPermission) {
      permission = await _messaging.requestPermission(
        alert: true,
        badge: false,
        sound: false,
        provisional: true,
      );
    }

    if (permission.authorizationStatus == AuthorizationStatus.notDetermined) return;
    if (!_hasPermission(permission.authorizationStatus)) {
      await _disableAndUnregister();
      return;
    }

    await _messaging.setAutoInitEnabled(true);
    final token = await _messaging.getToken();
    if (token == null || token.length < 20) return;
    await _register(userId, token);

    await _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen((refreshedToken) {
      if (_disposed || _client.session.userId != userId) return;
      unawaited(_register(userId, refreshedToken).catchError((Object _) {}));
    });
  }

  bool _hasPermission(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> _register(String userId, String token) async {
    if (_client.session.userId != userId || token.length < 20) return;
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) return;

    final deviceKeyHash = await _deviceKeyHash();
    await _client.rpc('register_device', params: <String, Object?>{
      'p_device_key_hash': deviceKeyHash,
      'p_push_token': token,
      'p_platform': platform,
    });
  }

  Future<void> _disableAndUnregister() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;

    final user = _client.session.userId;
    final deviceKeyHash = await _readDeviceKeyHash();
    try {
      if (user != null && deviceKeyHash != null) {
        await _client.rpc('unregister_device', params: <String, Object?>{
          'p_device_key_hash': deviceKeyHash,
        });
      }
    } finally {
      try {
        await _messaging.setAutoInitEnabled(false);
        await _messaging.deleteToken();
      } catch (_) {
        // Local sign-out and app use must not depend on push-provider availability.
      }
    }
  }

  Future<String> _deviceKeyHash() async {
    final existing = await _readDeviceKeyHash();
    if (existing != null) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final created = sha256.convert(bytes).toString();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_deviceKeyPreference, created);
    return created;
  }

  Future<String?> _readDeviceKeyHash() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_deviceKeyPreference);
    return value != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)
        ? value
        : null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }
}
