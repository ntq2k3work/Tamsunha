import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

final class PrivateSignal {
  PrivateSignal(this._api, this._channelName, this._onSignal) {
    _connect();
  }

  final ApiClient _api;
  final String _channelName;
  final void Function() _onSignal;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _closed = false;

  static const _wsUrl = String.fromEnvironment('REVERB_WS_URL');
  static const _appKey = String.fromEnvironment('REVERB_APP_KEY');

  void _connect() {
    if (_closed || _wsUrl.isEmpty || _appKey.isEmpty ||
        !_api.session.hasSession) return;
    final base = Uri.tryParse(_wsUrl);
    if (base == null || (base.scheme != 'ws' && base.scheme != 'wss')) return;
    final socket = WebSocketChannel.connect(base.replace(
      path: '/app/$_appKey',
      queryParameters: <String, String>{
        'protocol': '7', 'client': 'flutter', 'version': '1.0', 'flash': 'false',
      },
    ));
    _socket = socket;
    _subscription = socket.stream.listen((raw) async {
      if (_closed || raw is! String) return;
      Object? decoded;
      try { decoded = jsonDecode(raw); } catch (_) { return; }
      if (decoded is! Map) return;
      final event = decoded['event'];
      if (event == 'pusher:ping') {
        socket.sink.add(jsonEncode(<String, Object?>{
          'event': 'pusher:pong', 'data': <String, Object?>{},
        }));
        return;
      }
      if (event == 'pusher:connection_established') {
        final data = decoded['data'];
        Object? connection;
        try { connection = data is String ? jsonDecode(data) : data; }
        catch (_) { return; }
        if (connection is! Map || connection['socket_id'] is! String) return;
        try {
          final auth = await _api.authorizeChannel(
              'private-$_channelName', connection['socket_id'] as String);
          if (_closed) return;
          socket.sink.add(jsonEncode(<String, Object?>{
            'event': 'pusher:subscribe',
            'data': <String, String>{
              'channel': 'private-$_channelName', 'auth': auth,
            },
          }));
        } catch (_) { _scheduleRetry(); }
      } else if (event == 'pusher_internal:subscription_succeeded' &&
          decoded['channel'] == 'private-$_channelName') {
        _onSignal();
      } else if (decoded['channel'] == 'private-$_channelName' &&
          (event == 'signal' || event == 'wall_changed')) {
        _onSignal();
      }
    }, onDone: _scheduleRetry, onError: (Object _) => _scheduleRetry());
  }

  void _scheduleRetry() {
    if (_closed || _retry != null) return;
    _retry = Timer(const Duration(seconds: 5), () {
      _retry = null;
      _subscription?.cancel();
      _socket?.sink.close();
      _connect();
    });
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_socket?.sink.close());
  }
}
