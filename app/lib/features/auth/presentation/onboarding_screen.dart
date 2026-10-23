import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/paper_button.dart';
import '../../../core/widgets/paper_sheet.dart';

/// Màn hình Cam kết độ tuổi 18+ & Quy tắc cộng đồng (S02 — Onboarding).
///
/// Xuất hiện sau khi người dùng đăng nhập lần đầu tiên thành công.
/// Người dùng bắt buộc phải xác nhận đủ 18 tuổi và đồng ý với các quy tắc
/// bảo vệ không gian tĩnh lặng trước khi được cấp quyền tham gia bức tường chung.
class OnboardingScreen extends StatefulWidget {
  /// Callback khi hoàn tất onboarding, gửi thông tin consent cho backend ghi nhận.
  final Future<void> Function({
    required bool adultConfirmed,
    required bool termsAccepted,
    required bool privacyAccepted,
    required bool communityRulesAccepted,
    required bool onboardingAcknowledged,
  })? onCompleteOnboarding;

  /// Đang ghi nhận consent lên server.
  final bool isSubmitting;

  /// Thông báo lỗi từ server nếu có.
  final String? errorMessage;

  /// Callback mở xem toàn văn điều khoản.
  final VoidCallback? onOpenTerms;

  /// Callback mở xem toàn văn chính sách riêng tư.
  final VoidCallback? onOpenPrivacy;

  /// Callback mở xem quy tắc cộng đồng.
  final VoidCallback? onOpenGuidelines;

  const OnboardingScreen({
    super.key,
    this.onCompleteOnboarding,
    this.isSubmitting = false,
    this.errorMessage,
    this.onOpenTerms,
    this.onOpenPrivacy,
    this.onOpenGuidelines,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _adultConfirmed = false;
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _communityRulesAccepted = false;
  bool _onboardingAcknowledged = false;
  bool _isPending = false;
  String? _localError;

  bool get _effectiveSubmitting => widget.isSubmitting || _isPending;

  bool get _canProceed =>
      _adultConfirmed &&
      _termsAccepted &&
      _privacyAccepted &&
      _communityRulesAccepted &&
      _onboardingAcknowledged &&
      !_effectiveSubmitting &&
      widget.onCompleteOnboarding != null;

  Future<void> _handleComplete() async {
    if (!_canProceed || widget.onCompleteOnboarding == null) return;
    setState(() {
      _isPending = true;
      _localError = null;
    });

    try {
      await widget.onCompleteOnboarding!(
        adultConfirmed: _adultConfirmed,
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
        communityRulesAccepted: _communityRulesAccepted,
        onboardingAcknowledged: _onboardingAcknowledged,
      );
      if (mounted) {
        setState(() => _isPending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPending = false;
          _localError = e.toString().replaceFirst('Exception: ', '');
          // Giữ nguyên trạng thái đã tích của các checkbox khi có lỗi
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayError = _localError ?? widget.errorMessage;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: PaperSheet(
                showTape: true,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    const Icon(
                      Icons.spa_outlined,
                      size: 40,
                      color: AppColors.ink,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chào mừng bạn đến\nvới không gian tĩnh lặng',
                      textAlign: TextAlign.center,
                      style: AppTypography.displayLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Trước khi bắt đầu dán tờ giấy đầu tiên, xin hãy dành một phút để cùng chúng mình bảo vệ sự yên bình của Tường Nhỏ.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 20),

                    // Thông báo lỗi nếu có
                    if (displayError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.pink,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.paperBorder, width: 1),
                        ),
                        child: Text(
                          displayError,
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 4 Quy tắc cốt lõi
                    _buildRuleCard(
                      icon: Icons.eighteen_up_rating_outlined,
                      title: 'Chỉ dành cho người trưởng thành (18+)',
                      description:
                          'Tường Nhỏ là nơi người lớn giãi bày những âu lo và chia sẻ cảm xúc chân thật, không phục vụ đối tượng chưa đủ tuổi.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleCard(
                      icon: Icons.edit_calendar_outlined,
                      title: 'Một tờ giấy mỗi ngày',
                      description:
                          'Hạn mức 1 note/ngày (theo giờ Việt Nam) giúp mỗi chia sẻ đều được đắn đo trân trọng, tránh làm ồn ào bức tường.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleCard(
                      icon: Icons.favorite_border_rounded,
                      title: '5 lời động viên định sẵn',
                      description:
                          'Không có nút Like công khai hay bình luận tự do; người đọc chỉ có thể gửi gắm 1 trong 5 thông điệp ấm áp.',
                    ),
                    const SizedBox(height: 10),
                    _buildRuleCard(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Trò chuyện 3 tin liên tiếp',
                      description:
                          'Mỗi cuộc trò chuyện riêng tư chỉ được gửi tối đa 3 tin nhắn liên tiếp cho đến khi người kia phản hồi, chống quấy rối.',
                    ),
                    const SizedBox(height: 20),

                    // Nhóm 5 Checkbox cam kết độc lập (Bắt buộc riêng biệt — không gộp hay suy diễn)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.paperBorder, width: 1),
                      ),
                      child: Column(
                        children: [
                          // 1. Độ tuổi 18+
                          _ConsentCheckbox(
                            value: _adultConfirmed,
                            enabled: !_effectiveSubmitting,
                            onChanged: (val) => setState(() => _adultConfirmed = val ?? false),
                            label: 'Tôi cam kết tôi từ đủ 18 tuổi trở lên.',
                          ),
                          const Divider(color: AppColors.paperBorder, height: 12),
                          // 2. Điều khoản sử dụng
                          _ConsentCheckbox(
                            value: _termsAccepted,
                            enabled: !_effectiveSubmitting,
                            onChanged: (val) => setState(() => _termsAccepted = val ?? false),
                            label: 'Tôi đồng ý với Điều khoản sử dụng dịch vụ.',
                          ),
                          const Divider(color: AppColors.paperBorder, height: 12),
                          // 3. Chính sách riêng tư
                          _ConsentCheckbox(
                            value: _privacyAccepted,
                            enabled: !_effectiveSubmitting,
                            onChanged: (val) => setState(() => _privacyAccepted = val ?? false),
                            label:
                                'Tôi đồng ý với Chính sách riêng tư (ẩn danh trước người dùng khác, không ẩn danh với nhà cung cấp dịch vụ).',
                          ),
                          const Divider(color: AppColors.paperBorder, height: 12),
                          // 4. Quy tắc cộng đồng
                          _ConsentCheckbox(
                            value: _communityRulesAccepted,
                            enabled: !_effectiveSubmitting,
                            onChanged: (val) =>
                                setState(() => _communityRulesAccepted = val ?? false),
                            label:
                                'Tôi cam kết tuân thủ Quy tắc cộng đồng (giữ gìn sự tĩnh lặng, không quấy rối, không thù ghét, không spam).',
                          ),
                          const Divider(color: AppColors.paperBorder, height: 12),
                          // 5. Xác nhận hiểu cơ chế hoạt động
                          _ConsentCheckbox(
                            value: _onboardingAcknowledged,
                            enabled: !_effectiveSubmitting,
                            onChanged: (val) =>
                                setState(() => _onboardingAcknowledged = val ?? false),
                            label:
                                'Tôi đã đọc và hiểu cách hoạt động của Tường Nhỏ (1 tờ giấy/ngày, giới hạn 3 tin nhắn liên tiếp).',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (widget.onCompleteOnboarding == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Chế độ xem trước giao diện: Cần kết nối AuthFlowController để lưu cam kết.',
                          style: AppTypography.caption.copyWith(color: AppColors.inkSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Nút tiếp tục
                    PaperButton(
                      label: _effectiveSubmitting
                          ? 'Đang ghi nhận...'
                          : widget.onCompleteOnboarding != null
                              ? 'Bước vào Tường Nhỏ'
                              : 'Bước vào Tường Nhỏ (Chờ kết nối Auth)',
                      icon: Icons.arrow_forward_rounded,
                      isPrimary: true,
                      onPressed: _canProceed ? _handleComplete : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuleCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paperSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.paperBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.labelLarge),
                const SizedBox(height: 3),
                Text(description, style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final bool enabled;

  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: AppColors.ink,
                checkColor: AppColors.paperSurface,
                side: const BorderSide(color: AppColors.ink, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: enabled ? AppColors.ink : AppColors.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
