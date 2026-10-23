import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuong_nho/core/domain/world_cell.dart';
import 'package:tuong_nho/features/wall/domain/wall_geometry.dart';

void main() {
  group('WallGeometry', () {
    test('floor division keeps negative coordinates in the preceding tile', () {
      expect(floorDiv(-1, 8), -1);
      expect(floorDiv(-8, 8), -1);
      expect(floorDiv(-9, 8), -2);
      expect(floorDiv(9, 8), 1);
      expect(WallGeometry.tileCoordinate(-1), -1);
    });

    test('world positions snap to the same canonical cell around zero', () {
      expect(WallGeometry.worldToCell(x: 89.99, y: 0), const WorldCell(x: 0, y: 0));
      expect(WallGeometry.worldToCell(x: 90, y: 0), const WorldCell(x: 1, y: 0));
      expect(WallGeometry.worldToCell(x: -90, y: 0), const WorldCell(x: 0, y: 0));
      expect(WallGeometry.worldToCell(x: -90.01, y: 0), const WorldCell(x: -1, y: 0));
      expect(() => WallGeometry.worldToCell(x: double.nan, y: 0), throwsArgumentError);
    });

    test('tile coverage treats right and bottom edges as exclusive', () {
      final tileSize = WallGeometry.tileSizeWorldUnits.toDouble();
      expect(
        WallGeometry.tilesIntersecting(Rect.fromLTRB(0, 0, tileSize, tileSize)),
        <WallTileCoordinate>{const WallTileCoordinate(0, 0)},
      );
      expect(
        WallGeometry.tilesIntersecting(Rect.fromLTRB(-tileSize, 0, 0, tileSize)),
        <WallTileCoordinate>{const WallTileCoordinate(-1, 0)},
      );
    });

    test('zoom is clamped to documented interaction bounds', () {
      expect(WallGeometry.clampZoom(0.1), 0.45);
      expect(WallGeometry.clampZoom(3), 2.2);
      expect(WallGeometry.clampZoom(1.25), 1.25);
    });
  });
}
