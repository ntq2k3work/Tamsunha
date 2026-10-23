import 'model_parsing.dart';
import 'paper_color.dart';
import 'world_cell.dart';

/// Minimized public wall projection. It deliberately has no note body or author.
final class NoteTile {
  const NoteTile({
    required this.id,
    required this.cell,
    required this.paperColor,
    required this.styleSeed,
    required this.publishedAt,
  });

  final String id;
  final WorldCell cell;
  final PaperColor paperColor;
  final int styleSeed;
  final DateTime publishedAt;

  factory NoteTile.fromJson(Map<String, Object?> json) => NoteTile(
        id: ModelParsing.requiredString(json, 'id'),
        cell: WorldCell.fromJson(json),
        paperColor: PaperColor.fromJson(json['paper_color']),
        styleSeed: ModelParsing.requiredInt32(json, 'style_seed'),
        publishedAt: ModelParsing.requiredTimestamp(json, 'published_at'),
      );

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        ...cell.toJson(),
        'paper_color': paperColor.wireValue,
        'style_seed': styleSeed,
        'published_at': publishedAt.toUtc().toIso8601String(),
      };
}
