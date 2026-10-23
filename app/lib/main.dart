import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'core/config/api_bootstrap.dart';
import 'core/network/api_client.dart';
import 'core/notifications/firebase_runtime.dart';
import 'core/providers/backend_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseAvailable = await FirebaseRuntime.initialize();
  final bootstrap = ApiBootstrap.fromEnvironment();
  ApiClient? client;
  String? initializationError;
  if (bootstrap.isConfigured) {
    try {
      final session = ApiSession(const FlutterSecureStorage());
      await session.restore();
      client = ApiClient(bootstrap.baseUrl, session);
    } catch (_) {
      client = null;
      initializationError = 'Không thể đọc phiên đăng nhập đã lưu.';
    }
  }
  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        apiInitializationErrorProvider.overrideWithValue(initializationError),
        firebaseAvailableProvider.overrideWithValue(firebaseAvailable),
      ],
      child: const TuongNhoApp(),
    ),
  );
}
