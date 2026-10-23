import '../../../core/domain/note_tile.dart';
import '../../../core/domain/note_detail.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/domain/placement_result.dart';
import '../../../core/domain/world_cell.dart';

final class WallTileCursor {
  const WallTileCursor({
    required this.cellX,
    required this.cellY,
    required this.id,
  });

  final int cellX;
  final int cellY;
  final String id;
}

final class WallTilePage {
  const WallTilePage({
    required this.items,
    required this.revision,
    this.nextCursor,
  });

  final List<NoteTile> items;
  final int revision;
  final WallTileCursor? nextCursor;
}

final class DiscoveryTarget {
  const DiscoveryTarget({
    required this.tileX,
    required this.tileY,
    required this.cameraWorldX,
    required this.cameraWorldY,
    required this.availableCellsEstimate,
  });

  final int tileX;
  final int tileY;
  final int cameraWorldX;
  final int cameraWorldY;
  final int availableCellsEstimate;
}

final class MyNoteSummary {
  const MyNoteSummary({
    required this.id,
    required this.content,
    required this.paperColor,
    required this.status,
    required this.cell,
    required this.createdAt,
    required this.allowChat,
    required this.canEdit,
    required this.canDelete,
  });

  final String id;
  final String content;
  final PaperColor paperColor;
  final String status;
  final WorldCell cell;
  final DateTime createdAt;
  final bool allowChat;
  final bool canEdit;
  final bool canDelete;
}

final class MyNotesPage {
  const MyNotesPage({
    required this.items,
    required this.dailyQuotaUsed,
    this.nextCursorCreatedAt,
    this.nextCursorId,
  });

  final List<MyNoteSummary> items;
  final bool dailyQuotaUsed;
  final DateTime? nextCursorCreatedAt;
  final String? nextCursorId;

  bool get hasMore => nextCursorCreatedAt != null && nextCursorId != null;
}

final class NoteEditResult {
  const NoteEditResult({
    required this.id,
    required this.status,
    required this.content,
    required this.contentVersion,
  });

  final String id;
  final String status;
  final String content;
  final int contentVersion;
}

abstract interface class WallRepository {
  Future<NoteDetail> getNoteDetail(String noteId);

  Future<WallTilePage> getWallTiles({
    required int minCellX,
    required int maxCellX,
    required int minCellY,
    required int maxCellY,
    WallTileCursor? cursor,
    int limit = 200,
  });

  Future<DiscoveryTarget> getDiscoveryTarget({
    List<({int tileX, int tileY})> excludeRegions = const [],
  });

  Future<PlacementResult> placeNote({
    required String content,
    required PaperColor paperColor,
    required bool allowChat,
    required WorldCell cell,
    required String clientRequestId,
  });

  Future<NoteEditResult> editNote({
    required String noteId,
    required String newContent,
    required String clientRequestId,
  });

  Future<MyNotesPage> getMyNotes({
    DateTime? cursorCreatedAt,
    String? cursorId,
    int limit = 20,
  });

  Future<void> deleteNote(String noteId, {required String clientRequestId});
  Future<void> updateNoteChat(String noteId, {required bool allowChat});
}
