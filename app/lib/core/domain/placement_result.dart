import 'model_parsing.dart';
import 'world_cell.dart';

enum PlacementStatus {
  published('published'),
  pendingReview('pending_review');

  const PlacementStatus(this.wireValue);

  final String wireValue;

  static PlacementStatus fromJson(Object? value) {
    if (value is String) {
      for (final status in PlacementStatus.values) {
        if (status.wireValue == value) return status;
      }
    }
    throw FormatException('Unsupported placement status: $value.');
  }
}

/// Canonical result of a successful, idempotent place_note request.
final class PlacementResult {
  const PlacementResult({
    required this.noteId,
    required this.status,
    required this.cell,
    this.publishedAt,
  });

  final String noteId;
  final PlacementStatus status;
  final WorldCell cell;
  final DateTime? publishedAt;

  factory PlacementResult.fromJson(Map<String, Object?> json) {
    final status = PlacementStatus.fromJson(json['status']);
    final publishedAt = ModelParsing.optionalTimestamp(json, 'published_at');

    return PlacementResult(
      noteId: ModelParsing.requiredString(json, 'note_id'),
      status: status,
      cell: WorldCell.fromJson(json),
      publishedAt: publishedAt,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'note_id': noteId,
        'status': status.wireValue,
        ...cell.toJson(),
        if (publishedAt != null)
          'published_at': publishedAt!.toUtc().toIso8601String(),
      };
}
