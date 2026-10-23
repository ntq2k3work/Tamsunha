import '../../../core/network/api_client.dart';

import '../../../core/domain/model_parsing.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/errors/backend_exception.dart';
import '../domain/moderation_repository.dart';

final class ApiModerationRepository implements ModerationRepository {
  const ApiModerationRepository(this._client);

  final ApiClient? _client;

  ApiClient _requireClient() {
    final client = _client;
    if (client == null) throw BackendException.notConfigured();
    if (!client.session.hasSession) {
      throw const BackendException(
        code: 'UNAUTHENTICATED',
        message: 'Hãy đăng nhập để tiếp tục.',
      );
    }
    return client;
  }

  Future<Map<String, Object?>> _rpc(
    String name, {
    Map<String, Object?>? params,
  }) async {
    try {
      return await _requireClient().rpc(name, params: params);
    } on BackendException {
      rethrow;
    } catch (_) {
      throw BackendException.unavailable();
    }
  }

  @override
  Future<ModeratorQueues> loadQueues({int limit = 50}) async {
    final results = await Future.wait<Map<String, Object?>>(<Future<Map<String, Object?>>>[
      _rpc('get_moderation_queue', params: <String, Object?>{'p_limit': limit}),
      _rpc('get_reports_queue', params: <String, Object?>{'p_limit': limit}),
      _rpc('get_deletion_queue', params: <String, Object?>{'p_limit': limit}),
    ]);
    return ModeratorQueues(
      moderation: _list(results[0], 'items').map((item) {
        final json = item;
        final targetType = ModelParsing.requiredString(json, 'target_type');
        return ModerationRecord(
          queueId: ModelParsing.requiredString(json, 'id'),
          targetType: targetType,
          targetId: ModelParsing.requiredString(json, 'target_id'),
          content: ModelParsing.requiredString(json, 'content'),
          reasonCode: ModelParsing.requiredString(json, 'reason_code'),
          status: ModelParsing.requiredString(json, 'status'),
          createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
          paperColor: targetType == 'note'
              ? PaperColor.fromJson(json['paper_color'])
              : null,
        );
      }).toList(growable: false),
      reports: _list(results[1], 'items').map((json) => ReportQueueRecord(
        reportId: ModelParsing.requiredString(json, 'report_id'),
        targetType: ModelParsing.requiredString(json, 'target_type'),
        // User reports are resolved by report ID on the server; never expose
        // the reported user's UUID to the moderator UI.
        targetId: ModelParsing.optionalString(json, 'target_id') ?? '',
        reason: ModelParsing.requiredString(json, 'reason'),
        status: ModelParsing.requiredString(json, 'status'),
        createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
        description: ModelParsing.optionalString(json, 'description'),
        content: ModelParsing.optionalString(json, 'content'),
      )).toList(growable: false),
      deletions: _list(results[2], 'items').map((json) => DeletionQueueRecord(
        requestId: ModelParsing.requiredString(json, 'request_id'),
        status: ModelParsing.requiredString(json, 'status'),
        requestedAt: ModelParsing.requiredTimestamp(json, 'requested_at'),
        resolutionCode: ModelParsing.optionalString(json, 'resolution_code'),
      )).toList(growable: false),
    );
  }

  @override
  Future<void> moderateNote({
    required String noteId,
    required String action,
    required String reason,
  }) async {
    await _rpc('moderate_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_action': action,
      'p_reason': reason,
    });
  }

  @override
  Future<void> moderateMessage({
    required String messageId,
    required String action,
    required String reason,
  }) async {
    await _rpc('moderate_message', params: <String, Object?>{
      'p_message_id': messageId,
      'p_action': action,
      'p_reason': reason,
    });
  }

  @override
  Future<void> moderateContent({
    required String targetType,
    required String targetId,
    required String action,
    required String reason,
  }) async {
    if (targetType == 'note') {
      await moderateNote(
        noteId: targetId,
        action: action == 'approve' ? 'publish' : action,
        reason: reason,
      );
    } else if (targetType == 'message') {
      await moderateMessage(
        messageId: targetId,
        action: action,
        reason: reason,
      );
    } else {
      throw const BackendException(
        code: 'INVALID_INPUT',
        message: 'Loại nội dung không hỗ trợ kiểm duyệt.',
      );
    }
  }

  @override
  Future<void> reviewReport({
    required String reportId,
    required String action,
    required String reason,
  }) async {
    await _rpc('review_report', params: <String, Object?>{
      'p_report_id': reportId,
      'p_action': action,
      'p_reason': reason,
    });
  }

  @override
  Future<void> processDeletion({
    required String requestId,
    required String action,
    required String reason,
  }) async {
    await _rpc('process_deletion_request', params: <String, Object?>{
      'p_request_id': requestId,
      'p_action': action,
      'p_reason': reason,
    });
  }

  List<Map<String, Object?>> _list(Map<String, Object?> data, String key) {
    final rawItems = data[key];
    if (rawItems is! List) throw BackendException.unavailable();
    return rawItems.map(_asObjectMap).toList(growable: false);
  }

  Map<String, Object?> _asObjectMap(Object? value) {
    if (value is! Map) throw BackendException.unavailable();
    return Map<String, Object?>.from(value);
  }
}
