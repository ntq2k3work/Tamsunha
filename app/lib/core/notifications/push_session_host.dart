import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_gate_controller.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../providers/backend_providers.dart';

class PushSessionHost extends ConsumerStatefulWidget {
  const PushSessionHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushSessionHost> createState() => _PushSessionHostState();
}

class _PushSessionHostState extends ConsumerState<PushSessionHost>
    with WidgetsBindingObserver {
  AuthGateController? _gate;
  StreamSubscription<RemoteMessage>? _openSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindGate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForPushOpens());
  }

  void _listenForPushOpens() {
    if (!mounted || !ref.read(firebaseAvailableProvider)) return;
    final messaging = FirebaseMessaging.instance;
    _openSubscription = messaging.onMessageOpenedApp.listen((_) => _openInbox());
    unawaited(messaging.getInitialMessage().then((message) {
      if (message != null && mounted) _openInbox();
    }).catchError((Object _) {}));
  }

  void _openInbox() {
    if (!mounted) return;
    ref.read(appRouterProvider).go(AppRoute.inbox.path);
  }

  void _bindGate() {
    if (!mounted) return;
    final nextGate = ref.read(authGateControllerProvider);
    if (!identical(nextGate, _gate)) {
      _gate?.removeListener(_syncRegistration);
      _gate = nextGate..addListener(_syncRegistration);
    }
    _syncRegistration();
  }

  void _syncRegistration() {
    final gate = _gate;
    final service = ref.read(pushRegistrationServiceProvider);
    if (gate == null || service == null) return;
    switch (gate.status) {
      case AuthGateStatus.loading:
      case AuthGateStatus.backendUnavailable:
      case AuthGateStatus.backendNotConfigured:
        return;
      case AuthGateStatus.ready:
        unawaited(
          service
              .sync(gate.accountSettings?.notificationsEnabled ?? false)
              .catchError((Object _) {}),
        );
        return;
      case AuthGateStatus.onboardingRequired:
      case AuthGateStatus.signedOut:
      case AuthGateStatus.suspended:
        unawaited(service.sync(false).catchError((Object _) {}));
        return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncRegistration();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gate?.removeListener(_syncRegistration);
    unawaited(_openSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(authGateControllerProvider);
    if (!identical(gate, _gate)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindGate());
    }
    return widget.child;
  }
}
