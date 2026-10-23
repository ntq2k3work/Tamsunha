import 'model_parsing.dart';
import 'paper_color.dart';

/// Full note projection returned only after a permitted detail request.
/// The public author identity is never part of this model.
final class NoteDetail {
  const NoteDetail({
    required this.id,
    required this.content,
    required this.paperColor,
    required this.publishedAt,
    this.status = 'published',
    required this.canEncourage,
    this.alreadyEncouraged = false,
    required this.canStartChat,
    required this.isOwner,
    required this.allowChat,
    required this.canEdit,
    required this.canDelete,
  });

  final String id;
  final String content;
  final PaperColor paperColor;
  final DateTime? publishedAt;
  final String status;
  final bool canEncourage;
  final bool alreadyEncouraged;
  final bool canStartChat;
  final bool isOwner;
  final bool allowChat;
  final bool canEdit;
  final bool canDelete;

  factory NoteDetail.fromJson(Map<String, Object?> json) => NoteDetail(
        id: ModelParsing.requiredString(json, 'id'),
        content: ModelParsing.requiredString(json, 'content'),
        paperColor: PaperColor.fromJson(json['paper_color']),
        publishedAt: ModelParsing.optionalTimestamp(json, 'published_at'),
        status: ModelParsing.optionalString(json, 'status') ?? 'published',
        canEncourage: ModelParsing.requiredBool(json, 'can_encourage'),
        alreadyEncouraged:
            ModelParsing.requiredBool(json, 'already_encouraged'),
        canStartChat: ModelParsing.requiredBool(json, 'can_start_chat'),
        isOwner: ModelParsing.requiredBool(json, 'is_owner'),
        allowChat: ModelParsing.requiredBool(json, 'allow_chat'),
        canEdit: ModelParsing.requiredBool(json, 'can_edit'),
        canDelete: ModelParsing.requiredBool(json, 'can_delete'),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'content': content,
        'paper_color': paperColor.wireValue,
        'published_at': publishedAt?.toUtc().toIso8601String(),
        'status': status,
        'can_encourage': canEncourage,
        'already_encouraged': alreadyEncouraged,
        'can_start_chat': canStartChat,
        'is_owner': isOwner,
        'allow_chat': allowChat,
        'can_edit': canEdit,
        'can_delete': canDelete,
      };
}
