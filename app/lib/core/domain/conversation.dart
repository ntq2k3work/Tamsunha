import 'model_parsing.dart';

/// Safe result/state returned when opening a conversation from a note.
///
/// The API intentionally contains no participant IDs. Outbound allowance is
/// supplied by the server; the client never derives the pair-wide message cap.
final class Conversation {
  Conversation({
    required this.id,
    required this.created,
    required this.canSend,
    required this.remainingOutbound,
    this.status = 'active',
  }) {
    if (remainingOutbound < 0 || remainingOutbound > 3) {
      throw ArgumentError.value(
        remainingOutbound,
        'remainingOutbound',
        'Must be between 0 and 3.',
      );
    }
    if (canSend && remainingOutbound == 0) {
      throw ArgumentError('canSend cannot be true when remainingOutbound is 0.');
    }
  }

  final String id;
  final bool created;
  final bool canSend;
  final int remainingOutbound;
  final String status;

  bool get isClosed => status != 'active';

  factory Conversation.fromJson(Map<String, Object?> json) {
    final remainingOutbound =
        ModelParsing.requiredInt(json, 'remaining_outbound');
    if (remainingOutbound < 0 || remainingOutbound > 3) {
      throw const FormatException('remaining_outbound must be between 0 and 3.');
    }

    return Conversation(
      id: ModelParsing.requiredString(json, 'conversation_id'),
      created: ModelParsing.requiredBool(json, 'created'),
      canSend: ModelParsing.requiredBool(json, 'can_send'),
      remainingOutbound: remainingOutbound,
      status: ModelParsing.optionalString(json, 'status') ?? 'active',
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'conversation_id': id,
        'created': created,
        'can_send': canSend,
        'remaining_outbound': remainingOutbound,
        'status': status,
      };
}
