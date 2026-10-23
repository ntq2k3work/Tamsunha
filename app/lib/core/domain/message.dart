import 'model_parsing.dart';

/// Message DTO for a conversation participant; it exposes a role, never a user ID.
final class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.isMine,
    required this.createdAt,
    this.status = 'delivered',
  });

  final String id;
  final String conversationId;
  final String body;
  final bool isMine;
  final DateTime createdAt;
  final String status;

  factory Message.fromJson(Map<String, Object?> json) => Message(
        id: ModelParsing.requiredString(json, 'id'),
        conversationId: ModelParsing.requiredString(json, 'conversation_id'),
        body: ModelParsing.requiredString(json, 'body'),
        isMine: ModelParsing.requiredBool(json, 'is_mine'),
        createdAt: ModelParsing.requiredTimestamp(json, 'created_at'),
        status: ModelParsing.optionalString(json, 'status') ?? 'delivered',
      );

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'conversation_id': conversationId,
        'body': body,
        'is_mine': isMine,
        'created_at': createdAt.toUtc().toIso8601String(),
        'status': status,
      };
}
