import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/safety/application/moderator_console_host.dart';
import '../../features/auth/application/auth_gate_controller.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../domain/world_cell.dart';
import '../providers/backend_providers.dart';
import 'app_routes.dart';
import 'route_hosts.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final gate = ref.watch(authGateControllerProvider);
  final router = GoRouter(
    initialLocation: AppRoute.bootstrap.path,
    refreshListenable: gate,
    redirect: (context, state) {
      final path = state.uri.path;
      final isPublic = path == AppRoute.welcome.path ||
          path == AppRoute.offlineDemo.path;
      switch (gate.status) {
        case AuthGateStatus.loading:
          return path == AppRoute.bootstrap.path ? null : AppRoute.bootstrap.path;
        case AuthGateStatus.backendUnavailable:
          return path == AppRoute.bootstrap.path || isPublic
              ? null
              : AppRoute.bootstrap.path;
        case AuthGateStatus.backendNotConfigured:
        case AuthGateStatus.signedOut:
          return isPublic ? null : AppRoute.welcome.path;
        case AuthGateStatus.onboardingRequired:
          if (isPublic || path == AppRoute.onboarding.path) return null;
          return AppRoute.onboarding.path;
        case AuthGateStatus.ready:
          if (path == AppRoute.bootstrap.path ||
              path == AppRoute.welcome.path ||
              path == AppRoute.onboarding.path ||
              path == AppRoute.accountStatus.path) {
            return AppRoute.wall.path;
          }
          if (path == AppRoute.moderator.path && !gate.isModerator) {
            return AppRoute.inbox.path;
          }
          return null;
        case AuthGateStatus.suspended:
          return path == AppRoute.accountStatus.path || isPublic
              ? null
              : AppRoute.accountStatus.path;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.bootstrap.path,
        builder: (context, state) => const BootstrapRouteHost(),
      ),
      GoRoute(
        path: AppRoute.welcome.path,
        builder: (context, state) => const WelcomeRouteHost(),
      ),
      GoRoute(
        path: AppRoute.onboarding.path,
        builder: (context, state) => const OnboardingRouteHost(),
      ),
      GoRoute(
        path: AppRoute.accountStatus.path,
        builder: (context, state) => const AccountStatusRouteHost(),
      ),
      GoRoute(
        path: AppRoute.offlineDemo.path,
        builder: (context, state) => const OfflineDemoRouteHost(),
      ),
      GoRoute(
        path: AppRoute.conversation.path,
        name: AppRoute.conversation.name,
        builder: (context, state) => ConversationRouteHost(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: AppRoute.moderator.path,
        builder: (context, state) => const ModeratorConsoleRouteHost(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          child: navigationShell,
        ),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.wall.path,
                builder: (context, state) => SharedWallRouteHost(
                  initialCell: state.extra is WorldCell ? state.extra as WorldCell : null,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.inbox.path,
                builder: (context, state) => const InboxRouteHost(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.myNotes.path,
                builder: (context, state) => const MyNotesRouteHost(),
              ),
              GoRoute(
                path: AppRoute.settings.path,
                builder: (context, state) => const SettingsRouteHost(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
