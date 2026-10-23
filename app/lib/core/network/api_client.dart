import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../errors/backend_exception.dart';

final class ApiSession {
  ApiSession(this._storage);

  static const _tokenKey = 'api_bearer_token_v1';
  static const _emailKey = 'api_email_v1';
  static const _userIdKey = 'api_user_id_v1';

  final FlutterSecureStorage _storage;
  final _changes = StreamController<bool>.broadcast();
  String? token;
  String? email;
  String? userId;

  bool get hasSession => token != null && token!.isNotEmpty;
  Stream<bool> get changes => _changes.stream;

  Future<void> restore() async {
    token = await _storage.read(key: _tokenKey);
    email = await _storage.read(key: _emailKey);
    userId = await _storage.read(key: _userIdKey);
    _changes.add(hasSession);
  }

  Future<void> save({required String bearerToken, required String userEmail,
      required String id}) async {
    await _storage.write(key: _tokenKey, value: bearerToken);
    await _storage.write(key: _emailKey, value: userEmail);
    await _storage.write(key: _userIdKey, value: id);
    token = bearerToken;
    email = userEmail;
    userId = id;
    _changes.add(true);
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userIdKey);
    token = null;
    email = null;
    userId = null;
    _changes.add(false);
  }

  void dispose() => _changes.close();
}

final class ApiClient {
  ApiClient(this.baseUrl, this.session, {http.Client? transport})
      : _transport = transport ?? http.Client();

  final String baseUrl;
  final ApiSession session;
  final http.Client _transport;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<Map<String, Object?>> post(String path,
      {Map<String, Object?>? body, bool authenticated = true}) async {
    if (!isConfigured) throw BackendException.notConfigured();
    final token = session.token;
    if (authenticated && (token == null || token.isEmpty)) {
      throw const BackendException(
        code: 'UNAUTHENTICATED', message: 'Hãy đăng nhập để tiếp tục.');
    }
    http.Response response;
    try {
      response = await _transport.post(Uri.parse('$baseUrl$path'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (authenticated) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body ?? const <String, Object?>{}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw BackendException.unavailable();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw BackendException.unavailable();
    }
    if (decoded is! Map) throw BackendException.unavailable();
    final envelope = Map<String, Object?>.from(decoded);
    if (authenticated && response.statusCode == 401) {
      await session.clear();
    }
    final error = envelope['error'];
    if (error is Map) {
      throw BackendException.fromEnvelope(Map<String, Object?>.from(error));
    }
    if (response.statusCode == 401) {
      throw const BackendException(code: 'UNAUTHENTICATED',
          message: 'Phiên đăng nhập đã kết thúc. Hãy đăng nhập lại.');
    }
    if (response.statusCode >= 400) throw BackendException.unavailable();
    return requireRpcData(envelope);
  }

  Future<Map<String, Object?>> rpc(String name,
      {Map<String, Object?>? params}) async =>
      requireRpcData(await post('/api/v1/rpc/$name', body: params));

  Future<String> authorizeChannel(String channel, String socketId) async {
    final token = session.token;
    if (token == null) throw BackendException.unavailable();
    http.Response response;
    try {
      response = await _transport.post(Uri.parse('$baseUrl/api/broadcasting/auth'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, String>{
            'channel_name': channel, 'socket_id': socketId,
          })).timeout(const Duration(seconds: 10));
      final raw = jsonDecode(response.body);
      if (response.statusCode != 200 || raw is! Map || raw['auth'] is! String) {
        throw BackendException.unavailable();
      }
      return raw['auth'] as String;
    } catch (_) {
      throw BackendException.unavailable();
    }
  }

  void close() => _transport.close();
}
