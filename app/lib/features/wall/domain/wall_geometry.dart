import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../core/domain/world_cell.dart';

/// Canonical world geometry shared by wall rendering, placement, and tile reads.
abstract final class WallGeometry {
  static const int cellsPerTile = 8;
  static const int tileSizeWorldUnits =
      WorldCell.sizeWorldUnits * cellsPerTile;
  static const double noteWidthWorldUnits = 118;
  static const double noteHeightWorldUnits = 145;

  /// Maps a world point to its nearest cell center. Exact half-cell ties go
  /// toward the cell with the larger coordinate, on both sides of the origin.
  static WorldCell worldToCell({required double x, required double y}) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('World coordinates must be finite.');
    }
    return WorldCell(
      x: ((x + WorldCell.sizeWorldUnits / 2) / WorldCell.sizeWorldUnits).floor(),
      y: ((y + WorldCell.sizeWorldUnits / 2) / WorldCell.sizeWorldUnits).floor(),
    );
  }

  static double cellCenter(int cellCoordinate) =>
      cellCoordinate * WorldCell.sizeWorldUnits.toDouble();

  static int tileCoordinate(int cellCoordinate) =>
      floorDiv(cellCoordinate, cellsPerTile);

  static Rect visibleWorldBounds({
    required double centerX,
    required double centerY,
    required double viewportWidth,
    required double viewportHeight,
    required double zoom,
    double tileMargin = 1,
  }) {
    if (zoom <= 0 || !zoom.isFinite) {
      throw ArgumentError.value(zoom, 'zoom', 'Must be finite and positive.');
    }
    final margin = tileSizeWorldUnits * tileMargin;
    final halfWidth = viewportWidth / zoom / 2 + margin;
    final halfHeight = viewportHeight / zoom / 2 + margin;
    return Rect.fromLTRB(
      centerX - halfWidth,
      centerY - halfHeight,
      centerX + halfWidth,
      centerY + halfHeight,
    );
  }

  /// Returns all 8x8 tiles intersecting [bounds], including negative tiles.
  static Set<WallTileCoordinate> tilesIntersecting(Rect bounds) {
    if (bounds.isEmpty) return const <WallTileCoordinate>{};
    final minX = (bounds.left / tileSizeWorldUnits).floor();
    final minY = (bounds.top / tileSizeWorldUnits).floor();
    // Rect.right/bottom are exclusive for coverage. Subtracting a tiny amount
    // avoids loading the next tile when a boundary only touches its edge.
    final maxX = ((bounds.right - 1e-6) / tileSizeWorldUnits).floor();
    final maxY = ((bounds.bottom - 1e-6) / tileSizeWorldUnits).floor();
    return <WallTileCoordinate>{
      for (var x = minX; x <= maxX; x++)
        for (var y = minY; y <= maxY; y++) WallTileCoordinate(x, y),
    };
  }

  static double clampZoom(double value, {double min = 0.45, double max = 2.2}) =>
      math.max(min, math.min(max, value)).toDouble();
}

final class WallTileCoordinate {
  const WallTileCoordinate(this.x, this.y);

  final int x;
  final int y;

  int get originCellX => x * WallGeometry.cellsPerTile;
  int get originCellY => y * WallGeometry.cellsPerTile;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallTileCoordinate && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'WallTileCoordinate($x, $y)';
}
