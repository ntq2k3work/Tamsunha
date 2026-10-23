import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/backend_exception.dart';
import '../../../core/providers/backend_providers.dart';
import '../domain/moderation_repository.dart';
import '../presentation/moderator_console_screen.dart';

final class ModeratorConsoleRouteHost extends ConsumerStatefulWidget {
  const ModeratorConsoleRouteHost({super.key});

  @override
  ConsumerState<ModeratorConsoleRouteHost> createState() =>
      _ModeratorConsoleRouteHostState();
}

final class _ModeratorConsoleRouteHostState
    extends ConsumerState<ModeratorConsoleRouteHost> {
  ModeratorQueues? _queues;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final queues = await ref.read(moderationRepositoryProvider).loadQueues();
      if (mounted) setState(() => _queues = queues);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reviewReport(String reportId, String action, String reason) async {
    await ref.read(moderationRepositoryProvider).reviewReport(
      reportId: reportId,
      action: action == 'hide' ? 'hide_content' : action,
      reason: reason,
    );
  }

  Future<void> _moderateContent(
    String targetType,
    String targetId,
    String action,
    String reason,
  ) async {
    await ref.read(moderationRepositoryProvider).moderateContent(
      targetType: targetType,
      targetId: targetId,
      action: action,
      reason: reason,
    );
  }

  Future<void> _processDeletion(String requestId, String action, String reason) async {
    await ref.read(moderationRepositoryProvider).processDeletion(
      requestId: requestId,
      action: action,
      reason: reason,
    );
  }

  String _messageFor(Object error) => error is BackendException
      ? error.message
      : 'Không thể tải hoặc cập nhật hàng đợi. Hãy thử lại sau.';

  @override
  Widget build(BuildContext context) {
    final queues = _queues;
    return ModeratorConsoleScreen(
      reportQueue: queues?.reports.map((item) => ModeratorReportItem(
        reportId: item.reportId,
        targetType: item.targetType,
        targetId: item.targetId,
        reason: item.reason,
        detail: item.description,
        contentSnippet: item.content,
        reportedAt: item.createdAt,
        status: item.status,
      )).toList(growable: false),
      moderationQueue: queues?.moderation.map((item) =>
        ModeratorContentReviewItem(
          targetType: item.targetType,
          targetId: item.targetId,
          content: item.content,
          paperColor: item.paperColor,
          reviewReason: item.reasonCode,
          submittedAt: item.createdAt,
          status: item.status,
        )).toList(growable: false),
      deletionQueue: queues?.deletions.map((item) => ModeratorDeletionItem(
        requestId: item.requestId,
        opaqueAccountRef: item.opaqueAccountRef,
        requestedAt: item.requestedAt,
        status: item.status,
      )).toList(growable: false),
      isLoading: _loading,
      errorMessage: _error,
      onRefresh: _refresh,
      onBack: () => context.go('/settings'),
      onResolveReport: _reviewReport,
      onModerateContent: _moderateContent,
      onProcessDeletion: _processDeletion,
    );
  }
}
