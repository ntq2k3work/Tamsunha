abstract interface class SafetyRepository {
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? description,
  });

  Future<void> reportUserFromNote({
    required String noteId,
    required String reason,
    String? description,
  });

  Future<void> reportAndBlockUserFromNote({
    required String noteId,
    required String reason,
    String? description,
  });

  Future<void> reportUserFromConversation({
    required String conversationId,
    required String reason,
    String? description,
  });

  Future<void> reportAndBlockUserFromConversation({
    required String conversationId,
    required String reason,
    String? description,
  });

  Future<void> reportAndBlockNote({
    required String noteId,
    required String reason,
    String? description,
  });

  Future<void> reportAndBlockConversation({
    required String conversationId,
    required String reason,
    String? description,
  });

  Future<void> reportAndBlockMessage({
    required String messageId,
    required String reason,
    String? description,
  });

  Future<void> blockFromNote(String noteId);
  Future<void> blockFromConversation(String conversationId);
  Future<List<OwnBlockRecord>> getMyBlocks();
  Future<bool> unblock(String blockRef);
}

final class OwnBlockRecord {
  const OwnBlockRecord({required this.blockRef, required this.createdAt});

  final String blockRef;
  final DateTime createdAt;
}
