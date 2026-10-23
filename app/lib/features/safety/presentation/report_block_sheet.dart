import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_button.dart';
import '../../../core/widgets/paper_sheet.dart';

/// 7 lý do báo cáo theo đặc tả ALL_IN_ONE_SPEC.md §4.5 & §254
class ReportReasonOption {
  final String key;
  final String title;
  final String subtitle;

  const ReportReasonOption({
    required this.key,
    required this.title,
    required this.subtitle,
  });

  static const List<ReportReasonOption> options = [
    ReportReasonOption(
      key: 'harassment',
      title: 'Quấy rối hoặc đe dọa',
      subtitle: 'Tin nhắn gây áp lực, tấn công cá nhân hoặc làm phiền liên tục',
    ),
    ReportReasonOption(
      key: 'hate',
      title: 'Ngôn từ thù ghét',
      subtitle: 'Kỳ thị vùng miền, giới tính, tôn giáo hoặc phân biệt đối xử',
    ),
    ReportReasonOption(
      key: 'sexual_content',
      title: 'Nội dung khiêu dâm / không phù hợp',
      subtitle: 'Nội dung tình dục rõ ràng hoặc hình ảnh nhạy cảm',
    ),
    ReportReasonOption(
      key: 'self_harm_concern',
      title: 'Lo ngại tự hại / khủng hoảng tinh thần',
      subtitle: 'Biểu hiện ý định tự gây thương tích hoặc khủng hoảng nghiêm trọng',
    ),
    ReportReasonOption(
      key: 'personal_info',
      title: 'Lộ thông tin cá nhân (Doxxing)',
      subtitle: 'Chia sẻ số điện thoại, địa chỉ, tài khoản mạng xã hội của người khác',
    ),
    ReportReasonOption(
      key: 'spam',
      title: 'Spam hoặc quảng cáo',
      subtitle: 'Quảng cáo thương mại, liên kết lừa đảo hoặc nội dung lặp lại',
    ),
    ReportReasonOption(
      key: 'other',
      title: 'Lý do khác',
      subtitle: 'Hành vi vi phạm quy tắc cộng đồng khác',
    ),
  ];
}

/// Modal / Bottom Sheet Báo cáo & Chặn đối phương (S12 — Report & Block).
///
/// Hỗ trợ:
/// 1. Báo cáo với 7 danh mục lý do chuẩn hóa.
/// 2. Hướng dẫn đường dây nóng cứu trợ tâm lý ngay khi chọn lý do tự hại (§255).
/// 3. Lựa chọn chặn hai chiều tương tác mà không phơi bày danh tính đối phương (§253).
class ReportBlockSheet extends StatefulWidget {
  final String targetId;
  final String targetType; // 'note' | 'conversation' | 'message' | 'user'
  final bool isSubmitting;
  final String? errorMessage;
  final void Function({
    required String reason,
    String? detail,
    required bool blockPartner,
  })? onSubmitReport;
  final VoidCallback? onBlockOnly;
  final VoidCallback? onClose;

  const ReportBlockSheet({
    super.key,
    required this.targetId,
    this.targetType = 'note',
    this.isSubmitting = false,
    this.errorMessage,
    this.onSubmitReport,
    this.onBlockOnly,
    this.onClose,
  });

  @override
  State<ReportBlockSheet> createState() => _ReportBlockSheetState();
}

class _ReportBlockSheetState extends State<ReportBlockSheet> {
  String? _selectedReasonKey;
  final TextEditingController _detailController = TextEditingController();
  bool _blockPartner = true;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_selectedReasonKey == null || widget.isSubmitting || widget.onSubmitReport == null) return;

    widget.onSubmitReport!(
      reason: _selectedReasonKey!,
      detail: _detailController.text.trim().isEmpty ? null : _detailController.text.trim(),
      blockPartner: _blockPartner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUserReport = widget.targetType == 'user';
    final isSelfHarm = _selectedReasonKey == 'self_harm_concern';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: PaperSheet(
            showTape: true,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      isUserReport ? Icons.person_off_outlined : Icons.shield_outlined,
                      size: 22,
                      color: AppColors.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isUserReport ? 'Báo cáo người dùng ẩn danh' : 'Báo cáo & Giữ an toàn',
                        style: AppTypography.titleLarge,
                      ),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppColors.inkSecondary,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: widget.isSubmitting ? null : widget.onClose,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isUserReport
                      ? 'Báo cáo người dùng ẩn danh liên quan trong không gian này. Nội dung báo cáo chỉ hiển thị với đội ngũ kiểm duyệt để xem xét và không hiển thị cho người dùng khác.'
                      : 'Chọn lý do phù hợp để chúng mình kiểm tra và bảo vệ sự tĩnh lặng của không gian.',
                  style: AppTypography.caption,
                ),

                // Thông báo lỗi nếu có từ server
                if (widget.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.pink,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.paperBorder, width: 0.5),
                    ),
                    child: Text(
                      widget.errorMessage!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                // Thông báo chưa thể gửi báo cáo nếu callback vắng mặt
                if (widget.onSubmitReport == null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.paperBorder, width: 0.5),
                    ),
                    child: const Text(
                      'Chưa thể gửi báo cáo lúc này; hãy thử lại khi dịch vụ kết nối.',
                      style: AppTypography.caption,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Danh sách 7 lý do
                ...ReportReasonOption.options.map((option) {
                  final isSelected = _selectedReasonKey == option.key;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: widget.isSubmitting ? null : () => setState(() => _selectedReasonKey = option.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.paperButter : AppColors.paperSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppColors.ink : AppColors.paperBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Radio<String>(
                              value: option.key,
                              groupValue: _selectedReasonKey,
                              activeColor: AppColors.ink,
                              onChanged: widget.isSubmitting
                                  ? null
                                  : (val) => setState(() => _selectedReasonKey = val),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(option.title, style: AppTypography.labelLarge),
                                  Text(option.subtitle, style: AppTypography.caption),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // Thẻ thông tin cứu trợ khủng hoảng nếu chọn self_harm_concern (§255)
                if (isSelfHarm) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.paperSage,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.paperBorder, width: 1),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.health_and_safety_outlined, size: 18, color: AppColors.ink),
                            SizedBox(width: 6),
                            Text('Lưu ý an toàn sức khỏe', style: AppTypography.labelLarge),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Tường Nhỏ là không gian nhật ký cá nhân, KHÔNG phải là dịch vụ hỗ trợ khủng hoảng, can thiệp y tế hay chăm sóc sức khỏe tâm thần khẩn cấp.\n\n'
                          'Nếu bạn hoặc ai đó đang trong tình huống khẩn cấp hoặc có nguy cơ tự gây thương tích, xin vui lòng liên hệ ngay với các dịch vụ cấp cứu y tế hoặc cơ quan chức năng có thẩm quyền tại địa phương bạn đang sinh sống.',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],

                // Trường nhập mô tả chi tiết (tùy chọn <=500 ký tự)
                const SizedBox(height: 12),
                TextField(
                  controller: _detailController,
                  enabled: !widget.isSubmitting,
                  maxLength: 500,
                  maxLines: 2,
                  style: AppTypography.bodySmall,
                  decoration: InputDecoration(
                    hintText: 'Thêm thông tin chi tiết (không bắt buộc)...',
                    hintStyle: AppTypography.caption,
                    filled: true,
                    fillColor: AppColors.canvas,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.paperBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.paperBorder),
                    ),
                  ),
                ),

                // Checkbox đồng thời chặn tương tác (§253)
                InkWell(
                  onTap: widget.isSubmitting ? null : () => setState(() => _blockPartner = !_blockPartner),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _blockPartner,
                          activeColor: AppColors.ink,
                          onChanged: widget.isSubmitting
                              ? null
                              : (val) => setState(() => _blockPartner = val ?? true),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'Đồng thời chặn đối phương (ngăn gửi tin và động viên hai chiều)',
                            style: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                PaperButton(
                  label: widget.isSubmitting
                      ? 'Đang gửi...'
                      : (isUserReport ? 'Gửi báo cáo người dùng' : 'Gửi báo cáo an toàn'),
                  icon: Icons.send_rounded,
                  isPrimary: true,
                  onPressed: _selectedReasonKey != null &&
                          !widget.isSubmitting &&
                          widget.onSubmitReport != null
                      ? _handleSubmit
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
