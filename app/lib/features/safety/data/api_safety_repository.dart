import '../../../core/network/api_client.dart';

import '../../../core/domain/model_parsing.dart';
import '../../../core/errors/backend_exception.dart';
import '../domain/safety_repository.dart';

final class ApiSafetyRepository implements SafetyRepository {
  const ApiSafetyRepository(this._client);

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
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_content', params: <String, Object?>{
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportUserFromNote({
    required String noteId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_user_from_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportAndBlockUserFromNote({
    required String noteId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_and_block_user_from_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportUserFromConversation({
    required String conversationId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_user_from_conversation', params: <String, Object?>{
      'p_conversation_id': conversationId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportAndBlockUserFromConversation({
    required String conversationId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_and_block_user_from_conversation', params: <String, Object?>{
      'p_conversation_id': conversationId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportAndBlockNote({
    required String noteId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_and_block_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportAndBlockConversation({
    required String conversationId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_and_block_conversation', params: <String, Object?>{
      'p_conversation_id': conversationId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> reportAndBlockMessage({
    required String messageId,
    required String reason,
    String? description,
  }) async {
    await _rpc('report_and_block_message', params: <String, Object?>{
      'p_message_id': messageId,
      'p_reason': reason,
      'p_description': description,
    });
  }

  @override
  Future<void> blockFromNote(String noteId) async {
    await _rpc('block_from_note', params: <String, Object?>{'p_note_id': noteId});
  }

  @override
  Future<void> blockFromConversation(String conversationId) async {
    await _rpc('block_from_conversation', params: <String, Object?>{
      'p_conversation_id': conversationId,
    });
  }

  @override
  Future<List<OwnBlockRecord>> getMyBlocks() async {
    final data = await _rpc('get_my_blocks');
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    return rawItems.map((item) {
      if (item is! Map) throw BackendException.unavailable();
      final json = Map<String, Object?>.from(item);
      return OwnBlockRecord(
        blockRef: ModelParsing.requiredString(json, 'block_ref'),
        createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
      );
    }).toList(growable: false);
  }

  @override
  Future<bool> unblock(String blockRef) async {
    final data = await _rpc('unblock_from_my_list', params: <String, Object?>{
      'p_block_ref': blockRef,
    });
    return ModelParsing.requiredBool(data, 'unblocked');
  }
}
