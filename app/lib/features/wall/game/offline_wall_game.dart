import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/note_tile.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/domain/world_cell.dart';
import '../data/offline_wall_repository.dart';
import '../data/wall_tile_manager.dart';
import '../domain/wall_geometry.dart';
import '../domain/wall_scene_repository.dart';
import 'wall_note_component.dart';

typedef NoteSelectedCallback = void Function(
  NoteTile tile,
  NoteDetail? detail,
  Rect? sourceRect,
  double? sourceAngleRadians,
);

typedef WallViewportCallback = void Function(Rect absoluteBounds);

/// Offline-only wall engine for the M1 proof of concept.
///
/// Absolute camera coordinates stay as Dart doubles. Flame components are
/// re-based around the camera so the renderer never receives huge positions.
final class OfflineWallGame extends FlameGame with ScaleDetector {
  OfflineWallGame({
    OfflineWallRepository? repository,
    WallSceneRepository? sceneRepository,
    this.onNoteSelected,
    this.onPlacementChanged,
    this.onViewportChanged,
    this.minZoom = 0.45,
    this.maxZoom = 2.2,
  })  : repository = sceneRepository ?? repository ?? OfflineWallRepository(),
        super();

  final WallSceneRepository repository;
  final NoteSelectedCallback? onNoteSelected;
  final ValueChanged<WorldCell?>? onPlacementChanged;
  final WallViewportCallback? onViewportChanged;
  final double minZoom;
  final double maxZoom;

  late final WallTileManager _tileManager = WallTileManager(
    repository: repository,
    cacheCapacity: 30,
  );
  final Map<String, WallNoteComponent> _noteComponents = {};
  final Map<WallTileCoordinate, WallTileClusterComponent> _clusterComponents = {};
  final ValueNotifier<WorldCell?> candidateCell = ValueNotifier<WorldCell?>(null);
  final ValueNotifier<bool> candidateOccupied = ValueNotifier<bool>(false);
  final ValueNotifier<double> zoomLevel = ValueNotifier<double>(0.8);
  final ValueNotifier<bool> exploring = ValueNotifier<bool>(false);

  static const double _clusterZoomThreshold = 0.58;
  double _cameraWorldX = 0;
  double _cameraWorldY = 0;
  double _gestureStartZoom = 0.8;
  double _gestureStartScale = 1;
  int _gesturePointerCount = 0;
  double _gestureAnchorWorldX = 0;
  double _gestureAnchorWorldY = 0;
  double _gestureStartCanvasX = 0;
  double _gestureStartCanvasY = 0;
  bool _placementMode = false;
  bool _reducedMotion = false;
  PaperColor _selectedPaperColor = PaperColor.butter;
  double _lastTileSyncX = double.nan;
  double _lastTileSyncY = double.nan;
  double _lastTileSyncZoom = double.nan;
  bool _isReady = false;
  WallGhostComponent? _ghost;
  double _cameraStartX = 0;
  double _cameraStartY = 0;
  double? _cameraTargetX;
  double? _cameraTargetY;
  double _cameraAnimationElapsed = 0;
  static const double _cameraAnimationDuration = 0.38;

  bool get isPlacementMode => _placementMode;
  bool get isReducedMotion => _reducedMotion;
  WorldCell? get currentCandidate => candidateCell.value;
  double get cameraWorldX => _cameraWorldX;
  double get cameraWorldY => _cameraWorldY;

  @override
  Color backgroundColor() => const Color(0xFFF3E8D7);

  @override
  void onGameResize(Vector2 canvasSize) {
    super.onGameResize(canvasSize);
    _syncVisibleTiles(force: true);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.position = Vector2.zero();
    camera.viewfinder.zoom = WallGeometry.clampZoom(0.8, min: minZoom, max: maxZoom);
    zoomLevel.value = camera.viewfinder.zoom;
    _isReady = true;
    _syncVisibleTiles(force: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _updateCameraAnimation(dt);
    _syncVisibleTiles();
  }

  @override
  void onScaleStart(ScaleStartInfo info) {
    _stopCameraAnimation();
    _gestureStartZoom = camera.viewfinder.zoom;
    _gestureStartScale = 1;
    _gesturePointerCount = info.raw.pointerCount;
    _gestureStartCanvasX = info.eventPosition.widget.dx;
    _gestureStartCanvasY = info.eventPosition.widget.dy;
    final worldPoint = _canvasToAbsoluteWorld(
      _gestureStartCanvasX,
      _gestureStartCanvasY,
      _gestureStartZoom,
    );
    _gestureAnchorWorldX = worldPoint.dx;
    _gestureAnchorWorldY = worldPoint.dy;
    if (_placementMode) {
      _setCandidate(_screenToCell(_gestureStartCanvasX, _gestureStartCanvasY));
    }
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    final focalX = info.eventPosition.widget.dx;
    final focalY = info.eventPosition.widget.dy;
    final pointerCount = info.raw.pointerCount;
    final currentScale = info.scale.global.y;
    if (pointerCount != _gesturePointerCount) {
      // Flutter's scale recognizer changes its focal point when the second
      // finger joins or leaves. Re-anchor at that transition to prevent jumps.
      _gesturePointerCount = pointerCount;
      _gestureStartZoom = camera.viewfinder.zoom;
      _gestureStartScale = currentScale;
      final anchor = _canvasToAbsoluteWorld(focalX, focalY, _gestureStartZoom);
      _gestureAnchorWorldX = anchor.dx;
      _gestureAnchorWorldY = anchor.dy;
    }
    if (_placementMode && pointerCount == 1) {
      // In placement mode a one-finger drag moves the ghost between cells;
      // ordinary wall panning resumes after the user cancels placement.
      _setCandidate(_screenToCell(focalX, focalY));
      return;
    }
    final scaleFactor = currentScale / _gestureStartScale;
    final nextZoom = WallGeometry.clampZoom(
      _gestureStartZoom * scaleFactor,
      min: minZoom,
      max: maxZoom,
    );
    final centerX = size.x / 2;
    final centerY = size.y / 2;

    // Keep the absolute world point under the starting pinch focal point
    // anchored beneath the current focal point as fingers move or zoom.
    _cameraWorldX = _gestureAnchorWorldX - (focalX - centerX) / nextZoom;
    _cameraWorldY = _gestureAnchorWorldY - (focalY - centerY) / nextZoom;
    camera.viewfinder.zoom = nextZoom;
    zoomLevel.value = nextZoom;
    _repositionVisibleComponents();

    if (_placementMode) {
      _setCandidate(_screenToCell(focalX, focalY));
    }
    _syncVisibleTiles();
  }

  void beginPlacement({PaperColor color = PaperColor.butter}) {
    _placementMode = true;
    _selectedPaperColor = color;
    final centerCell = WallGeometry.worldToCell(
      x: _cameraWorldX,
      y: _cameraWorldY,
    );
    _setCandidate(centerCell);
    _refreshNoteInteractivity();
    _syncVisibleTiles(force: true);
  }

  void updatePlacementColor(PaperColor color) {
    _selectedPaperColor = color;
    if (_ghost != null) _ghost!.paperColor = color;
  }

  void cancelPlacement() {
    _placementMode = false;
    candidateCell.value = null;
    candidateOccupied.value = false;
    _ghost?.removeFromParent();
    _ghost = null;
    _refreshNoteInteractivity();
    _syncVisibleTiles(force: true);
  }

  /// Commits only to this in-memory POC repository, and only for an empty cell.
  bool confirmPlacement(String content) {
    final cell = candidateCell.value;
    if (!_placementMode || cell == null || candidateOccupied.value) return false;
    final scene = repository;
    if (scene is! OfflineWallRepository) return false;
    final tile = scene.placeLocally(
      cell: cell,
      content: content,
      paperColor: _selectedPaperColor,
    );
    if (tile == null) {
      _setCandidate(cell);
      return false;
    }

    _tileManager.invalidate(cell);
    _syncVisibleTiles(force: true);
    cancelPlacement();
    return true;
  }

  void setReducedMotion(bool value) {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    for (final component in _noteComponents.values) {
      component.removeFromParent();
    }
    _noteComponents.clear();
    _syncVisibleTiles(force: true);
  }

  void focusOn(WorldCell cell) {
    _stopCameraAnimation();
    _cameraWorldX = WallGeometry.cellCenter(cell.x);
    _cameraWorldY = WallGeometry.cellCenter(cell.y);
    _repositionVisibleComponents();
    _syncVisibleTiles(force: true);
  }

  /// Camera target used by authenticated discovery and inbox jump flows.
  void moveCameraTo(WorldCell cell) {
    if (_reducedMotion) {
      focusOn(cell);
      return;
    }
    _cameraStartX = _cameraWorldX;
    _cameraStartY = _cameraWorldY;
    _cameraTargetX = WallGeometry.cellCenter(cell.x);
    _cameraTargetY = WallGeometry.cellCenter(cell.y);
    _cameraAnimationElapsed = 0;
    exploring.value = true;
  }

  void refreshScene({bool clearCachedTiles = false}) {
    if (clearCachedTiles) _tileManager.clear();
    _syncVisibleTiles(force: true);
  }

  void exploreOtherRegion() {
    final scene = repository;
    if (scene is! OfflineWallRepository) return;
    final target = scene.discoveryTarget();
    if (_reducedMotion) {
      focusOn(target);
      return;
    }
    _cameraStartX = _cameraWorldX;
    _cameraStartY = _cameraWorldY;
    _cameraTargetX = WallGeometry.cellCenter(target.x);
    _cameraTargetY = WallGeometry.cellCenter(target.y);
    _cameraAnimationElapsed = 0;
    exploring.value = true;
  }

  @override
  void onDispose() {
    candidateCell.dispose();
    candidateOccupied.dispose();
    zoomLevel.dispose();
    exploring.dispose();
    super.onDispose();
  }

  void _setCandidate(WorldCell? value) {
    if (candidateCell.value == value) {
      final occupied = value != null && repository.noteAt(value) != null;
      candidateOccupied.value = occupied;
      _updateGhost(value, occupied);
      return;
    }
    candidateCell.value = value;
    final occupied = value != null && repository.noteAt(value) != null;
    candidateOccupied.value = occupied;
    _updateGhost(value, occupied);
    onPlacementChanged?.call(value);
  }

  void _updateGhost(WorldCell? cell, bool occupied) {
    if (cell == null || !_placementMode) {
      _ghost?.removeFromParent();
      _ghost = null;
      return;
    }
    if (_ghost == null) {
      _ghost = WallGhostComponent(
        position: _localPosition(cell),
        paperColor: _selectedPaperColor,
        isOccupied: occupied,
      );
      world.add(_ghost!);
      return;
    }
    _ghost!
      ..position.setFrom(_localPosition(cell))
      ..paperColor = _selectedPaperColor
      ..isOccupied = occupied;
  }

  WorldCell _screenToCell(double screenX, double screenY) {
    final point = _canvasToAbsoluteWorld(screenX, screenY, camera.viewfinder.zoom);
    return WallGeometry.worldToCell(x: point.dx, y: point.dy);
  }

  Offset _canvasToAbsoluteWorld(double screenX, double screenY, double zoom) => Offset(
        _cameraWorldX + (screenX - size.x / 2) / zoom,
        _cameraWorldY + (screenY - size.y / 2) / zoom,
      );

  Rect _visibleAbsoluteBounds() {
    final local = camera.visibleWorldRect;
    return local.shift(Offset(_cameraWorldX, _cameraWorldY));
  }

  void _syncVisibleTiles({bool force = false}) {
    if (!hasLayout || !_isReady) return;
    final currentZoom = camera.viewfinder.zoom;
    if (!force &&
        (_cameraWorldX - _lastTileSyncX).abs() < WallGeometry.tileSizeWorldUnits / 2 &&
        (_cameraWorldY - _lastTileSyncY).abs() < WallGeometry.tileSizeWorldUnits / 2 &&
        (currentZoom - _lastTileSyncZoom).abs() < 0.12) {
      return;
    }

    _lastTileSyncX = _cameraWorldX;
    _lastTileSyncY = _cameraWorldY;
    _lastTileSyncZoom = currentZoom;
    final visible = _visibleAbsoluteBounds().inflate(WallGeometry.tileSizeWorldUnits.toDouble());
    final notes = _tileManager.visibleNotes(visible);
    if (currentZoom <= _clusterZoomThreshold && !_placementMode) {
      _showClusters(notes);
    } else {
      _showNotes(notes);
    }
    onViewportChanged?.call(visible);
  }

  void _showNotes(List<NoteTile> notes) {
    for (final cluster in _clusterComponents.values) {
      cluster.removeFromParent();
    }
    _clusterComponents.clear();
    final ids = notes.map((note) => note.id).toSet();
    for (final entry in _noteComponents.entries.toList()) {
      if (!ids.contains(entry.key)) {
        entry.value.removeFromParent();
        _noteComponents.remove(entry.key);
      }
    }
    for (final note in notes) {
      final localPosition = _localPosition(note.cell);
      final existing = _noteComponents[note.id];
      if (existing != null) {
        existing.setWallPosition(localPosition);
        continue;
      }
      final component = WallNoteComponent(
        note: note,
        position: localPosition,
        reducedMotion: _reducedMotion,
        isInteractive: !_placementMode,
        onOpen: _openNote,
      );
      _noteComponents[note.id] = component;
      world.add(component);
    }
    _refreshNoteInteractivity();
  }

  void _showClusters(List<NoteTile> notes) {
    for (final component in _noteComponents.values) {
      component.removeFromParent();
    }
    _noteComponents.clear();
    final grouped = <WallTileCoordinate, List<NoteTile>>{};
    for (final note in notes) {
      final coordinate = WallTileCoordinate(
        WallGeometry.tileCoordinate(note.cell.x),
        WallGeometry.tileCoordinate(note.cell.y),
      );
      (grouped[coordinate] ??= <NoteTile>[]).add(note);
    }
    for (final entry in _clusterComponents.entries.toList()) {
      if (!grouped.containsKey(entry.key)) {
        entry.value.removeFromParent();
        _clusterComponents.remove(entry.key);
      }
    }
    for (final entry in grouped.entries) {
      if (_clusterComponents.containsKey(entry.key)) continue;
      final cellX = entry.key.originCellX + WallGeometry.cellsPerTile ~/ 2;
      final cellY = entry.key.originCellY + WallGeometry.cellsPerTile ~/ 2;
      final center = _localPosition(WorldCell(x: cellX, y: cellY));
      final component = WallTileClusterComponent(
        notes: entry.value,
        position: center,
        onOpenRegion: () => focusOn(WorldCell(x: cellX, y: cellY)),
      );
      _clusterComponents[entry.key] = component;
      world.add(component);
    }
  }

  void _repositionVisibleComponents() {
    for (final component in _noteComponents.values) {
      component.setWallPosition(_localPosition(component.note.cell));
    }
    for (final entry in _clusterComponents.entries) {
      final cellX = entry.key.originCellX + WallGeometry.cellsPerTile ~/ 2;
      final cellY = entry.key.originCellY + WallGeometry.cellsPerTile ~/ 2;
      entry.value.position.setFrom(_localPosition(WorldCell(x: cellX, y: cellY)));
    }
    final cell = candidateCell.value;
    if (cell != null) _ghost?.position.setFrom(_localPosition(cell));
  }

  Vector2 _localPosition(WorldCell cell) => Vector2(
        WallGeometry.cellCenter(cell.x) - _cameraWorldX,
        WallGeometry.cellCenter(cell.y) - _cameraWorldY,
      );

  void _refreshNoteInteractivity() {
    for (final component in _noteComponents.values) {
      component.isInteractive = !_placementMode;
    }
  }

  void _openNote(NoteTile tile) {
    if (_placementMode) return;
    final detail = repository.detailFor(tile.id);

    final component = _noteComponents[tile.id];
    final sourceRect = component == null ? null : _noteBoundsInCanvas(component);
    onNoteSelected?.call(tile, detail, sourceRect, component?.angle);
  }

  Rect _noteBoundsInCanvas(WallNoteComponent component) {
    final zoom = camera.viewfinder.zoom;
    // Keep this rect in the paper's local orientation; sourceAngleRadians is
    // passed separately so the Flutter reader can animate rotation to zero.
    final width = component.size.x * component.scale.x * zoom;
    final height = component.size.y * component.scale.y * zoom;
    final center = Offset(
      size.x / 2 + component.position.x * zoom,
      size.y / 2 + component.position.y * zoom,
    );

    return Rect.fromCenter(center: center, width: width, height: height);
  }

  void _updateCameraAnimation(double dt) {
    final targetX = _cameraTargetX;
    final targetY = _cameraTargetY;
    if (targetX == null || targetY == null) return;
    _cameraAnimationElapsed += dt;
    final progress =
        (_cameraAnimationElapsed / _cameraAnimationDuration).clamp(0.0, 1.0).toDouble();
    final eased = Curves.easeInOutCubic.transform(progress);
    _cameraWorldX = _cameraStartX + (targetX - _cameraStartX) * eased;
    _cameraWorldY = _cameraStartY + (targetY - _cameraStartY) * eased;
    _repositionVisibleComponents();
    if (progress >= 1) {
      _cameraWorldX = targetX;
      _cameraWorldY = targetY;
      _stopCameraAnimation();
      _repositionVisibleComponents();
    }
  }

  void _stopCameraAnimation() {
    _cameraTargetX = null;
    _cameraTargetY = null;
    _cameraAnimationElapsed = 0;
    if (exploring.value) exploring.value = false;
  }
}
