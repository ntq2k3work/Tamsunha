import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/private_signal.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/domain/world_cell.dart';
import '../../../core/errors/backend_exception.dart';
import '../../../core/ids/client_request_id.dart';
import '../../../core/notifications/product_analytics.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../core/router/app_routes.dart';
import '../data/remote_wall_scene_cache.dart';
import '../domain/wall_geometry.dart';
import '../domain/wall_repository.dart';
import '../game/offline_wall_game.dart';
import '../presentation/wall_screen.dart';
import '../../encouragements/presentation/encouragement_sheet.dart';
import '../../inbox/domain/inbox_repository.dart';
import '../../safety/domain/safety_repository.dart';
import '../../safety/presentation/report_block_sheet.dart';

final class SharedWallHost extends ConsumerStatefulWidget {
  const SharedWallHost({super.key, this.initialCell});

  final WorldCell? initialCell;

  @override
  ConsumerState<SharedWallHost> createState() => _SharedWallHostState();
}

final class _SharedWallHostState extends ConsumerState<SharedWallHost>
    with WidgetsBindingObserver {
  final RemoteWallSceneCache _scene = RemoteWallSceneCache();
  final Map<WallTileCoordinate, Future<void>> _tileLoads = {};
  final Map<WallTileCoordinate, PrivateSignal> _wallChannels = {};
  final Map<String, String> _encouragementRequestIds = <String, String>{};
  final Map<String, String> _conversationRequestIds = <String, String>{};
  final Map<String, String> _deleteRequestIds = <String, String>{};
  final Map<String, String> _editRequestIds = <String, String>{};
  final Map<String, String> _editRequestContents = <String, String>{};
  Set<WallTileCoordinate> _visibleCoordinates = <WallTileCoordinate>{};
  late final OfflineWallGame _game;
  late final WallRepository _wallRepository;
  late final InboxRepository _inboxRepository;
  late final SafetyRepository _safetyRepository;
  ApiClient? _client;

  NoteDetail? _activeNote;
  Rect? _activeNoteSourceRect;
  double? _activeNoteSourceAngleRadians;
  String _draftContent = '';
  PaperColor _draftPaperColor = PaperColor.butter;
  bool _isSubmittingPlacement = false;
  String? _placementRequestId;
  String? _placementRequestContent;
  bool _isExploring = false;
  Rect? _lastVisibleBounds;

  @override
  void initState() {
    super.initState();
    _wallRepository = ref.read(wallRepositoryProvider);
    _inboxRepository = ref.read(inboxRepositoryProvider);
    _safetyRepository = ref.read(safetyRepositoryProvider);
    _client = ref.read(apiClientProvider);
    WidgetsBinding.instance.addObserver(this);
    _game = OfflineWallGame(
      sceneRepository: _scene,
      onViewportChanged: _loadVisibleTiles,
      onNoteSelected: (tile, detail, sourceRect, sourceAngleRadians) {
        if (!mounted) return;
        _activeNoteSourceRect = sourceRect;
        _activeNoteSourceAngleRadians = sourceAngleRadians;
        if (detail != null) {
          unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.noteOpened));
          setState(() => _activeNote = detail);
        } else {
          unawaited(_loadNoteDetail(tile.id, recordOpen: true));
        }
      },
    );
    _game.exploring.addListener(_refreshExplorationState);
    if (widget.initialCell != null) {
      _game.focusOn(widget.initialCell!);
    } else {
      unawaited(_exploreOtherRegion(initial: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game.setReducedMotion(MediaQuery.of(context).disableAnimations);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.exploring.removeListener(_refreshExplorationState);
    final client = _client;
    if (client != null) {
      for (final channel in _wallChannels.values) {
        channel.close();
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _scene.clear();
    _game.refreshScene(clearCachedTiles: true);
    final bounds = _lastVisibleBounds;
    if (bounds != null) _loadVisibleTiles(bounds);
  }

  void _refreshExplorationState() {
    if (mounted) setState(() => _isExploring = _game.exploring.value);
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is BackendException
        ? error.message
        : 'Không thể kết nối lúc này. Hãy thử lại sau.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _loadVisibleTiles(Rect bounds) {
    _lastVisibleBounds = bounds;
    final visible = WallGeometry.tilesIntersecting(bounds);
    _syncWallChannels(visible);
    for (final coordinate in visible) {
      if (_scene.notesForTile(coordinate) != null || _tileLoads.containsKey(coordinate)) {
        continue;
      }
      unawaited(_loadTileTracked(coordinate));
    }
  }

  Future<void> _loadTileTracked(WallTileCoordinate coordinate) {
    final existing = _tileLoads[coordinate];
    if (existing != null) return existing;
    final load = _loadTile(coordinate);
    _tileLoads[coordinate] = load;
    unawaited(load.whenComplete(() {
      if (identical(_tileLoads[coordinate], load)) _tileLoads.remove(coordinate);
    }));
    return load;
  }

  void _syncWallChannels(Set<WallTileCoordinate> visible) {
    final client = _client;
    if (client == null) return;
    _visibleCoordinates = visible;
    for (final coordinate in _wallChannels.keys.toList(growable: false)) {
      if (visible.contains(coordinate)) continue;
      final channel = _wallChannels.remove(coordinate);
      channel?.close();
    }
    for (final coordinate in visible) {
      if (_wallChannels.containsKey(coordinate)) continue;
      final channel = PrivateSignal(client, 'wall:${coordinate.x}:${coordinate.y}', () {
        if (!mounted || !_visibleCoordinates.contains(coordinate)) return;
        _scene.invalidate(coordinate);
        unawaited(_refreshTile(coordinate));
      });
      _wallChannels[coordinate] = channel;
    }
  }

  Future<void> _refreshTile(WallTileCoordinate coordinate) async {
    final pending = _tileLoads[coordinate];
    if (pending != null) await pending;
    if (!mounted || !_visibleCoordinates.contains(coordinate)) return;
    _scene.invalidate(coordinate);
    await _loadTileTracked(coordinate);
  }

  Future<void> _loadTile(WallTileCoordinate coordinate) async {
    try {
      final originX = coordinate.originCellX;
      final originY = coordinate.originCellY;
      final page = await _wallRepository.getWallTiles(
        minCellX: originX,
        maxCellX: originX + WallGeometry.cellsPerTile - 1,
        minCellY: originY,
        maxCellY: originY + WallGeometry.cellsPerTile - 1,
        limit: 64,
      );
      _scene.putTile(coordinate, page.items);
      if (mounted) _game.refreshScene(clearCachedTiles: true);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadNoteDetail(String noteId, {bool recordOpen = false}) async {
    try {
      final detail = await _wallRepository.getNoteDetail(noteId);
      if (!mounted) return;
      if (recordOpen) {
        unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.noteOpened));
      }
      setState(() => _activeNote = detail);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _exploreOtherRegion({bool initial = false}) async {
    try {
      final target = await _wallRepository.getDiscoveryTarget();
      if (!mounted) return;
      if (!initial) {
        unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.wallRegionVisited));
      }
      final cell = WallGeometry.worldToCell(
        x: target.cameraWorldX.toDouble(),
        y: target.cameraWorldY.toDouble(),
      );
      _game.moveCameraTo(cell);
    } catch (error) {
      if (!initial) _showError(error);
    }
  }

  void _enterPlacement() {
    setState(() {
      _draftContent = '';
      _draftPaperColor = PaperColor.butter;
      _placementRequestId = null;
      _placementRequestContent = null;
    });
    _game.beginPlacement(color: _draftPaperColor);
  }

  void _setDraftContent(String value) {
    if (_placementRequestContent != null && _placementRequestContent != value) {
      _placementRequestId = null;
      _placementRequestContent = null;
    }
    setState(() => _draftContent = value);
  }

  void _cancelPlacement() {
    _game.cancelPlacement();
    setState(() {
      _draftContent = '';
      _placementRequestId = null;
      _placementRequestContent = null;
    });
  }

  Future<void> _confirmPlacement() async {
    final content = _draftContent.trim();
    final cell = _game.currentCandidate;
    if (cell == null || content.isEmpty || content.characters.length > 1000) return;
    final requestId = _placementRequestId ?? ClientRequestId.create();
    _placementRequestId = requestId;
    _placementRequestContent = content;
    setState(() => _isSubmittingPlacement = true);
    try {
      final result = await _wallRepository.placeNote(
        content: content,
        paperColor: _draftPaperColor,
        allowChat: true,
        cell: cell,
        clientRequestId: requestId,
      );
      if (!mounted) return;
      unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.noteCreated));
      if (result.status == 'published') {
        unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.notePlaced));
      }
      _game.cancelPlacement();
      setState(() {
        _draftContent = '';
        _placementRequestId = null;
        _placementRequestContent = null;
      });
      if (result.status == 'published') {
        final coordinate = WallTileCoordinate(
          WallGeometry.tileCoordinate(cell.x),
          WallGeometry.tileCoordinate(cell.y),
        );
        _scene.invalidate(coordinate);
        _game.focusOn(cell);
        _game.refreshScene(clearCachedTiles: true);
        _loadVisibleTiles(_gameVisibleBounds(cell));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tờ giấy đã được dán lên bức tường.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tờ giấy đang chờ kiểm duyệt.')),
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSubmittingPlacement = false);
    }
  }

  Rect _gameVisibleBounds(WorldCell cell) => Rect.fromCenter(
        center: Offset(
          WallGeometry.cellCenter(cell.x),
          WallGeometry.cellCenter(cell.y),
        ),
        width: WallGeometry.tileSizeWorldUnits.toDouble() * 2,
        height: WallGeometry.tileSizeWorldUnits.toDouble() * 2,
      );

  void _closeNote() {
    setState(() {
      _activeNote = null;
      _activeNoteSourceRect = null;
      _activeNoteSourceAngleRadians = null;
    });
  }

  Future<void> _showEncouragement(NoteDetail note) async {
    var alreadySent = note.alreadyEncouraged;
    var isSubmitting = false;
    String? errorMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: EncouragementSheet(
              noteId: note.id,
              isOwner: note.isOwner,
              alreadySent: alreadySent,
              isSubmitting: isSubmitting,
              errorMessage: errorMessage,
              onClose: () => Navigator.of(sheetContext).pop(),
              onSendEncouragement: (templateKey) async {
                if (isSubmitting || alreadySent) return;
                setSheetState(() {
                  isSubmitting = true;
                  errorMessage = null;
                });
                try {
                  await _inboxRepository.sendEncouragement(
                    noteId: note.id,
                    templateKey: templateKey,
                    clientRequestId: _encouragementRequestIds.putIfAbsent(
                      '${note.id}:$templateKey',
                      ClientRequestId.create,
                    ),
                  );
                  unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.encouragementSent));
                  _encouragementRequestIds.remove('${note.id}:$templateKey');
                  setSheetState(() => alreadySent = true);
                } catch (error) {
                  setSheetState(() => errorMessage = _messageFor(error));
                } finally {
                  if (sheetContext.mounted) {
                    setSheetState(() => isSubmitting = false);
                  }
                }
              },
            ),
          ),
        ),
      ),
    );
    if (mounted && _activeNote?.id == note.id) unawaited(_loadNoteDetail(note.id));
  }

  Future<void> _startChat(NoteDetail note) async {
    try {
      final conversation = await _inboxRepository.startConversationFromNote(
        note.id,
        clientRequestId: _conversationRequestIds.putIfAbsent(note.id, ClientRequestId.create),
      );
      unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.conversationStarted));
      _conversationRequestIds.remove(note.id);
      if (mounted) {
        context.goNamed(
          AppRoute.conversation.name,
          pathParameters: <String, String>{'conversationId': conversation.id},
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editNote(NoteDetail note) async {
    final controller = TextEditingController(text: note.content);
    try {
      final content = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sửa tờ giấy'),
          content: TextField(
            controller: controller,
            maxLength: 1000,
            maxLines: 6,
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Lưu'),
            ),
          ],
        ),
      );
      if (content == null || !mounted) return;
      if (_editRequestContents[note.id] != content || !_editRequestIds.containsKey(note.id)) {
        _editRequestContents[note.id] = content;
        _editRequestIds[note.id] = ClientRequestId.create();
      }
      await _wallRepository.editNote(
        noteId: note.id,
        newContent: content,
        clientRequestId: _editRequestIds[note.id]!,
      );
      _editRequestIds.remove(note.id);
      _editRequestContents.remove(note.id);
      await _loadNoteDetail(note.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi nội dung sửa để kiểm tra lại.')),
      );
    } catch (error) {
      _showError(error);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteNote(NoteDetail note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gỡ tờ giấy?'),
        content: const Text('Tờ giấy sẽ được gỡ khỏi bức tường chung. Lượt viết hôm nay vẫn được tính.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Gỡ giấy')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _wallRepository.deleteNote(
        note.id,
        clientRequestId: _deleteRequestIds.putIfAbsent(note.id, ClientRequestId.create),
      );
      _deleteRequestIds.remove(note.id);
      _closeNote();
      _game.refreshScene(clearCachedTiles: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gỡ tờ giấy khỏi bức tường.')),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showReport(NoteDetail note, {bool reportUser = false}) async {
    var isSubmitting = false;
    String? errorMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ReportBlockSheet(
          targetId: note.id,
          // The note ID is context only. The server resolves the author ID;
          // it is never sent to or rendered by this sheet.
          targetType: reportUser ? 'user' : 'note',
          isSubmitting: isSubmitting,
          errorMessage: errorMessage,
          onClose: () => Navigator.of(sheetContext).pop(),
          onSubmitReport: ({required reason, detail, required blockPartner}) async {
            setSheetState(() {
              isSubmitting = true;
              errorMessage = null;
            });
            try {
              final safety = _safetyRepository;
              if (blockPartner) {
                if (reportUser) {
                  await safety.reportAndBlockUserFromNote(
                    noteId: note.id,
                    reason: reason,
                    description: detail,
                  );
                } else {
                  await safety.reportAndBlockNote(
                    noteId: note.id,
                    reason: reason,
                    description: detail,
                  );
                }
              } else if (reportUser) {
                await safety.reportUserFromNote(
                  noteId: note.id,
                  reason: reason,
                  description: detail,
                );
              } else {
                await safety.report(
                  targetType: 'note',
                  targetId: note.id,
                  reason: reason,
                  description: detail,
                );
              }
              unawaited(ref.read(productAnalyticsProvider).record(ProductEvent.reportSubmitted));
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã gửi báo cáo an toàn.')),
                );
              }
            } catch (error) {
              setSheetState(() => errorMessage = _messageFor(error));
            } finally {
              setSheetState(() => isSubmitting = false);
            }
          },
          onBlockOnly: () async {
            setSheetState(() => isSubmitting = true);
            try {
              await _safetyRepository.blockFromNote(note.id);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } catch (error) {
              setSheetState(() => errorMessage = _messageFor(error));
            } finally {
              setSheetState(() => isSubmitting = false);
            }
          },
        ),
      ),
    );
  }

  String _messageFor(Object error) => error is BackendException
      ? error.message
      : 'Không thể kết nối lúc này. Hãy thử lại sau.';

  @override
  Widget build(BuildContext context) {
    return WallScreen(
      gameWidget: GameWidget(game: _game),
      activeNoteDetail: _activeNote,
      activeNoteSourceRect: _activeNoteSourceRect,
      activeNoteSourceAngleRadians: _activeNoteSourceAngleRadians,
      isPlacementMode: _game.isPlacementMode,
      isPlacementCellOccupied: _game.candidateOccupied.value,
      isPlacementSubmitting: _isSubmittingPlacement,
      draftContent: _draftContent,
      draftPaperColor: _draftPaperColor,
      isExploring: _isExploring,
      onExploreOtherRegion: () => unawaited(_exploreOtherRegion()),
      onEnterPlacement: _enterPlacement,
      onCancelPlacement: _cancelPlacement,
      onConfirmPlacement: () => unawaited(_confirmPlacement()),
      onCloseNoteDetail: _closeNote,
      onDraftContentChanged: _setDraftContent,
      onDraftPaperColorChanged: (value) {
        setState(() => _draftPaperColor = value);
        _game.updatePlacementColor(value);
      },
      onEncourageNote: (note) => unawaited(_showEncouragement(note)),
      onStartChatNote: (note) => unawaited(_startChat(note)),
      onEditNote: (note) => unawaited(_editNote(note)),
      onDeleteNote: (note) => unawaited(_deleteNote(note)),
      onReportNote: (note) => unawaited(_showReport(note)),
      onReportUser: (note) => unawaited(_showReport(note, reportUser: true)),
    );
  }
}

