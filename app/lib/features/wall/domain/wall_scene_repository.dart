import 'package:flutter/painting.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/note_tile.dart';
import '../../../core/domain/world_cell.dart';

/// Synchronous, in-memory view used by Flame while async repositories fetch tiles.
abstract interface class WallSceneRepository {
  Iterable<NoteTile> tilesIn(Rect bounds, {int maxItems = 300});
  NoteDetail? detailFor(String id);
  NoteTile? noteAt(WorldCell cell);
}
