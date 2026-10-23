import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/domain/note_detail.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_sheet.dart';

/// Màn hình đọc chi tiết tờ giấy (Open Note — S04).
///
/// Hỗ trợ:
/// 1. Hiệu ứng bay ra từ tọa độ tờ giấy đã chạm (`sourceRect`) về giữa màn hình.
/// 2. Nền mờ (Backdrop Dim) hoàn toàn tĩnh tại (Stationary), chỉ thay đổi độ mờ.
/// 3. Fallback fade/scale nhẹ nhàng ở giữa màn hình khi `sourceRect == null`.
/// 4. Khôi phục góc xoay từ `sourceAngleRadians` về 0° khi mở và xoay ngược lại khi đóng.
/// 5. Chế độ giảm chuyển động (`MediaQuery.disableAnimations`): fade đơn giản, không dịch chuyển/xoay/co giãn (ALL_IN_ONE_SPEC.md §198 & §684).
/// 6. Xử lý nút Back và chạm ngoài để đóng tờ giấy với animation thu về `sourceRect` & `sourceAngleRadians`.
class NoteReaderSheet extends StatefulWidget {
  final NoteDetail note;
  final Rect? sourceRect;
  final double? sourceAngleRadians;
  final VoidCallback onClose;
  final VoidCallback? onEncourage;
  final VoidCallback? onStartChat;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onReportUser;

  const NoteReaderSheet({
    super.key,
    required this.note,
    this.sourceRect,
    this.sourceAngleRadians,
    required this.onClose,
    this.onEncourage,
    this.onStartChat,
    this.onEdit,
    this.onDelete,
    this.onReport,
    this.onReportUser,
  });

  @override
  State<NoteReaderSheet> createState() => _NoteReaderSheetState();
}

class _NoteReaderSheetState extends State<NoteReaderSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curvedAnimation;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      // Reduced motion: hiệu ứng mờ dần (fade) ngắn gọn (~150ms mở, ~120ms đóng), không giật ngay lập tức
      _controller.duration = const Duration(milliseconds: 150);
      _controller.reverseDuration = const Duration(milliseconds: 120);
    } else {
      _controller.duration = const Duration(milliseconds: 300);
      _controller.reverseDuration = const Duration(milliseconds: 240);
    }

    if (!_isClosing && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant NoteReaderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _isClosing = false;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleClose() {
    if (_isClosing) return;
    _isClosing = true;

    // Cả chế độ chuẩn lẫn reduced motion đều chạy controller.reverse().
    // Ở reduced motion, controller.reverse() mờ dần nhanh (~120ms) mà không di chuyển/xoay/co giãn.
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onClose();
      }
    });
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleClose();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tính tâm đích từ kích thước layout cục bộ (khớp với tọa độ WallScreen/GameWidget)
          final targetCenter = Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
          );

          return AnimatedBuilder(
            animation: _curvedAnimation,
            builder: (context, child) {
              final t = _curvedAnimation.value;

              // Tính toán vị trí, tỷ lệ scale, góc xoay và độ mờ của tờ giấy
              final Offset currentOffset;
              final double currentScale;
              final double currentRotation;
              final double currentOpacity = t.clamp(0.0, 1.0).toDouble();

              if (disableAnimations) {
                // Per ALL_IN_ONE_SPEC.md §198 & §684:
                // Reduced motion: fade đơn giản, không dịch chuyển, co giãn hay xoay
                currentOffset = Offset.zero;
                currentScale = 1.0;
                currentRotation = 0.0;
              } else if (widget.sourceRect != null) {
                final sourceCenter = widget.sourceRect!.center;
                final delta = sourceCenter - targetCenter;

                // Ước tính kích thước tờ giấy mục tiêu ở giữa màn hình từ constraints cục bộ
                final targetWidth = math.min(constraints.maxWidth - 48, 420.0);
                final targetHeight = math.min(constraints.maxHeight - 64, 520.0);

                final scaleX = (widget.sourceRect!.width / targetWidth).clamp(0.15, 0.85).toDouble();
                final scaleY = (widget.sourceRect!.height / targetHeight).clamp(0.15, 0.85).toDouble();
                final initialScale = (scaleX + scaleY) / 2;

                currentOffset = Offset.lerp(delta, Offset.zero, t)!;
                currentScale = _lerp(initialScale, 1.0, t);

                // Nội suy góc xoay từ góc Flame trên canvas (sourceAngleRadians) về 0 khi mở, và ngược lại khi đóng
                final initialAngle = widget.sourceAngleRadians ?? 0.0;
                currentRotation = _lerp(initialAngle, 0.0, t);
              } else {
                // Fallback khi không có sourceRect: giữ ở giữa màn hình, scale nhẹ 0.94 -> 1.0
                currentOffset = Offset.zero;
                currentScale = _lerp(0.94, 1.0, t);
                final initialAngle = widget.sourceAngleRadians ?? 0.0;
                currentRotation = _lerp(initialAngle, 0.0, t);
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Lớp phủ làm mờ nền tường (Backdrop Dim) — HOÀN TOÀN TĨNH TẠI, chỉ Fade
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _handleClose,
                      behavior: HitTestBehavior.opaque,
                      child: ColoredBox(
                        color: Color.fromRGBO(85, 72, 62, 0.4 * currentOpacity),
                      ),
                    ),
                  ),

                  // 2. Tờ giấy lớn trung tâm — Di chuyển, xoay và co giãn mượt mà từ sourceRect & sourceAngleRadians
                  Center(
                    child: Transform.translate(
                      offset: currentOffset,
                      child: Transform.rotate(
                        angle: currentRotation,
                        child: Transform.scale(
                          scale: currentScale,
                          child: Opacity(
                            opacity: currentOpacity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                  maxHeight: 600,
                                ),
                                child: PaperSheet(
                                  paperColor: widget.note.paperColor,
                                  showTape: true,
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Header: Thời gian tương đối + nút Đóng (X) + nút Báo cáo
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.access_time_rounded,
                                            size: 14,
                                            color: AppColors.inkSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _statusLabel(widget.note),
                                            style: AppTypography.caption,
                                          ),
                                          const Spacer(),
                                          // Nút Báo cáo tờ giấy (chỉ hiển thị nếu không phải chủ sở hữu)
                                          if (!widget.note.isOwner && widget.onReport != null)
                                            Semantics(
                                              button: true,
                                              label: 'Báo cáo tờ giấy',
                                              child: IconButton(
                                                icon: const Icon(Icons.flag_outlined, size: 18),
                                                color: AppColors.inkSecondary,
                                                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                                tooltip: 'Báo cáo tờ giấy',
                                                onPressed: widget.onReport,
                                              ),
                                            ),
                                          // Nút Báo cáo người dùng (chỉ hiển thị nếu không phải chủ sở hữu)
                                          if (!widget.note.isOwner && widget.onReportUser != null)
                                            Semantics(
                                              button: true,
                                              label: 'Báo cáo người dùng',
                                              child: IconButton(
                                                icon: const Icon(Icons.person_off_outlined, size: 18),
                                                color: AppColors.inkSecondary,
                                                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                                tooltip: 'Báo cáo người dùng',
                                                onPressed: widget.onReportUser,
                                              ),
                                            ),
                                          // Nút Đóng (X)
                                          Semantics(
                                            button: true,
                                            label: 'Đóng tờ giấy',
                                            child: IconButton(
                                              icon: const Icon(Icons.close_rounded, size: 20),
                                              color: AppColors.ink,
                                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                              tooltip: 'Đóng',
                                              onPressed: _handleClose,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // Nội dung tâm sự (1 - 1.000 graphemes)
                                      Flexible(
                                        child: SingleChildScrollView(
                                          child: SelectableText(
                                            widget.note.content,
                                            style: AppTypography.bodyLarge.copyWith(
                                              height: 1.6,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 16),
                                      const Divider(color: AppColors.paperBorder, height: 1),
                                      const SizedBox(height: 16),

                                      // Thông báo nếu tác giả tắt nhận tin nhắn
                                      if (!widget.note.isOwner && !widget.note.allowChat) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0x1A55483E),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.chat_bubble_outline_rounded,
                                                  size: 14, color: AppColors.inkSecondary),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Người viết đã tắt nhận trò chuyện từ tờ giấy này.',
                                                  style: AppTypography.caption,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],

                                      // Hàng nút hành động (CTAs)
                                      if (widget.note.isOwner)
                                        // CTAs cho chủ sở hữu: Sửa / Xóa
                                        Row(
                                          children: [
                                            if (widget.note.canEdit)
                                              Expanded(
                                                child: PaperButton(
                                                  label: 'Sửa',
                                                  icon: Icons.edit_outlined,
                                                  isPrimary: false,
                                                  onPressed: widget.onEdit,
                                                ),
                                              ),
                                            if (widget.note.canEdit && widget.note.canDelete)
                                              const SizedBox(width: 10),
                                            if (widget.note.canDelete)
                                              Expanded(
                                                child: PaperButton(
                                                  label: 'Xóa giấy',
                                                  icon: Icons.delete_outline_rounded,
                                                  isPrimary: !widget.note.canEdit,
                                                  backgroundColor: AppColors.pink,
                                                  onPressed: widget.onDelete,
                                                ),
                                              ),
                                          ],
                                        )
                                      else
                                        // CTAs cho người đọc: Động viên / Nhắn tin
                                        Row(
                                          children: [
                                            // Nút Động viên
                                            Expanded(
                                              child: PaperButton(
                                                label: 'Động viên',
                                                icon: Icons.favorite_border_rounded,
                                                isPrimary: !widget.note.canStartChat || !widget.note.allowChat,
                                                onPressed: widget.note.canEncourage ? widget.onEncourage : null,
                                              ),
                                            ),
                                            // Nút Nhắn tin (nếu cho phép)
                                            if (widget.note.allowChat) ...[
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: PaperButton(
                                                  label: 'Nhắn tin',
                                                  icon: Icons.chat_bubble_outline_rounded,
                                                  isPrimary: true,
                                                  onPressed: widget.note.canStartChat ? widget.onStartChat : null,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Định dạng thời gian tương đối theo tiếng Việt
  static String _statusLabel(NoteDetail note) {
    if (note.status == 'pending_review') return 'Đang chờ duyệt';
    if (note.status == 'deleted') return 'Tờ giấy đã được gỡ bỏ';
    final publishedAt = note.publishedAt;
    if (publishedAt == null) return 'Chưa được xuất bản';
    return _formatRelativeTime(publishedAt);
  }

  static String _formatRelativeTime(DateTime publishedAt) {
    final now = DateTime.now();
    final difference = now.difference(publishedAt);

    if (difference.inMinutes < 1) {
      return 'Vừa xong';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${publishedAt.day}/${publishedAt.month}/${publishedAt.year}';
    }
  }
}
