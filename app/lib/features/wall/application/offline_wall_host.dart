import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/domain/note_detail.dart';
import '../../../core/domain/paper_color.dart';
import '../game/offline_wall_game.dart';
import '../presentation/wall_screen.dart';

/// Connects the offline M1 wall logic to its presentation contract.
///
/// All writes made here remain in the in-memory POC repository. M2 replaces
/// this host's repository without changing the presentation widgets.
final class OfflineWallHost extends StatefulWidget {
  const OfflineWallHost({super.key});

  @override
  State<OfflineWallHost> createState() => _OfflineWallHostState();
}

final class _OfflineWallHostState extends State<OfflineWallHost> {
  late final OfflineWallGame _game;
  NoteDetail? _activeNote;
  Rect? _activeNoteSourceRect;
  double? _activeNoteSourceAngleRadians;
  String _draftContent = '';
  PaperColor _draftPaperColor = PaperColor.butter;

  @override
  void initState() {
    super.initState();
    _game = OfflineWallGame(
      onNoteSelected: (_, detail, sourceRect, sourceAngleRadians) {
        if (!mounted) return;
        setState(() {
          _activeNote = detail;
          _activeNoteSourceRect = sourceRect;
          _activeNoteSourceAngleRadians = sourceAngleRadians;
        });
      },
      onPlacementChanged: (_) {
        if (mounted) setState(() {});
      },
    );
    _game.exploring.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _game.setReducedMotion(MediaQuery.of(context).disableAnimations);
  }

  @override
  void dispose() {
    _game.exploring.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _enterPlacement() {
    setState(() {
      _draftContent = '';
      _draftPaperColor = PaperColor.butter;
    });
    _game.beginPlacement(color: _draftPaperColor);
  }

  void _cancelPlacement() {
    _game.cancelPlacement();
    setState(() => _draftContent = '');
  }

  void _confirmPlacement() {
    final content = _draftContent.trim();
    if (content.isEmpty || content.characters.length > 1000) return;
    if (!_game.confirmPlacement(content)) {
      if (_game.currentCandidate != null && _game.candidateOccupied.value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chỗ này đã có giấy. Hãy chọn một ô khác.')),
        );
      }
      return;
    }
    setState(() => _draftContent = '');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã lưu giấy trong bản thử cục bộ này; nội dung chưa được chia sẻ.'),
      ),
    );
  }

  void _closeNote() {
    setState(() {
      _activeNote = null;
      _activeNoteSourceRect = null;
      _activeNoteSourceAngleRadians = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WallScreen(
      gameWidget: GameWidget(game: _game),
      activeNoteDetail: _activeNote,
      activeNoteSourceRect: _activeNoteSourceRect,
      activeNoteSourceAngleRadians: _activeNoteSourceAngleRadians,
      isPlacementMode: _game.isPlacementMode,
      isPlacementCellOccupied: _game.candidateOccupied.value,
      draftContent: _draftContent,
      draftPaperColor: _draftPaperColor,
      isExploring: _game.exploring.value,
      onExploreOtherRegion: _game.exploreOtherRegion,
      onEnterPlacement: _enterPlacement,
      onCancelPlacement: _cancelPlacement,
      onConfirmPlacement: _confirmPlacement,
      onCloseNoteDetail: _closeNote,
      onDraftContentChanged: (value) => setState(() => _draftContent = value),
      onDraftPaperColorChanged: (value) {
        setState(() => _draftPaperColor = value);
        _game.updatePlacementColor(value);
      },
    );
  }
}
