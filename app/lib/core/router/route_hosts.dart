import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../network/private_signal.dart';

import '../domain/world_cell.dart';
import '../errors/backend_exception.dart';
import '../ids/client_request_id.dart';
import '../notifications/product_analytics.dart';
import '../providers/backend_providers.dart';
import '../theme/app_colors.dart';
import '../../features/auth/application/auth_gate_controller.dart';
import '../../features/auth/application/auth_flow_controller.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/chat/presentation/conversation_screen.dart';
import '../../features/inbox/domain/inbox_repository.dart';
import '../../features/inbox/presentation/inbox_screen.dart';
import '../../features/my_notes/presentation/my_notes_screen.dart';
import '../../features/safety/domain/safety_repository.dart';
import '../../features/safety/presentation/report_block_sheet.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/wall/application/offline_wall_host.dart';
import '../../features/wall/application/shared_wall_host.dart';
import '../../features/wall/domain/wall_repository.dart';
import 'app_routes.dart';

final class BootstrapRouteHost extends ConsumerWidget {
  const BootstrapRouteHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(authGateControllerProvider);
    return AnimatedBuilder(
      animation: gate,
      builder: (context, _) {
        final unavailable = gate.status == AuthGateStatus.backendUnavailable;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(unavailable
                          ? gate.errorMessage ?? 'Chưa thể kết nối dịch vụ.'
                          : 'Đang kiểm tra phiên đăng nhập…'),
                      if (unavailable) ...<Widget>[
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => context.go(AppRoute.offlineDemo.path),
                          child: const Text('Mở bản thử ngoại tuyến'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class WelcomeRouteHost extends ConsumerWidget {
  const WelcomeRouteHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authFlowControllerProvider);
    final gate = ref.watch(authGateControllerProvider);
    return WelcomeScreen(
      initialEmail: gate.currentEmail,
      onSendEmailOtp: auth.sendEmailOtp,
      onResendOtp: auth.sendEmailOtp,
      onVerifyOtp: (email, token) => auth.verifyEmailOtp(email: email, token: token),
      onOpenOfflineDemo: () => context.go(AppRoute.offlineDemo.path),
    );
  }
}

final class OnboardingRouteHost extends ConsumerWidget {
  const OnboardingRouteHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authFlowControllerProvider);
    return OnboardingScreen(
      onCompleteOnboarding: ({
        required adultConfirmed,
        required termsAccepted,
        required privacyAccepted,
        required communityRulesAccepted,
        required onboardingAcknowledged,
      }) => auth.completeOnboarding(
        adultConfirmed: adultConfirmed,
        termsAccepted: termsAccepted,
        privacyAccepted: privacyAccepted,
        communityRulesAccepted: communityRulesAccepted,
        onboardingAcknowledged: onboardingAcknowledged,
      ),
    );
  }
}

final class AccountStatusRouteHost extends ConsumerWidget {
  const AccountStatusRouteHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authFlowControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Trạng thái tài khoản')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.lock_outline_rounded, size: 42),
                const SizedBox(height: 16),
                const Text(
                  'Tài khoản hiện chưa thể sử dụng các tính năng cộng đồng.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () async {
                    await auth.signOut();
                    if (context.mounted) context.go(AppRoute.welcome.path);
                  },
                  child: const Text('Đăng xuất'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class OfflineDemoRouteHost extends StatelessWidget {
  const OfflineDemoRouteHost({super.key});

  @override
  Widget build(BuildContext context) => const OfflineWallHost();
}

final class SharedWallRouteHost extends StatelessWidget {
  const SharedWallRouteHost({super.key, this.initialCell});

  final WorldCell? initialCell;

  @override
  Widget build(BuildContext context) => SharedWallHost(initialCell: initialCell);
}

final class InboxRouteHost extends ConsumerStatefulWidget {
  const InboxRouteHost({super.key});

  @override
  ConsumerState<InboxRouteHost> createState() => _InboxRouteHostState();
}

final class _InboxRouteHostState extends ConsumerState<InboxRouteHost>
    with WidgetsBindingObserver {
  InboxPage<EncouragementRecord>? _encouragementPage;
  InboxPage<ConversationRecord>? _conversationPage;
  PrivateSignal? _channel;
  bool _loading = true;
  bool _loadingMoreEncouragements = false;
  bool _loadingMoreConversations = false;
  int _loadGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToInbox();
    unawaited(_load());
  }

  void _subscribeToInbox() {
    final client = ref.read(apiClientProvider);
    final userId = client?.session.userId;
    if (client == null || userId == null) return;
    _channel = PrivateSignal(client, 'user:$userId', () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    channel?.close();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() {
      _loading = true;
      _loadingMoreEncouragements = false;
      _loadingMoreConversations = false;
      _error = null;
    });
    try {
      final repository = ref.read(inboxRepositoryProvider);
      final pages = await Future.wait<Object>(<Future<Object>>[
        repository.getEncouragements(),
        repository.getConversations(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _encouragementPage = pages[0] as InboxPage<EncouragementRecord>;
        _conversationPage = pages[1] as InboxPage<ConversationRecord>;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreEncouragements() async {
    final page = _encouragementPage;
    final cursor = page?.nextCursor;
    if (page == null || cursor == null || _loading || _loadingMoreEncouragements) return;
    final generation = _loadGeneration;
    setState(() => _loadingMoreEncouragements = true);
    try {
      final next = await ref.read(inboxRepositoryProvider).getEncouragements(cursor: cursor);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _encouragementPage = InboxPage<EncouragementRecord>(
          items: <EncouragementRecord>[...page.items, ...next.items],
          nextCursor: next.nextCursor,
        );
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMoreEncouragements = false);
      }
    }
  }

  Future<void> _loadMoreConversations() async {
    final page = _conversationPage;
    final cursor = page?.nextCursor;
    if (page == null || cursor == null || _loading || _loadingMoreConversations) return;
    final generation = _loadGeneration;
    setState(() => _loadingMoreConversations = true);
    try {
      final next = await ref.read(inboxRepositoryProvider).getConversations(cursor: cursor);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _conversationPage = InboxPage<ConversationRecord>(
          items: <ConversationRecord>[...page.items, ...next.items],
          nextCursor: next.nextCursor,
        );
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMoreConversations = false);
      }
    }
  }

  String _encouragementText(String key) => switch (key) {
        'LISTEN' => 'Mình đang lắng nghe bạn',
        'TOMORROW' => 'Ngày mai sẽ ổn hơn thôi',
        'TRIED' => 'Bạn đã rất cố gắng rồi',
        'THANKS' => 'Cảm ơn bạn đã can đảm chia sẻ',
        'HUG' => 'Gửi bạn một cái ôm thật ấm',
        _ => 'Bạn nhận được một lời động viên',
      };

  String _messageFor(Object error) => error is BackendException
      ? error.message
      : 'Không thể tải hộp thư. Hãy thử lại sau.';

  @override
  Widget build(BuildContext context) {
    final encouragements = _encouragementPage?.items.map((item) => EncouragementInboxItem(
      id: item.id,
      messageText: _encouragementText(item.templateKey),
      receivedAt: item.receivedAt,
      noteSnippet: 'Một tờ giấy của bạn nhận được lời động viên',
      cellX: item.cellX,
      cellY: item.cellY,
    )).toList(growable: false);
    final conversations = _conversationPage?.items.map((item) => ConversationInboxItem(
      conversationId: item.conversationId,
      lastMessageSnippet: item.lastMessagePreview,
      updatedAt: item.lastMessageAt,
      unreadCount: item.unreadCount,
      remainingOutbound: item.remainingOutbound,
    )).toList(growable: false);
    return InboxScreen(
      encouragements: encouragements,
      conversations: conversations,
      isLoading: _loading,
      errorMessage: _error,
      onRefresh: _load,
      onLoadMoreEncouragements: _encouragementPage?.nextCursor == null
          ? null
          : _loadMoreEncouragements,
      onLoadMoreConversations: _conversationPage?.nextCursor == null
          ? null
          : _loadMoreConversations,
      isLoadingMoreEncouragements: _loadingMoreEncouragements,
      isLoadingMoreConversations: _loadingMoreConversations,
      onOpenConversation: (id) => context.goNamed(
        AppRoute.conversation.name,
        pathParameters: <String, String>{'conversationId': id},
      ),
      onJumpToNote: (cellX, cellY) {
        final records = _encouragementPage?.items.where((item) =>
          item.cellX == cellX && item.cellY == cellY && item.notificationId != null
        ).toList(growable: false);
        if (records != null && records.isNotEmpty) {
          final record = records.first;
          unawaited(ref.read(inboxRepositoryProvider)
            .markNotificationRead(record.notificationId!).catchError((Object _) {}));
        }
        context.go(AppRoute.wall.path, extra: WorldCell(x: cellX, y: cellY));
      },
    );
  }
}

final class MyNotesRouteHost extends ConsumerStatefulWidget {
  const MyNotesRouteHost({super.key});

  @override
  ConsumerState<MyNotesRouteHost> createState() => _MyNotesRouteHostState();
}

final class _MyNotesRouteHostState extends ConsumerState<MyNotesRouteHost> {
  MyNotesPage? _page;
  bool _loading = true;
  String? _error;
  final Map<String, String> _deleteRequestIds = <String, String>{};
  final Map<String, String> _editRequestIds = <String, String>{};
  final Map<String, String> _editRequestContents = <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final page = await ref.read(wallRepositoryProvider).getMyNotes();
      if (mounted) setState(() => _page = page);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(Object error) => error is BackendException
      ? error.message
      : 'Không thể tải nhật ký của bạn. Hãy thử lại sau.';

  Future<void> _delete(String id) async {
    try {
      await ref.read(wallRepositoryProvider).deleteNote(
        id,
        clientRequestId: _deleteRequestIds.putIfAbsent(id, ClientRequestId.create),
      );
      _deleteRequestIds.remove(id);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _edit(String id) async {
    final matchingNotes = _page?.items.where((item) => item.id == id).toList(growable: false);
    if (matchingNotes == null || matchingNotes.isEmpty) return;
    final note = matchingNotes.first;
    final controller = TextEditingController(text: note.content);
    try {
      final content = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sửa tờ giấy'),
          content: TextField(controller: controller, maxLength: 1000, maxLines: 6, autofocus: true),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Lưu')),
          ],
        ),
      );
      if (content == null || !mounted) return;
      if (_editRequestContents[id] != content || !_editRequestIds.containsKey(id)) {
        _editRequestContents[id] = content;
        _editRequestIds[id] = ClientRequestId.create();
      }
      await ref.read(wallRepositoryProvider).editNote(
        noteId: id,
        newContent: content,
        clientRequestId: _editRequestIds[id]!,
      );
      _editRequestIds.remove(id);
      _editRequestContents.remove(id);
      await _load();
    } catch (error) {
      _showError(error);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _toggleChat(String id, bool allowChat) async {
    try {
      await ref.read(wallRepositoryProvider).updateNoteChat(id, allowChat: allowChat);
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(error))));
  }

  @override
  Widget build(BuildContext context) => MyNotesScreen(
        dailyQuotaUsed: _page?.dailyQuotaUsed,
        notes: _page?.items.map((note) => MyNoteItem(
          id: note.id,
          content: note.content,
          paperColor: note.paperColor,
          status: note.status,
          createdAt: note.createdAt,
          cellX: note.cell.x,
          cellY: note.cell.y,
          canEdit: note.canEdit,
          canDelete: note.canDelete,
          allowChat: note.allowChat,
        )).toList(growable: false),
        isLoading: _loading,
        errorMessage: _error,
        onRefresh: _load,
        onJumpToNote: (x, y) => context.go(AppRoute.wall.path, extra: WorldCell(x: x, y: y)),
        onEditNote: (id) => unawaited(_edit(id)),
        onDeleteNote: (id) => unawaited(_delete(id)),
        onToggleChat: (id, allowChat) => unawaited(_toggleChat(id, allowChat)),
      );
}

final class SettingsRouteHost extends ConsumerWidget {
  const SettingsRouteHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authFlowControllerProvider);
    final gate = ref.read(authGateControllerProvider);
    final deletionRequestId = ref.read(accountDeletionRequestIdProvider);
    final notificationsAvailable = ref.watch(firebaseAvailableProvider);
    return AnimatedBuilder(
      animation: gate,
      builder: (context, _) {
        Future<void> saveReducedMotion(bool value) async {
          try {
            await auth.updateSettings(reducedMotion: value);
            await gate.refresh();
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error is BackendException ? error.message : 'Không lưu được cài đặt.')),
              );
            }
          }
        }

        Future<void> saveNotifications(bool value) async {
          try {
            await auth.updateSettings(notificationsEnabled: value);
            await gate.refresh();
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error is BackendException ? error.message : 'Không lưu được cài đặt.')),
              );
            }
          }
        }

        return SettingsScreen(
          notificationsAvailable: notificationsAvailable,
          notificationsEnabled: gate.accountSettings?.notificationsEnabled ?? false,
          reduceMotionEnabled: gate.accountSettings?.reducedMotion ?? false,
          userEmail: gate.currentEmail,
          isModerator: gate.isModerator,
          onOpenModerator: () => context.go(AppRoute.moderator.path),
          onToggleNotifications: notificationsAvailable ? saveNotifications : null,
          onToggleReduceMotion: (value) => unawaited(saveReducedMotion(value)),
          onSignOut: auth.signOut,
          onRequestAccountDeletion: () => auth.requestAccountDeletion(
            clientRequestId: deletionRequestId,
          ),
        );
      },
    );
  }
}

final accountDeletionRequestIdProvider = Provider<String>((ref) => ClientRequestId.create());

final class ConversationRouteHost extends ConsumerStatefulWidget {
  const ConversationRouteHost({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationRouteHost> createState() => _ConversationRouteHostState();
}

final class _ConversationRouteHostState extends ConsumerState<ConversationRouteHost>
    with WidgetsBindingObserver {
  MessagePage? _page;
  PrivateSignal? _channel;
  bool _loading = true;
  String? _error;
  String? _requestBody;
  String? _requestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToConversation();
    unawaited(_load());
  }

  void _subscribeToConversation() {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    _channel = PrivateSignal(client, 'conversation:${widget.conversationId}', () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    channel?.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await ref.read(inboxRepositoryProvider).getMessages(widget.conversationId);
      if (mounted) setState(() { _page = page; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(Object error) => error is BackendException
      ? error.message
      : 'Không thể kết nối cuộc trò chuyện lúc này.';

  Future<void> _send(String text) async {
    final body = text.trim();
    if (_requestBody != body || _requestId == null) {
      _requestBody = body;
      _requestId = ClientRequestId.create();
    }
    await ref.read(inboxRepositoryProvider).sendMessage(
      conversationId: widget.conversationId,
      body: body,
      clientRequestId: _requestId!,
    );
    unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.messageSent));
    _requestBody = null;
    _requestId = null;
    await _load();
  }

  Future<void> _close() async {
    try {
      await ref.read(inboxRepositoryProvider).closeConversation(widget.conversationId);
      if (mounted) context.go(AppRoute.inbox.path);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _block() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chặn đối phương?'),
        content: const Text('Hai bên sẽ không thể gửi thêm tin nhắn trong cuộc trò chuyện này.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Chặn')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(safetyRepositoryProvider).blockFromConversation(widget.conversationId);
      if (mounted) context.go(AppRoute.inbox.path);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _report() async {
    var busy = false;
    String? errorText;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ReportBlockSheet(
          targetId: widget.conversationId,
          targetType: 'conversation',
          isSubmitting: busy,
          errorMessage: errorText,
          onClose: () => Navigator.of(sheetContext).pop(),
          onSubmitReport: ({required reason, detail, required blockPartner}) async {
            setSheetState(() { busy = true; errorText = null; });
            try {
              final safety = ref.read(safetyRepositoryProvider);
              if (blockPartner) {
                await safety.reportAndBlockConversation(
                  conversationId: widget.conversationId,
                  reason: reason,
                  description: detail,
                );
              } else {
                await safety.report(
                  targetType: 'conversation',
                  targetId: widget.conversationId,
                  reason: reason,
                  description: detail,
                );
              }
              unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.reportSubmitted));
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
          onBlockOnly: () async {
            setSheetState(() => busy = true);
            try {
              await ref.read(safetyRepositoryProvider).blockFromConversation(widget.conversationId);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
        ),
      ),
    );
  }

  Future<void> _reportUser() async {
    var busy = false;
    String? errorText;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ReportBlockSheet(
          // This is an opaque conversation context ID, never a user ID.
          targetId: widget.conversationId,
          targetType: 'user',
          isSubmitting: busy,
          errorMessage: errorText,
          onClose: () => Navigator.of(sheetContext).pop(),
          onSubmitReport: ({required reason, detail, required blockPartner}) async {
            setSheetState(() { busy = true; errorText = null; });
            try {
              final safety = ref.read(safetyRepositoryProvider);
              if (blockPartner) {
                await safety.reportAndBlockUserFromConversation(
                  conversationId: widget.conversationId,
                  reason: reason,
                  description: detail,
                );
              } else {
                await safety.reportUserFromConversation(
                  conversationId: widget.conversationId,
                  reason: reason,
                  description: detail,
                );
              }
              unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.reportSubmitted));
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
          onBlockOnly: () async {
            setSheetState(() => busy = true);
            try {
              await ref.read(safetyRepositoryProvider).blockFromConversation(widget.conversationId);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
        ),
      ),
    );
  }

  Future<void> _reportMessage(String messageId) async {
    var busy = false;
    String? errorText;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ReportBlockSheet(
          targetId: messageId,
          targetType: 'message',
          isSubmitting: busy,
          errorMessage: errorText,
          onClose: () => Navigator.of(sheetContext).pop(),
          onSubmitReport: ({required reason, detail, required blockPartner}) async {
            setSheetState(() { busy = true; errorText = null; });
            try {
              final safety = ref.read(safetyRepositoryProvider);
              if (blockPartner) {
                await safety.reportAndBlockMessage(
                  messageId: messageId,
                  reason: reason,
                  description: detail,
                );
              } else {
                await safety.report(
                  targetType: 'message',
                  targetId: messageId,
                  reason: reason,
                  description: detail,
                );
              }
              unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.reportSubmitted));
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (blockPartner && mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
          onBlockOnly: () async {
            setSheetState(() => busy = true);
            try {
              await ref.read(safetyRepositoryProvider).blockFromConversation(widget.conversationId);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) context.go(AppRoute.inbox.path);
            } catch (error) {
              setSheetState(() => errorText = _messageFor(error));
            } finally {
              if (sheetContext.mounted) setSheetState(() => busy = false);
            }
          },
        ),
      ),
    );
  }

  void _showError(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_messageFor(error))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text(_error ?? 'Chưa tải được cuộc trò chuyện.'),
                  TextButton(onPressed: () { setState(() => _loading = true); unawaited(_load()); }, child: const Text('Thử lại')),
                ]),
        ),
      );
    }
    return ConversationScreen(
      conversation: page.conversation,
      messages: page.items,
      sourceNoteContent: page.sourceNoteContent,
      errorMessage: _error,
      onSendMessage: _send,
      onReportMessage: (messageId) => unawaited(_reportMessage(messageId)),
      onCloseConversation: () => unawaited(_close()),
      onBlockPartner: () => unawaited(_block()),
      onReport: () => unawaited(_report()),
      onReportUser: () => unawaited(_reportUser()),
      onBack: () => context.go(AppRoute.inbox.path),
    );
  }
}

String _messageFor(Object error) => error is BackendException
    ? error.message
    : 'Không thể kết nối lúc này. Hãy thử lại sau.';

