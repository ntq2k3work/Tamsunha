import 'package:flutter/painting.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/note_tile.dart';
import '../../../core/domain/world_cell.dart';
import '../domain/wall_geometry.dart';
import '../domain/wall_scene_repository.dart';
import 'wall_tile_cache.dart';

/// Bounded in-memory cache of server-approved tiles used by the Flame scene.
final class RemoteWallSceneCache implements WallSceneRepository {
  RemoteWallSceneCache({int capacity = 30})
      : _tiles = WallTileCache<WallTileCoordinate, List<NoteTile>>(
          capacity: capacity,
        );

  final WallTileCache<WallTileCoordinate, List<NoteTile>> _tiles;

  List<NoteTile>? notesForTile(WallTileCoordinate coordinate) => _tiles.get(coordinate);

  void putTile(WallTileCoordinate coordinate, List<NoteTile> notes) {
    _tiles.put(coordinate, List<NoteTile>.unmodifiable(notes));
  }

  void invalidate(WallTileCoordinate coordinate) => _tiles.remove(coordinate);

  void clear() => _tiles.clear();

  @override
  Iterable<NoteTile> tilesIn(Rect bounds, {int maxItems = 300}) sync* {
    if (maxItems < 1) return;
    final coordinates = WallGeometry.tilesIntersecting(bounds).toList()
      ..sort((a, b) {
        final aX = (a.x + 0.5) * WallGeometry.tileSizeWorldUnits - bounds.center.dx;
        final aY = (a.y + 0.5) * WallGeometry.tileSizeWorldUnits - bounds.center.dy;
        final bX = (b.x + 0.5) * WallGeometry.tileSizeWorldUnits - bounds.center.dx;
        final bY = (b.y + 0.5) * WallGeometry.tileSizeWorldUnits - bounds.center.dy;
        return (aX * aX + aY * aY).compareTo(bX * bX + bY * bY);
      });
    var returned = 0;
    for (final coordinate in coordinates) {
      for (final note in _tiles.get(coordinate) ?? const <NoteTile>[]) {
        final center = Offset(
          WallGeometry.cellCenter(note.cell.x),
          WallGeometry.cellCenter(note.cell.y),
        );
        if (!bounds.contains(center)) continue;
        if (returned >= maxItems) return;
        returned++;
        yield note;
      }
    }
  }

  @override
  NoteDetail? detailFor(String id) => null;

  @override
  NoteTile? noteAt(WorldCell cell) {
    final coordinate = WallTileCoordinate(
      WallGeometry.tileCoordinate(cell.x),
      WallGeometry.tileCoordinate(cell.y),
    );
    for (final note in _tiles.get(coordinate) ?? const <NoteTile>[]) {
      if (note.cell == cell) return note;
    }
    return null;
  }
}
