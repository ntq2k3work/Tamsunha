import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_gate_controller.dart';
import '../../features/auth/application/auth_flow_controller.dart';
import '../../features/auth/data/api_auth_repository.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/inbox/data/api_inbox_repository.dart';
import '../../features/inbox/domain/inbox_repository.dart';
import '../../features/safety/data/api_safety_repository.dart';
import '../../features/safety/data/api_moderation_repository.dart';
import '../../features/safety/domain/moderation_repository.dart';
import '../../features/safety/domain/safety_repository.dart';
import '../../features/wall/data/api_wall_repository.dart';
import '../../features/wall/domain/wall_repository.dart';
import '../network/api_client.dart';
import '../notifications/firebase_runtime.dart';
import '../notifications/product_analytics.dart';
import '../notifications/push_registration_service.dart';

final apiClientProvider = Provider<ApiClient?>((ref) => null);
final apiInitializationErrorProvider = Provider<String?>((ref) => null);
final firebaseAvailableProvider = Provider<bool>((ref) => false);

final productAnalyticsProvider = Provider<ProductAnalytics>((ref) {
  final analytics = ref.watch(firebaseAvailableProvider) &&
          FirebaseRuntime.analyticsEnabled
      ? FirebaseAnalytics.instance
      : null;
  return ProductAnalytics(analytics);
});

final pushRegistrationServiceProvider = Provider<PushRegistrationService?>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null || !ref.watch(firebaseAvailableProvider)) return null;

  final service = PushRegistrationService(client);
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(
    ref.watch(apiClientProvider),
    initializationError: ref.watch(apiInitializationErrorProvider),
  );
});

final wallRepositoryProvider = Provider<WallRepository>((ref) {
  return ApiWallRepository(ref.watch(apiClientProvider));
});

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  return ApiInboxRepository(ref.watch(apiClientProvider));
});

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return ApiSafetyRepository(ref.watch(apiClientProvider));
});

final moderationRepositoryProvider = Provider<ModerationRepository>((ref) {
  return ApiModerationRepository(ref.watch(apiClientProvider));
});

final authGateControllerProvider = Provider<AuthGateController>((ref) {
  final controller = AuthGateController(ref.watch(authRepositoryProvider));
  unawaited(controller.initialize());
  ref.onDispose(controller.dispose);
  return controller;
});

final authFlowControllerProvider = Provider<AuthFlowController>((ref) {
  return AuthFlowController(
    ref.watch(authRepositoryProvider),
    ref.watch(authGateControllerProvider),
    ref.watch(pushRegistrationServiceProvider),
  );
});
