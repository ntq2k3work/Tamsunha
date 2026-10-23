import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_button.dart';
import '../../../core/widgets/paper_sheet.dart';

/// 5 mẫu câu động viên định sẵn theo đặc tả ALL_IN_ONE_SPEC.md §4.3
class EncouragementTemplate {
  final String id;
  final String text;
  final IconData icon;
  final Color cardColor;

  const EncouragementTemplate({
    required this.id,
    required this.text,
    required this.icon,
    required this.cardColor,
  });

  static const List<EncouragementTemplate> all = [
    EncouragementTemplate(
      id: 'LISTEN',
      text: 'Mình đang lắng nghe bạn',
      icon: Icons.hearing_rounded,
      cardColor: AppColors.paperButter,
    ),
    EncouragementTemplate(
      id: 'TOMORROW',
      text: 'Ngày mai sẽ ổn hơn thôi',
      icon: Icons.wb_sunny_outlined,
      cardColor: AppColors.paperSage,
    ),
    EncouragementTemplate(
      id: 'TRIED',
      text: 'Bạn đã rất cố gắng rồi',
      icon: Icons.favorite_border_rounded,
      cardColor: AppColors.paperPink,
    ),
    EncouragementTemplate(
      id: 'THANKS',
      text: 'Cảm ơn bạn đã can đảm chia sẻ',
      icon: Icons.auto_awesome_outlined,
      cardColor: AppColors.paperBlue,
    ),
    EncouragementTemplate(
      id: 'HUG',
      text: 'Gửi bạn một cái ôm thật ấm',
      icon: Icons.spa_outlined,
      cardColor: AppColors.paperLilac,
    ),
  ];
}

/// Modal / Bottom Sheet chọn lời động viên (S07).
///
/// Người đọc có thể chọn 1 trong 5 câu động viên định sẵn để gửi tới chủ note.
/// Lời động viên được lưu độc lập, không phơi bày danh tính người gửi và không cộng like public.
class EncouragementSheet extends StatefulWidget {
  final String noteId;
  final bool isSubmitting;
  final bool alreadySent;
  final bool isOwner;
  final String? errorMessage;
  final Future<void> Function(String)? onSendEncouragement;
  final VoidCallback? onClose;

  const EncouragementSheet({
    super.key,
    required this.noteId,
    this.isSubmitting = false,
    this.alreadySent = false,
    this.isOwner = false,
    this.errorMessage,
    this.onSendEncouragement,
    this.onClose,
  });

  @override
  State<EncouragementSheet> createState() => _EncouragementSheetState();
}

class _EncouragementSheetState extends State<EncouragementSheet> {
  String? _selectedTemplateId;
  bool _isSending = false;
  String? _localError;

  bool get _effectiveSubmitting => widget.isSubmitting || _isSending;

  Future<void> _handleSend() async {
    if (_selectedTemplateId == null ||
        _effectiveSubmitting ||
        widget.alreadySent ||
        widget.onSendEncouragement == null) {
      return;
    }

    setState(() {
      _isSending = true;
      _localError = null;
    });

    try {
      await widget.onSendEncouragement!(_selectedTemplateId!);
      if (mounted) {
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = widget.alreadySent;
    final displayError = _localError ?? widget.errorMessage;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: PaperSheet(
            showTape: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header + Nút đóng (X)
                Row(
                  children: [
                    const Icon(
                      Icons.favorite_border_rounded,
                      size: 20,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Gửi lời động viên',
                        style: AppTypography.titleLarge,
                      ),
                    ),
                    if (widget.onClose != null)
                      Semantics(
                        button: true,
                        label: 'Đóng hộp động viên',
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: AppColors.inkSecondary,
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          onPressed: widget.onClose,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chọn một thông điệp để gửi đến người viết. Bạn hoàn toàn ẩn danh và không có số lượt like hiển thị công khai.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 16),

                // Trường hợp đã gửi trước đó
                if (isDone) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.paperSage,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.paperBorder, width: 1),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 32, color: AppColors.ink),
                        SizedBox(height: 8),
                        Text(
                          'Đã gửi lời động viên',
                          style: AppTypography.labelLarge,
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Người viết sẽ nhận được sự ấm áp này trong Hộp thư của họ. Tường Nhỏ giới hạn 1 lời động viên cho mỗi tờ giấy.',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PaperButton(
                    label: 'Đóng',
                    isPrimary: false,
                    onPressed: widget.onClose,
                  ),
                ] else if (widget.isOwner) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.paperButter,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.paperBorder, width: 1),
                    ),
                    child: const Text(
                      'Đây là tờ giấy của chính bạn. Bạn không thể tự gửi lời động viên cho mình.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PaperButton(
                    label: 'Đóng',
                    isPrimary: false,
                    onPressed: widget.onClose,
                  ),
                ] else ...[
                  // Thông báo lỗi nếu có
                  if (displayError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.pink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        displayError,
                        style: AppTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Danh sách 5 câu định sẵn
                  ...EncouragementTemplate.all.map((item) {
                    final isSelected = _selectedTemplateId == item.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: _effectiveSubmitting
                            ? null
                            : () => setState(() => _selectedTemplateId = item.id),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: item.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.ink : AppColors.paperBorder,
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(item.icon, size: 20, color: AppColors.ink),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.text,
                                  style: AppTypography.bodyMedium.copyWith(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.ink),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 12),
                  PaperButton(
                    label: _effectiveSubmitting
                        ? 'Đang gửi...'
                        : widget.onSendEncouragement != null
                            ? 'Gửi lời động viên'
                            : 'Gửi lời động viên (Chờ kết nối M3)',
                    icon: Icons.send_rounded,
                    isPrimary: true,
                    onPressed: _selectedTemplateId != null &&
                            !_effectiveSubmitting &&
                            widget.onSendEncouragement != null
                        ? _handleSend
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
