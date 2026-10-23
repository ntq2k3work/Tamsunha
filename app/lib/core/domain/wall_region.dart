import 'world_cell.dart';

/// One 8×8 tile region in the shared wall.
final class WallRegion {
  static const int cellsPerSide = 8;
  static const int cellCount = cellsPerSide * cellsPerSide;

  WallRegion({
    required this.tileX,
    required this.tileY,
    this.availableCellsEstimate,
  }) {
    if (availableCellsEstimate != null &&
        (availableCellsEstimate! < 0 || availableCellsEstimate! > cellCount)) {
      throw ArgumentError.value(
        availableCellsEstimate,
        'availableCellsEstimate',
        'Must be between 0 and $cellCount.',
      );
    }
  }

  final int tileX;
  final int tileY;

  /// An advisory server estimate; final placement is always server-validated.
  final int? availableCellsEstimate;

  factory WallRegion.containing(WorldCell cell) => WallRegion(
        tileX: floorDiv(cell.x, cellsPerSide),
        tileY: floorDiv(cell.y, cellsPerSide),
      );

  factory WallRegion.fromJson(Map<String, Object?> json) {
    final tileX = json['tile_x'];
    final tileY = json['tile_y'];
    final freeEstimate = json['available_cells_estimate'];
    if (tileX is! int || tileY is! int) {
      throw const FormatException('tile_x and tile_y must be integers.');
    }
    if (freeEstimate != null && freeEstimate is! int) {
      throw const FormatException('available_cells_estimate must be an integer.');
    }

    if (freeEstimate is int && (freeEstimate < 0 || freeEstimate > cellCount)) {
      throw const FormatException(
        'available_cells_estimate must be between 0 and 64.',
      );
    }

    return WallRegion(
      tileX: tileX,
      tileY: tileY,
      availableCellsEstimate: freeEstimate as int?,
    );
  }

  bool contains(WorldCell cell) =>
      floorDiv(cell.x, cellsPerSide) == tileX &&
      floorDiv(cell.y, cellsPerSide) == tileY;

  Map<String, Object> toJson() => <String, Object>{
        'tile_x': tileX,
        'tile_y': tileY,
        if (availableCellsEstimate != null)
          'available_cells_estimate': availableCellsEstimate!,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallRegion &&
          other.tileX == tileX &&
          other.tileY == tileY &&
          other.availableCellsEstimate == availableCellsEstimate;

  @override
  int get hashCode => Object.hash(tileX, tileY, availableCellsEstimate);

  @override
  String toString() => 'WallRegion(tileX: $tileX, tileY: $tileY)';
}
