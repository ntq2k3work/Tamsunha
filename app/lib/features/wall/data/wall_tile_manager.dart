import 'package:flutter/painting.dart';

import '../../../core/domain/note_tile.dart';
import '../../../core/domain/world_cell.dart';
import '../domain/wall_geometry.dart';
import '../domain/wall_scene_repository.dart';
import 'wall_tile_cache.dart';

/// Loads only the tiles intersecting the viewport and keeps a bounded LRU.
final class WallTileManager {
  WallTileManager({
    required this.repository,
    int cacheCapacity = 30,
    this.maxItemsPerRead = 300,
  }) : cache = WallTileCache<WallTileCoordinate, List<NoteTile>>(
          capacity: cacheCapacity,
        );

  final WallSceneRepository repository;
  final int maxItemsPerRead;
  final WallTileCache<WallTileCoordinate, List<NoteTile>> cache;

  List<NoteTile> visibleNotes(Rect absoluteWorldBounds) {
    final center = absoluteWorldBounds.center;
    final tiles = WallGeometry.tilesIntersecting(absoluteWorldBounds).toList()
      ..sort((a, b) {
        final aX = (a.x + 0.5) * WallGeometry.tileSizeWorldUnits - center.dx;
        final aY = (a.y + 0.5) * WallGeometry.tileSizeWorldUnits - center.dy;
        final bX = (b.x + 0.5) * WallGeometry.tileSizeWorldUnits - center.dx;
        final bY = (b.y + 0.5) * WallGeometry.tileSizeWorldUnits - center.dy;
        return (aX * aX + aY * aY).compareTo(bX * bX + bY * bY);
      });
    final notes = <NoteTile>[];
    for (final coordinate in tiles) {
      final tileNotes = cache.get(coordinate) ?? _load(coordinate);
      notes.addAll(tileNotes);
      if (notes.length >= maxItemsPerRead) {
        return notes.take(maxItemsPerRead).toList(growable: false);
      }
    }
    return notes;
  }

  void invalidate(WorldCell coordinate) {
    cache.remove(WallTileCoordinate(
      WallGeometry.tileCoordinate(coordinate.x),
      WallGeometry.tileCoordinate(coordinate.y),
    ));
  }

  void clear() => cache.clear();

  List<NoteTile> _load(WallTileCoordinate coordinate) {
    final left = coordinate.x * WallGeometry.tileSizeWorldUnits.toDouble();
    final top = coordinate.y * WallGeometry.tileSizeWorldUnits.toDouble();
    final bounds = Rect.fromLTWH(
      left,
      top,
      WallGeometry.tileSizeWorldUnits.toDouble(),
      WallGeometry.tileSizeWorldUnits.toDouble(),
    );
    final value = repository.tilesIn(bounds, maxItems: maxItemsPerRead).toList();
    cache.put(coordinate, value);
    return value;
  }
}
