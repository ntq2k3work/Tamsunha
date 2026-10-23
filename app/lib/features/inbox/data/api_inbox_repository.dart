import '../../../core/network/api_client.dart';

import '../../../core/domain/conversation.dart';
import '../../../core/domain/message.dart';
import '../../../core/domain/model_parsing.dart';
import '../../../core/errors/backend_exception.dart';
import '../domain/inbox_repository.dart';

final class ApiInboxRepository implements InboxRepository {
  const ApiInboxRepository(this._client);

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
  Future<InboxPage<EncouragementRecord>> getEncouragements({
    InboxCursor? cursor,
    int limit = 20,
  }) async {
    final data = await _rpc('get_inbox', params: _inboxParams('encouragements', cursor, limit));
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    return InboxPage<EncouragementRecord>(
      items: rawItems.map((item) {
        final json = _asObjectMap(item);
        return EncouragementRecord(
          id: ModelParsing.requiredString(json, 'id'),
          noteId: ModelParsing.requiredString(json, 'note_id'),
          templateKey: ModelParsing.requiredString(json, 'template_key'),
          receivedAt: ModelParsing.requiredTimestamp(json, 'created_at'),
          cellX: ModelParsing.requiredInt(json, 'cell_x'),
          cellY: ModelParsing.requiredInt(json, 'cell_y'),
          isRead: ModelParsing.requiredBool(json, 'is_read'),
          notificationId: ModelParsing.optionalString(json, 'notification_id'),
        );
      }).toList(growable: false),
      nextCursor: _parseCursor(data['next_cursor']),
    );
  }

  @override
  Future<InboxPage<ConversationRecord>> getConversations({
    InboxCursor? cursor,
    int limit = 20,
  }) async {
    final data = await _rpc('get_inbox', params: _inboxParams('chats', cursor, limit));
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    return InboxPage<ConversationRecord>(
      items: rawItems.map((item) {
        final json = _asObjectMap(item);
        final remaining = ModelParsing.requiredInt(json, 'remaining_outbound');
        if (remaining < 0 || remaining > 3) {
          throw const FormatException('remaining_outbound must be between 0 and 3.');
        }
        final unread = ModelParsing.requiredInt(json, 'unread_count');
        if (unread < 0) throw const FormatException('unread_count cannot be negative.');
        return ConversationRecord(
          conversationId: ModelParsing.requiredString(json, 'conversation_id'),
          lastMessageAt: ModelParsing.requiredTimestamp(json, 'last_message_at'),
          lastMessageIsMine: ModelParsing.requiredBool(json, 'last_message_is_mine'),
          remainingOutbound: remaining,
          lastMessagePreview: ModelParsing.requiredString(json, 'last_message_preview'),
          unreadCount: unread,
        );
      }).toList(growable: false),
      nextCursor: _parseCursor(data['next_cursor']),
    );
  }

  @override
  Future<MessagePage> getMessages(
    String conversationId, {
    InboxCursor? before,
    int limit = 30,
  }) async {
    final data = await _rpc('get_messages', params: <String, Object?>{
      'p_conversation_id': conversationId,
      'p_before_created_at': before?.createdAt.toUtc().toIso8601String(),
      'p_before_id': before?.id,
      'p_limit': limit,
    });
    final rawItems = data['items'];
    if (rawItems is! List) throw BackendException.unavailable();
    final remaining = ModelParsing.requiredInt(data, 'remaining_outbound');
    final status = ModelParsing.requiredString(data, 'status');
    final canSend = ModelParsing.requiredBool(data, 'can_send');
    final rawSourceNote = data['source_note_content'];
    if (rawSourceNote != null && rawSourceNote is! String) {
      throw BackendException.unavailable();
    }
    return MessagePage(
      conversation: Conversation(
        id: conversationId,
        created: false,
        canSend: canSend,
        remainingOutbound: remaining,
        status: status,
      ),
      items: rawItems.map((item) => Message.fromJson(_asObjectMap(item))).toList(growable: false),
      sourceNoteContent: rawSourceNote as String?,
      nextCursor: _parseCursor(data['next_cursor']),
    );
  }

  @override
  Future<Conversation> startConversationFromNote(
    String noteId, {
    required String clientRequestId,
  }) async {
    final data = await _rpc('start_conversation_from_note', params: <String, Object?>{
      'p_note_id': noteId,
      'p_client_request_id': clientRequestId,
    });
    return Conversation.fromJson(data);
  }

  @override
  Future<MessageSendResult> sendMessage({
    required String conversationId,
    required String body,
    required String clientRequestId,
  }) async {
    final data = await _rpc('send_message', params: <String, Object?>{
      'p_conversation_id': conversationId,
      'p_body': body,
      'p_client_request_id': clientRequestId,
    });
    return MessageSendResult(
      messageId: ModelParsing.requiredString(data, 'message_id'),
      createdAt: ModelParsing.requiredTimestamp(data, 'created_at'),
      remainingOutbound: ModelParsing.requiredInt(data, 'remaining_outbound'),
      status: ModelParsing.requiredString(data, 'status'),
    );
  }

  @override
  Future<void> sendEncouragement({
    required String noteId,
    required String templateKey,
    required String clientRequestId,
  }) async {
    await _rpc('send_encouragement', params: <String, Object?>{
      'p_note_id': noteId,
      'p_template_key': templateKey,
      'p_client_request_id': clientRequestId,
    });
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    await _rpc('mark_notification_read', params: <String, Object?>{
      'p_notification_id': notificationId,
    });
  }

  @override
  Future<void> closeConversation(String conversationId) async {
    await _rpc('close_conversation', params: <String, Object?>{
      'p_conversation_id': conversationId,
    });
  }

  Map<String, Object?> _inboxParams(String kind, InboxCursor? cursor, int limit) =>
      <String, Object?>{
        'p_kind': kind,
        'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'p_cursor_id': cursor?.id,
        'p_limit': limit,
      };

  InboxCursor? _parseCursor(Object? value) {
    if (value == null) return null;
    final json = _asObjectMap(value);
    return InboxCursor(
      createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
      id: ModelParsing.requiredString(json, 'id'),
    );
  }

  Map<String, Object?> _asObjectMap(Object? value) {
    if (value is! Map) throw BackendException.unavailable();
    return Map<String, Object?>.from(value);
  }
}
