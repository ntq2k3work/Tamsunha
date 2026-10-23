import 'package:flutter/material.dart';
import '../../../../core/domain/paper_color.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_sheet.dart';

/// Lớp phủ chế độ dán giấy (Placement Mode — S06) kết hợp trình soạn thảo (Composer — S05).
///
/// Thiết kế tối ưu khả năng tương tác (Usability & Gesture Pass-through):
/// 1. Trình soạn thảo và bộ chọn màu được gom gọn vào khung phía trên (Top Bounded Panel).
/// 2. Bỏ toàn bộ `Positioned.fill` che khuất màn hình; vùng tường trung tâm để trống hoàn toàn
///    giúp sự kiện chạm/kéo/pan truyền thẳng xuống `GameWidget` của Flame.
/// 3. Hàng chọn 5 màu pastel sử dụng `Wrap` tự động thích ứng với màn hình nhỏ (320dp).
/// 4. Giữ nguyên toàn bộ logic validation 1 - 1.000 graphemes, callbacks và nhãn trung thực.
class WallPlacementOverlay extends StatefulWidget {
  final String draftContent;
  final PaperColor paperColor;
  final ValueChanged<String> onContentChanged;
  final ValueChanged<PaperColor> onPaperColorChanged;
  final bool isCellOccupied;
  final bool isSubmitting;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  const WallPlacementOverlay({
    super.key,
    required this.draftContent,
    required this.paperColor,
    required this.onContentChanged,
    required this.onPaperColorChanged,
    this.isCellOccupied = false,
    this.isSubmitting = false,
    this.onCancel,
    this.onConfirm,
  });

  @override
  State<WallPlacementOverlay> createState() => _WallPlacementOverlayState();
}

class _WallPlacementOverlayState extends State<WallPlacementOverlay> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.draftContent);
  }

  @override
  void didUpdateWidget(covariant WallPlacementOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftContent != widget.draftContent &&
        _textController.text != widget.draftContent) {
      _textController.value = _textController.value.copyWith(
        text: widget.draftContent,
        selection: TextSelection.collapsed(offset: widget.draftContent.length),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _graphemeCount => widget.draftContent.characters.length;
  bool get _isContentEmpty => widget.draftContent.trim().isEmpty;
  bool get _isContentOverLimit => _graphemeCount > 1000;
  bool get _isContentValid => !_isContentEmpty && !_isContentOverLimit;
  bool get _canConfirm => _isContentValid && !widget.isCellOccupied && !widget.isSubmitting;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: [
        // 1. Khung soạn thảo & chọn màu phía trên (Bounded Upper Panel)
        // Chỉ vùng hiển thị của panel này mới nhận touch events; vùng xung quanh để trống.
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 380,
                  maxHeight: screenHeight * 0.52,
                ),
                child: SingleChildScrollView(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tiêu đề hướng dẫn nhỏ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.paperSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.paperBorder, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note_rounded, size: 16, color: AppColors.inkSecondary),
                            SizedBox(width: 6),
                            Text(
                              'Soạn tâm sự & kéo tường chọn ô',
                              style: AppTypography.labelLarge,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Tờ giấy nháp tích hợp trình soạn thảo (Gọn gàng 2-4 dòng)
                      PaperSheet(
                        paperColor: widget.paperColor,
                        showTape: true,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _textController,
                              onChanged: widget.onContentChanged,
                              maxLines: 4,
                              minLines: 2,
                              maxLength: 1000,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Viết vài dòng tâm tư của bạn hôm nay...',
                                hintStyle: AppTypography.bodyMedium.copyWith(
                                  color: const Color(0x9982756A),
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                counter: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _isContentEmpty
                                            ? 'Cần ít nhất 1 ký tự'
                                            : (_isContentOverLimit
                                                ? 'Vượt quá giới hạn'
                                                : 'Hợp lệ'),
                                        style: AppTypography.caption.copyWith(
                                          color: _isContentOverLimit
                                              ? AppColors.danger
                                              : AppColors.inkSecondary,
                                        ),
                                      ),
                                      Text(
                                        '$_graphemeCount / 1.000',
                                        style: AppTypography.caption.copyWith(
                                          color: _isContentOverLimit
                                              ? AppColors.danger
                                              : AppColors.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Bộ chọn 5 màu giấy pastel tự co giãn / xuống dòng ở màn hình hẹp (320dp)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.paperSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.paperBorder, width: 1),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Màu giấy:',
                              style: AppTypography.bodySmall,
                            ),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: PaperColor.values.map((color) {
                                final isSelected = widget.paperColor == color;
                                return Semantics(
                                  button: true,
                                  label: AppColors.labelForPaper(color),
                                  selected: isSelected,
                                  child: InkWell(
                                    onTap: () => widget.onPaperColorChanged(color),
                                    borderRadius: BorderRadius.circular(22),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 44,
                                        minHeight: 44,
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: AppColors.colorForPaper(color),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.ink
                                                  : AppColors.paperBorder,
                                              width: isSelected ? 2.5 : 1.0,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  size: 15,
                                                  color: AppColors.ink,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Trạng thái kiểm tra chiếm dụng của ô
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isCellOccupied ? AppColors.pink : AppColors.sage,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.isCellOccupied ? AppColors.danger : AppColors.success,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isCellOccupied
                                  ? Icons.block_rounded
                                  : Icons.check_circle_outline_rounded,
                              size: 14,
                              color: widget.isCellOccupied ? AppColors.danger : AppColors.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isCellOccupied
                                  ? 'Chỗ này đã có giấy'
                                  : 'Khoảng trống hợp lệ trên tường',
                              style: AppTypography.caption.copyWith(
                                color: widget.isCellOccupied ? AppColors.danger : AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // [KHÔNG GIAN TRỐNG Ở GIỮA]:
        // Toàn bộ vùng màn hình giữa khung trên và thanh dưới hoàn toàn không có widget che phủ.
        // Mọi cử chỉ vuốt, kéo, pan camera hay chạm ô đều truyền thẳng xuống GameWidget của Flame.

        // 2. Thanh nút hành động dưới cùng (Hủy / Dán tại đây)
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: PaperSheet(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Nút Hủy
                      Expanded(
                        child: PaperButton(
                          label: 'Hủy',
                          isPrimary: false,
                          onPressed: widget.isSubmitting ? null : widget.onCancel,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Nút Dán tại đây (kiểm soát chặt chẽ validation)
                      Expanded(
                        flex: 2,
                        child: widget.isSubmitting
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.ink),
                                  ),
                                ),
                              )
                            : PaperButton(
                                label: 'Dán tại đây',
                                isPrimary: true,
                                icon: Icons.push_pin_outlined,
                                onPressed: _canConfirm ? widget.onConfirm : null,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
