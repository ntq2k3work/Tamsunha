import '../../../core/domain/conversation.dart';
import '../../../core/domain/message.dart';

enum InboxKind { encouragements, chats }

final class InboxCursor {
  const InboxCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

final class InboxPage<T> {
  const InboxPage({required this.items, this.nextCursor});

  final List<T> items;
  final InboxCursor? nextCursor;
}

final class EncouragementRecord {
  const EncouragementRecord({
    required this.id,
    required this.noteId,
    required this.templateKey,
    required this.receivedAt,
    required this.cellX,
    required this.cellY,
    required this.isRead,
    this.notificationId,
  });

  final String id;
  final String noteId;
  final String templateKey;
  final DateTime receivedAt;
  final int cellX;
  final int cellY;
  final bool isRead;
  final String? notificationId;
}

final class ConversationRecord {
  const ConversationRecord({
    required this.conversationId,
    required this.lastMessageAt,
    required this.lastMessageIsMine,
    required this.remainingOutbound,
    required this.lastMessagePreview,
    required this.unreadCount,
  });

  final String conversationId;
  final DateTime lastMessageAt;
  final bool lastMessageIsMine;
  final int remainingOutbound;
  final String lastMessagePreview;
  final int unreadCount;
}

final class MessagePage {
  const MessagePage({
    required this.conversation,
    required this.items,
    this.sourceNoteContent,
    this.nextCursor,
  });

  final Conversation conversation;
  final List<Message> items;
  final String? sourceNoteContent;
  final InboxCursor? nextCursor;
}

final class MessageSendResult {
  const MessageSendResult({
    required this.messageId,
    required this.createdAt,
    required this.remainingOutbound,
    required this.status,
  });

  final String messageId;
  final DateTime createdAt;
  final int remainingOutbound;
  final String status;
}

abstract interface class InboxRepository {
  Future<InboxPage<EncouragementRecord>> getEncouragements({
    InboxCursor? cursor,
    int limit = 20,
  });

  Future<InboxPage<ConversationRecord>> getConversations({
    InboxCursor? cursor,
    int limit = 20,
  });

  Future<MessagePage> getMessages(
    String conversationId, {
    InboxCursor? before,
    int limit = 30,
  });

  Future<Conversation> startConversationFromNote(
    String noteId, {
    required String clientRequestId,
  });

  Future<MessageSendResult> sendMessage({
    required String conversationId,
    required String body,
    required String clientRequestId,
  });

  Future<void> sendEncouragement({
    required String noteId,
    required String templateKey,
    required String clientRequestId,
  });

  Future<void> markNotificationRead(String notificationId);
  Future<void> closeConversation(String conversationId);
}
