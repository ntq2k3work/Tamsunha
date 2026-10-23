import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/notifications/product_analytics.dart';
import 'core/providers/backend_providers.dart';
import 'core/notifications/push_session_host.dart';
import 'core/theme/app_theme.dart';

class TuongNhoApp extends ConsumerStatefulWidget {
  const TuongNhoApp({super.key});

  @override
  ConsumerState<TuongNhoApp> createState() => _TuongNhoAppState();
}

class _TuongNhoAppState extends ConsumerState<TuongNhoApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.appOpened));
    });
  }

  @override
  Widget build(BuildContext context) {
    return PushSessionHost(
      child: MaterialApp.router(
        title: 'Tường Nhỏ',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: ref.watch(appRouterProvider),
      ),
    );
  }
}
