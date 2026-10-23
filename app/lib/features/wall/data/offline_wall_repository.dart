import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/note_tile.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/domain/world_cell.dart';
import '../domain/wall_geometry.dart';
import '../domain/wall_scene_repository.dart';

/// In-memory M1 fixture. It intentionally never writes to a backend or disk.
final class OfflineWallRepository implements WallSceneRepository {
  OfflineWallRepository({int fixtureSize = 10000})
      : _tilesByTile = <WallTileCoordinate, List<NoteTile>>{},
        _tilesById = <String, NoteTile>{} {
    if (fixtureSize < 0) {
      throw ArgumentError.value(fixtureSize, 'fixtureSize');
    }
    if (fixtureSize > 1000000) {
      throw ArgumentError.value(fixtureSize, 'fixtureSize', 'Must be at most 1,000,000.');
    }
    _seedFixture(fixtureSize);
    _nextId = fixtureSize + 1;
  }

  final Map<WallTileCoordinate, List<NoteTile>> _tilesByTile;
  final Map<String, NoteTile> _tilesById;
  final Map<String, NoteDetail> _localDetails = <String, NoteDetail>{};
  int _nextId = 10001;
  int _discoveryIndex = 0;

  int get noteCount => _tilesByTile.values.fold<int>(0, (sum, items) => sum + items.length);

  Iterable<NoteTile> tilesIn(Rect bounds, {int maxItems = 300}) sync* {
    if (maxItems < 1) return;
    final tileCoords = WallGeometry.tilesIntersecting(bounds).toList()
      ..sort((a, b) {
        final aDistance = a.x * a.x + a.y * a.y;
        final bDistance = b.x * b.x + b.y * b.y;
        return aDistance.compareTo(bDistance);
      });
    var returned = 0;
    for (final coordinate in tileCoords) {
      for (final tile in _tilesByTile[coordinate] ?? const <NoteTile>[]) {
        if (returned >= maxItems) return;
        final x = WallGeometry.cellCenter(tile.cell.x);
        final y = WallGeometry.cellCenter(tile.cell.y);
        if (bounds.contains(Offset(x, y))) {
          returned++;
          yield tile;
        }
      }
    }
  }

  NoteDetail? detailFor(String id) {
    final local = _localDetails[id];
    if (local != null) return local;
    final tile = _findById(id);
    if (tile == null) return null;
    return _fixtureDetail(tile);
  }

  NoteTile? noteAt(WorldCell cell) {
    final coordinate = WallTileCoordinate(
      WallGeometry.tileCoordinate(cell.x),
      WallGeometry.tileCoordinate(cell.y),
    );
    for (final note in _tilesByTile[coordinate] ?? const <NoteTile>[]) {
      if (note.cell == cell) return note;
    }
    return null;
  }

  WorldCell discoveryTarget() {
    final distantNotes = _tilesById.values
        .where((note) => note.cell.x.abs() > 8 || note.cell.y.abs() > 8)
        .toList(growable: false);
    if (distantNotes.isEmpty) return const WorldCell(x: 0, y: 0);
    final target = distantNotes[_discoveryIndex % distantNotes.length].cell;
    _discoveryIndex++;
    return target;
  }

  /// Adds a demo-only note if the cell is free. No remote success is implied.
  NoteTile? placeLocally({
    required WorldCell cell,
    required String content,
    required PaperColor paperColor,
  }) {
    if (content.trim().isEmpty || noteAt(cell) != null) return null;
    final sequence = _nextId++;
    final id = 'offline-local-$sequence';
    final tile = NoteTile(
      id: id,
      cell: cell,
      paperColor: paperColor,
      styleSeed: _positiveSeed(cell.x, cell.y, sequence),
      publishedAt: DateTime.utc(2026, 10, 23),
    );
    _addTile(tile);
    _localDetails[id] = NoteDetail(
      id: id,
      content: content.trim(),
      paperColor: paperColor,
      publishedAt: tile.publishedAt,
      canEncourage: false,
      canStartChat: false,
      isOwner: true,
      allowChat: false,
      canEdit: false,
      canDelete: false,
    );
    return tile;
  }

  void _seedFixture(int count) {
    // First make a small, dense, deterministic area so a fresh install opens
    // with enough notes to demonstrate wall gestures and note reading.
    final occupied = <WorldCell>{};
    var sequence = 1;
    for (var ring = 0; occupied.length < math.min(80, count); ring++) {
      for (var y = -ring; y <= ring && occupied.length < math.min(80, count); y++) {
        for (var x = -ring; x <= ring && occupied.length < math.min(80, count); x++) {
          if (math.max(x.abs(), y.abs()) != ring) continue;
          if ((x * 7 + y * 11).abs() % 4 == 0) continue;
          final cell = WorldCell(x: x, y: y);
          if (occupied.add(cell)) _addFixtureNote(sequence++, cell);
        }
      }
    }

    // The remaining fixture approximates the 10k-note population in M1-4.
    // Cells are unique; tile reads still return only the visible subset.
    var randomState = 0x51A7E;
    while (occupied.length < count) {
      randomState = (randomState * 1664525 + 1013904223) & 0x7FFFFFFF;
      final x = (randomState % 1025) - 512;
      randomState = (randomState * 1664525 + 1013904223) & 0x7FFFFFFF;
      final y = (randomState % 1025) - 512;
      final cell = WorldCell(x: x, y: y);
      if (occupied.add(cell)) _addFixtureNote(sequence++, cell);
    }
  }

  void _addFixtureNote(int sequence, WorldCell cell) {
    final colors = PaperColor.values;
    final tile = NoteTile(
      id: 'offline-note-${sequence.toString().padLeft(5, '0')}',
      cell: cell,
      paperColor: colors[(sequence * 7 + cell.x.abs() + cell.y.abs()) % colors.length],
      styleSeed: _positiveSeed(cell.x, cell.y, sequence),
      publishedAt: DateTime.utc(2026, 9, 1).add(Duration(days: sequence % 52)),
    );
    _addTile(tile);
  }

  void _addTile(NoteTile tile) {
    final key = WallTileCoordinate(
      WallGeometry.tileCoordinate(tile.cell.x),
      WallGeometry.tileCoordinate(tile.cell.y),
    );
    (_tilesByTile[key] ??= <NoteTile>[]).add(tile);
    _tilesById[tile.id] = tile;
  }

  NoteTile? _findById(String id) => _tilesById[id];

  NoteDetail _fixtureDetail(NoteTile tile) {
    const samples = <String>[
      'Hôm nay mình đã bước chậm lại một chút. Chỉ vậy thôi cũng đủ đáng quý rồi.',
      'Nếu bạn đang đọc những dòng này, mong bạn nhớ rằng mình không cần phải ổn ngay lập tức.',
      'Có những ngày bình thường trôi qua thật nhẹ. Mình muốn giữ lại cảm giác đó.',
      'Mình đang học cách dịu dàng với chính mình, kể cả khi chưa làm tốt mọi thứ.',
      'Một lời nhắc nhỏ: nghỉ ngơi cũng là một phần của hành trình.',
    ];
    return NoteDetail(
      id: tile.id,
      content: samples[tile.styleSeed % samples.length],
      paperColor: tile.paperColor,
      publishedAt: tile.publishedAt,
      canEncourage: false,
      canStartChat: false,
      isOwner: false,
      allowChat: false,
      canEdit: false,
      canDelete: false,
    );
  }

  int _positiveSeed(int x, int y, int salt) =>
      ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7FFFFFFF;
}
