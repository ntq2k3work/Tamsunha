import '../../../core/domain/paper_color.dart';

final class ModerationRecord {
  const ModerationRecord({
    required this.queueId,
    required this.targetType,
    required this.targetId,
    required this.content,
    required this.reasonCode,
    required this.status,
    required this.createdAt,
    required this.paperColor,
  });

  final String queueId;
  final String targetType;
  final String targetId;
  final String content;
  final String reasonCode;
  final String status;
  final DateTime createdAt;
  final PaperColor? paperColor;

  bool get isNote => targetType == 'note';
}

final class ReportQueueRecord {
  const ReportQueueRecord({
    required this.reportId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.description,
    this.content,
  });

  final String reportId;
  final String targetType;
  final String targetId;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String? description;
  final String? content;
}

final class DeletionQueueRecord {
  const DeletionQueueRecord({
    required this.requestId,
    required this.status,
    required this.requestedAt,
    this.resolutionCode,
  });

  final String requestId;
  final String status;
  final DateTime requestedAt;
  final String? resolutionCode;

  String get opaqueAccountRef => requestId.substring(0, 8).toUpperCase();
}

final class ModeratorQueues {
  const ModeratorQueues({
    required this.moderation,
    required this.reports,
    required this.deletions,
  });

  final List<ModerationRecord> moderation;
  final List<ReportQueueRecord> reports;
  final List<DeletionQueueRecord> deletions;
}

abstract interface class ModerationRepository {
  Future<ModeratorQueues> loadQueues({int limit = 50});

  Future<void> moderateNote({
    required String noteId,
    required String action,
    required String reason,
  });

  Future<void> moderateMessage({
    required String messageId,
    required String action,
    required String reason,
  });

  Future<void> moderateContent({
    required String targetType,
    required String targetId,
    required String action,
    required String reason,
  });

  Future<void> reviewReport({
    required String reportId,
    required String action,
    required String reason,
  });

  Future<void> processDeletion({
    required String requestId,
    required String action,
    required String reason,
  });
}
