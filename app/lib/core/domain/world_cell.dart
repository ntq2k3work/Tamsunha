/// A note's stable position in the shared world.
///
/// These coordinates are signed integer cells. They are not pixels, viewport
/// offsets, or per-user positions.
final class WorldCell {
  const WorldCell({required this.x, required this.y});

  static const int sizeWorldUnits = 180;

  final int x;
  final int y;

  // The product spec defines each cell's center at (cell_x * 180, cell_y * 180).
  double get centerWorldX => x * sizeWorldUnits.toDouble();
  double get centerWorldY => y * sizeWorldUnits.toDouble();

  factory WorldCell.fromJson(Map<String, Object?> json) {
    final x = json['cell_x'];
    final y = json['cell_y'];
    if (x is! int || y is! int) {
      throw const FormatException('cell_x and cell_y must be integers.');
    }
    return WorldCell(x: x, y: y);
  }

  Map<String, Object> toJson() => <String, Object>{
        'cell_x': x,
        'cell_y': y,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorldCell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'WorldCell(x: $x, y: $y)';
}

/// Integer floor division for positive divisors.
///
/// Dart's `~/` truncates toward zero. The wall uses floor division so a cell
/// at -1 belongs to tile -1, not tile 0.
int floorDiv(int dividend, int divisor) {
  if (divisor <= 0) {
    throw ArgumentError.value(divisor, 'divisor', 'Must be positive.');
  }

  final quotient = dividend ~/ divisor;
  final remainder = dividend.remainder(divisor);
  return remainder < 0 ? quotient - 1 : quotient;
}
