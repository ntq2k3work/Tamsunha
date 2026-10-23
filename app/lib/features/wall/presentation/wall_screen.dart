import 'package:flutter/material.dart';
import '../../../core/domain/note_detail.dart';
import '../../../core/domain/paper_color.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_sheet.dart';
import '../../../core/widgets/seamless_paper_background.dart';
import 'widgets/note_reader_sheet.dart';
import 'widgets/wall_hud.dart';
import 'widgets/wall_placement_overlay.dart';

/// Màn hình Bức tường chung (Infinite Wall — S03).
///
/// Tầng giao diện chính chịu trách nhiệm:
/// 1. Nhúng Flame Canvas (`gameWidget`) bên dưới lớp nền.
/// 2. Hiển thị HUD điều hướng (Khám phá góc khác, nút dán giấy +).
/// 3. Hiển thị lớp phủ soạn thảo & chọn vị trí dán giấy (Placement Overlay — S05/S06).
/// 4. Hiển thị tờ giấy đọc chi tiết (NoteReaderSheet — S04) khi người dùng chạm vào một note.
///
/// Cung cấp hợp đồng giao tiếp (Contract) đầy đủ typed props/callbacks để Codex kết nối logic.
class WallScreen extends StatefulWidget {
  /// Widget chứa Flame Game (Canvas 2D vô hạn). Nếu null, fallback về nền giấy tĩnh.
  final Widget? gameWidget;

  /// Tờ giấy đang được mở đọc chi tiết (S04). Nếu null, không hiển thị reader sheet.
  final NoteDetail? activeNoteDetail;

  /// Tọa độ cục bộ của tờ giấy vừa chạm trên canvas (dùng làm gốc chuyển cảnh bay ra/vào).
  final Rect? activeNoteSourceRect;

  /// Góc xoay cục bộ của tờ giấy trên canvas (theo radian, dùng để xoay về 0° khi mở).
  final double? activeNoteSourceAngleRadians;

  /// Đang ở chế độ dán giấy (Placement Mode — S06) hay không.
  final bool isPlacementMode;

  /// Trạng thái ô đang chọn có bị chiếm dụng bởi giấy khác hay không.
  final bool isPlacementCellOccupied;

  /// Đang trong quá trình submit dán giấy hay không.
  final bool isPlacementSubmitting;

  /// Nội dung dự thảo của tờ giấy (1 - 1.000 ký tự).
  final String draftContent;

  /// Màu giấy dự kiến cho tờ giấy đang chuẩn bị dán (1 trong 5 màu pastel).
  final PaperColor draftPaperColor;

  /// Đang thực hiện chuyển camera tới góc khác hay không.
  final bool isExploring;

  // --- Callbacks kết nối tầng Logic/Controller ---
  final ValueChanged<String>? onDraftContentChanged;
  final ValueChanged<PaperColor>? onDraftPaperColorChanged;
  final VoidCallback? onExploreOtherRegion;
  final VoidCallback? onEnterPlacement;
  final VoidCallback? onCancelPlacement;
  final VoidCallback? onConfirmPlacement;
  final VoidCallback? onCloseNoteDetail;
  final ValueChanged<NoteDetail>? onEncourageNote;
  final ValueChanged<NoteDetail>? onStartChatNote;
  final ValueChanged<NoteDetail>? onEditNote;
  final ValueChanged<NoteDetail>? onDeleteNote;
  final ValueChanged<NoteDetail>? onReportNote;
  final ValueChanged<NoteDetail>? onReportUser;

  const WallScreen({
    super.key,
    this.gameWidget,
    this.activeNoteDetail,
    this.activeNoteSourceRect,
    this.activeNoteSourceAngleRadians,
    this.isPlacementMode = false,
    this.isPlacementCellOccupied = false,
    this.isPlacementSubmitting = false,
    this.draftContent = '',
    this.draftPaperColor = PaperColor.butter,
    this.isExploring = false,
    this.onDraftContentChanged,
    this.onDraftPaperColorChanged,
    this.onExploreOtherRegion,
    this.onEnterPlacement,
    this.onCancelPlacement,
    this.onConfirmPlacement,
    this.onCloseNoteDetail,
    this.onEncourageNote,
    this.onStartChatNote,
    this.onEditNote,
    this.onDeleteNote,
    this.onReportNote,
    this.onReportUser,
  });

  @override
  State<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends State<WallScreen> {
  // Trạng thái cục bộ hỗ trợ fallback preview khi chạy độc lập (standalone mode)
  bool _localPlacementMode = false;
  NoteDetail? _localActiveNote;
  String _localDraftContent = '';
  PaperColor _localDraftColor = PaperColor.butter;

  bool get _effectivePlacementMode =>
      widget.onEnterPlacement != null ? widget.isPlacementMode : _localPlacementMode;

  NoteDetail? get _effectiveActiveNote =>
      widget.activeNoteDetail ?? _localActiveNote;

  String get _effectiveDraftContent =>
      widget.onDraftContentChanged != null ? widget.draftContent : _localDraftContent;

  PaperColor get _effectiveDraftColor =>
      widget.onDraftPaperColorChanged != null ? widget.draftPaperColor : _localDraftColor;

  void _handleEnterPlacement() {
    if (widget.onEnterPlacement != null) {
      widget.onEnterPlacement!();
    } else {
      setState(() => _localPlacementMode = true);
    }
  }

  void _handleCancelPlacement() {
    if (widget.onCancelPlacement != null) {
      widget.onCancelPlacement!();
    } else {
      setState(() => _localPlacementMode = false);
    }
  }

  void _handleDraftContentChanged(String newContent) {
    if (widget.onDraftContentChanged != null) {
      widget.onDraftContentChanged!(newContent);
    } else {
      setState(() => _localDraftContent = newContent);
    }
  }

  void _handleDraftPaperColorChanged(PaperColor newColor) {
    if (widget.onDraftPaperColorChanged != null) {
      widget.onDraftPaperColorChanged!(newColor);
    } else {
      setState(() => _localDraftColor = newColor);
    }
  }

  void _handleConfirmPlacement() {
    if (widget.onConfirmPlacement != null) {
      widget.onConfirmPlacement!();
    } else {
      // Fallback xem trước cục bộ M1: đóng overlay và hiển thị phản hồi trung thực
      setState(() => _localPlacementMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thử nghiệm dán giấy trên bản xem trước cục bộ (M1 POC).'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleCloseReader() {
    if (widget.onCloseNoteDetail != null) {
      widget.onCloseNoteDetail!();
    } else {
      setState(() => _localActiveNote = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _effectiveActiveNote == null && !_effectivePlacementMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_effectiveActiveNote != null) {
          // No-op: NoteReaderSheet tự xử lý reverse animation và gọi onClose sau khi hoàn tất.
          return;
        }
        if (_effectivePlacementMode) {
          _handleCancelPlacement();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Tầng nền: Flame Canvas hoặc Nền giấy vi hạt tĩnh
            if (widget.gameWidget != null)
              widget.gameWidget!
            else
              SeamlessPaperBackground(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: PaperSheet(
                      showTape: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.pan_tool_alt_outlined,
                            size: 36,
                            color: AppColors.inkSecondary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Bức tường tĩnh lặng',
                            style: AppTypography.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Kéo theo bốn hướng để dạo bước hoặc chạm vào tờ giấy nhỏ để đọc tâm sự.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall,
                          ),
                          if (widget.gameWidget == null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.canvas,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.paperBorder, width: 1),
                              ),
                              child: const Text(
                                'Chờ kết nối Flame World (M1)',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Tầng HUD hoặc Lớp phủ soạn & dán giấy (Placement Overlay)
            if (_effectivePlacementMode)
              WallPlacementOverlay(
                draftContent: _effectiveDraftContent,
                paperColor: _effectiveDraftColor,
                onContentChanged: _handleDraftContentChanged,
                onPaperColorChanged: _handleDraftPaperColorChanged,
                isCellOccupied: widget.isPlacementCellOccupied,
                isSubmitting: widget.isPlacementSubmitting,
                onCancel: _handleCancelPlacement,
                onConfirm: _handleConfirmPlacement,
              )
            else
              WallHud(
                isExploring: widget.isExploring,
                onExploreOtherRegion: widget.onExploreOtherRegion,
                onEnterPlacement: _handleEnterPlacement,
              ),

            // 3. Tầng cao nhất: Modal đọc chi tiết tờ giấy (NoteReaderSheet)
            // Nhận activeNoteSourceRect làm gốc chuyển cảnh, nền mờ tĩnh, hỗ trợ fallback và giảm chuyển động
            if (_effectiveActiveNote != null)
              Positioned.fill(
                child: NoteReaderSheet(
                  key: ValueKey<String>(_effectiveActiveNote!.id),
                  note: _effectiveActiveNote!,
                  sourceRect: widget.activeNoteSourceRect,
                  sourceAngleRadians: widget.activeNoteSourceAngleRadians,
                  onClose: _handleCloseReader,
                  onEncourage: () =>
                      widget.onEncourageNote?.call(_effectiveActiveNote!),
                  onStartChat: () =>
                      widget.onStartChatNote?.call(_effectiveActiveNote!),
                  onEdit: () =>
                      widget.onEditNote?.call(_effectiveActiveNote!),
                  onDelete: () =>
                      widget.onDeleteNote?.call(_effectiveActiveNote!),
                  onReport: () =>
                      widget.onReportNote?.call(_effectiveActiveNote!),
                  onReportUser: () =>
                      widget.onReportUser?.call(_effectiveActiveNote!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
